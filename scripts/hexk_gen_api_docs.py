#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Generate and check the per-module contract documents docs/api/<module>.md.

Source files under src/ carry //! tags in their header. Files with the same @module value
form one module and share one contract document.

    hexk_gen_api_docs.py           create missing documents, refresh the generated blocks
    hexk_gen_api_docs.py --check   write nothing; exit 1 on any finding

Generated blocks sit between <!-- HEXK_GEN:BEGIN name --> and <!-- HEXK_GEN:END name -->
markers; everything outside them is hand-written and never touched.

Checks (both modes):

  API-EMITS  every message ID in the source is listed in //! @emits and the reverse
  API-ID     message IDs of the library start with the upper-case prefix
  DOC-5      every public define, typedef, class, function and task has a comment line
             directly above it
  API-DOC    the contract document exists, has the nine sections in order (see
             docs/api/README.md), and its generated blocks are up to date           (--check only)

Limits: public member variables and covergroups are not listed and not
checked for DOC-5; macro arguments that carry a message ID are not followed.
"""

import argparse
import re
import sys
from pathlib import Path

LOWER = "hexk_"
UPPER = "HEXK_"
SV_SUFFIXES = (".sv", ".svh")
SECTIONS = (
    "1. Summary",
    "2. When to use / when not to use",
    "3. API",
    "4. Behaviour and invariants",
    "5. Configuration",
    "6. Messages emitted",
    "7. Minimal example",
    "8. Anti-patterns",
    "9. Status",
)
NOT_WRITTEN = "_Not written yet._"
SEVERITIES = ("info", "warning", "error", "fatal")

TAG_RE = re.compile(r"^//!\s*@(\w+)\s*(.*)$")
DEFINE_RE = re.compile(r"^\s*`define\s+(\w+)(\([^)]*\))?")
CONDITIONAL_RE = re.compile(r"^\s*`(?:ifdef|ifndef|elsif|else|endif|undef)\b")
CLASS_OPEN_RE = re.compile(r"^\s*(?:virtual\s+|interface\s+)?class\s+\w+")
SUBROUTINE_RE = re.compile(r"^\s*(?:(?:pure|virtual|static|extern)\s+)*(?:function|task)\b")
HIDDEN_RE = re.compile(r"^\s*(?:local|protected)\b")
ID_LITERAL_RE = re.compile('"(' + UPPER + '[A-Z0-9_]+)"')
REPORT_ID_RE = re.compile(r'`uvm_(?:info|warning|error|fatal)(?:_context)?\s*\(\s*"([^"]*)"')
BLOCK_RE = re.compile(r"<!-- HEXK_GEN:BEGIN (\w+) -->\n(.*?)<!-- HEXK_GEN:END \1 -->\n", re.DOTALL)


class Symbol:
    """A public declaration: what it is, its signature, its doc comment and where it is."""

    def __init__(self, kind, signature, doc, line):
        self.kind = kind
        self.signature = signature
        self.doc = doc
        self.line = line


class SourceFile:
    """Tags, public symbols and message IDs of one source file."""

    def __init__(self, root, path):
        self.rel = path.relative_to(root).as_posix()
        self.name = path.name
        self.lines = path.read_text(encoding="utf-8").split("\n")
        self.tags = {}
        self.summary = ""
        self.symbols = []
        self.ids = {}
        self.bad_ids = []
        self.parse_header()
        self.parse_symbols()
        self.parse_ids()

    def parse_header(self):
        for index, line in enumerate(self.lines):
            if not line.startswith("//"):
                break
            match = TAG_RE.match(line)
            if match:
                self.tags.setdefault(match.group(1), []).append(match.group(2).strip())
            elif index == 5:
                self.summary = line[2:].strip()

    def code_of(self, line):
        """The line without its trailing // comment."""
        return line.split("//", 1)[0].rstrip()

    def doc_above(self, index, skip_conditionals=False):
        """Comment lines directly above line index, joined; '' when there are none."""
        index -= 1
        while skip_conditionals and index >= 0 and CONDITIONAL_RE.match(self.lines[index]):
            index -= 1
        doc = []
        while index >= 0:
            text = self.lines[index].strip()
            if not text.startswith("//") or text.startswith("//!"):
                break
            doc.insert(0, text[2:].strip())
            index -= 1
        return " ".join(part for part in doc if part)

    def statement_from(self, index):
        """The declaration that starts on line index, up to its first ';' outside braces, on one line."""
        parts = []
        depth = 0
        for line in self.lines[index:]:
            code = self.code_of(line).strip()
            parts.append(code)
            depth += code.count("{") - code.count("}")
            if depth <= 0 and ";" in code.rsplit("}", 1)[-1]:
                break
        text = re.sub(r"\s+", " ", " ".join(parts))
        # The first ';' at brace depth 0 ends the declaration; those of a struct body are inside braces.
        depth = 0
        for position, char in enumerate(text):
            depth += (char == "{") - (char == "}")
            if char == ";" and depth == 0:
                return text[:position + 1]
        return text.rstrip(";") + ";"

    def parse_symbols(self):
        guard = self.name.upper().replace(".", "_")
        primary = self.name.rsplit(".", 1)[0]
        seen_defines = set()
        class_depth = 0
        for index, line in enumerate(self.lines):
            code = self.code_of(line)
            match = DEFINE_RE.match(code)
            if match:
                name = match.group(1)
                if name != guard and name not in seen_defines:
                    seen_defines.add(name)
                    signature = "`define " + name + (match.group(2) or "")
                    self.symbols.append(Symbol("define", signature, self.doc_above(index, True), index + 1))
                continue
            # A declaration in the body of a macro is documented by the comment of the macro.
            if index > 0 and self.lines[index - 1].rstrip().endswith("\\"):
                continue
            if CLASS_OPEN_RE.match(code):
                if class_depth == 0 and not re.search(r"\bclass\s+" + re.escape(primary) + r"\b", code):
                    self.symbols.append(Symbol("class", self.statement_from(index), self.doc_above(index), index + 1))
                class_depth += 1
                continue
            if re.search(r"\bendclass\b", code):
                class_depth = max(class_depth - 1, 0)
                continue
            if HIDDEN_RE.match(code):
                continue
            if SUBROUTINE_RE.match(code):
                kind = "task" if re.search(r"\btask\b", code.split("(", 1)[0]) else "function"
                self.symbols.append(Symbol(kind, self.statement_from(index), self.doc_above(index), index + 1))
            elif class_depth == 0 and re.match(r"^\s*typedef\b", code):
                statement = self.statement_from(index)
                if not re.match(r"^typedef\s+(?:class|interface\s+class)\s+\w+\s*;", statement):
                    self.symbols.append(Symbol("typedef", statement, self.doc_above(index), index + 1))

    def parse_ids(self):
        for index, line in enumerate(self.lines):
            code = self.code_of(line)
            for match in ID_LITERAL_RE.finditer(code):
                self.ids.setdefault(match.group(1), index + 1)
            for match in REPORT_ID_RE.finditer(code):
                if not match.group(1).startswith(UPPER):
                    self.bad_ids.append((index + 1, match.group(1)))


class Module:
    """All source files sharing one @module value."""

    def __init__(self, root, name):
        self.root = root
        self.name = name
        self.files = []

    def tag(self, name):
        """First value of a tag over the module's files, '' when absent."""
        for source in self.files:
            if source.tags.get(name):
                return source.tags[name][0]
        return ""

    def emits(self):
        """Return {ID: severity} from the @emits tags, and a list of malformed entries."""
        declared = {}
        malformed = []
        for source in self.files:
            for value in source.tags.get("emits", []):
                for token in value.split():
                    if token == "(none)":
                        continue
                    name, _, severity = token.partition(":")
                    if severity not in SEVERITIES:
                        malformed.append((source.rel, token))
                    declared[name] = severity
        return declared, malformed

    def block(self, name):
        """Content of one generated block."""
        if name == "files":
            return "".join(f"- `{source.rel}`\n" for source in self.files)
        if name == "api":
            return self.api_block()
        if name == "emits":
            declared, _ = self.emits()
            if not declared:
                return "This module emits no messages.\n"
            rows = "".join(f"| `{name}` | {declared[name]} |  |\n" for name in sorted(declared))
            return "| ID | Severity | Meaning |\n|---|---|---|\n" + rows
        if name == "status":
            return (
                "| Stability | Since |\n|---|---|\n"
                f"| {self.tag('stability') or '?'} | {self.tag('since') or '?'} |\n"
            )
        if name == "example":
            rel = f"examples/{self.name}/{self.name}_example.sv"
            path = self.root / rel
            if not path.is_file():
                return "No example file yet.\n"
            code = path.read_bytes().decode("utf-8")
            return f"`{rel}`, elaborated in Gate 1:\n\n```systemverilog\n{code}```\n"
        raise KeyError(name)

    def api_block(self):
        text = ""
        for source in self.files:
            symbols = source.symbols
            if not symbols:
                continue
            # Building blocks marked "Internal" are left out: the listing shows what users call.
            public = [symbol for symbol in symbols if not symbol.doc.startswith("Internal")]
            text += f"From `{source.rel}`:\n\n```systemverilog\n"
            for symbol in public:
                if symbol.doc:
                    text += f"// {symbol.doc}\n"
                text += f"{symbol.signature}\n"
            text += "```\n\n"
            if len(public) != len(symbols):
                text += ('The file also defines building blocks of these, marked "Internal" in the source; '
                         "they may change, do not call them.\n\n")
        return text.rstrip("\n") + "\n" if text else "No public symbols yet.\n"

    def skeleton(self):
        """A new contract document with every section and the generated blocks in place."""
        summary = next((source.summary for source in self.files if source.summary), NOT_WRITTEN)
        generated = {
            "3. API": ("files", "api"),
            "6. Messages emitted": ("emits",),
            "7. Minimal example": ("example",),
            "9. Status": ("status",),
        }
        text = f"# {self.name}\n"
        for section in SECTIONS:
            text += f"\n## {section}\n\n"
            if section == "1. Summary":
                text += summary + "\n"
                continue
            for name in generated.get(section, ()):
                text += f"<!-- HEXK_GEN:BEGIN {name} -->\n{self.block(name)}<!-- HEXK_GEN:END {name} -->\n\n"
            text += NOT_WRITTEN + "\n"
        return text


def collect_modules(root):
    """Return ({module name: Module}, findings) for all files under src/."""
    modules = {}
    findings = []
    for path in sorted((root / "src").rglob("*")):
        if not path.is_file() or path.suffix not in SV_SUFFIXES:
            continue
        source = SourceFile(root, path)
        names = source.tags.get("module")
        if not names:
            findings.append(f"{source.rel}:1: [API-DOC] no '//! @module' tag")
            continue
        modules.setdefault(names[0], Module(root, names[0])).files.append(source)
    return modules, findings


def check_module(module):
    """Source-level checks of one module; return a list of findings."""
    findings = []
    declared, malformed = module.emits()
    for rel, token in malformed:
        findings.append(f"{rel}:1: [API-EMITS] '@emits {token}' needs the form ID:info|warning|error|fatal")
    used = {}
    for source in module.files:
        for name, line in source.ids.items():
            used.setdefault(name, (source.rel, line))
        for line, name in source.bad_ids:
            findings.append(f"{source.rel}:{line}: [API-ID] message ID \"{name}\" must start with {UPPER}")
        for symbol in source.symbols:
            if not symbol.doc:
                findings.append(f"{source.rel}:{symbol.line}: [DOC-5] no doc comment above: {symbol.signature}")
    for name, (rel, line) in sorted(used.items()):
        if name not in declared:
            findings.append(f"{rel}:{line}: [API-EMITS] message ID {name} is not listed in //! @emits")
    for name in sorted(declared):
        if name not in used:
            findings.append(f"{module.files[0].rel}:1: [API-EMITS] @emits lists {name} but no source uses it")
    return findings


def refresh(module, text):
    """Return text with every generated block replaced by its current content."""
    def replace(match):
        name = match.group(1)
        try:
            return f"<!-- HEXK_GEN:BEGIN {name} -->\n{module.block(name)}<!-- HEXK_GEN:END {name} -->\n"
        except KeyError:
            return match.group(0)
    return BLOCK_RE.sub(replace, text)


def check_document(module, rel, text):
    """Structure checks of one contract document; return a list of findings."""
    findings = []
    position = 0
    for section in SECTIONS:
        found = text.find(f"\n## {section}\n", position)
        if found < 0:
            findings.append(f"{rel}:1: [API-DOC] section '## {section}' is missing or out of order")
        else:
            position = found
    blocks = {match.group(1) for match in BLOCK_RE.finditer(text)}
    for name in ("files", "api", "emits", "example", "status"):
        if name not in blocks:
            findings.append(f"{rel}:1: [API-DOC] generated block '{name}' is missing")
    if refresh(module, text) != text:
        findings.append(f"{rel}:1: [API-DOC] generated blocks are out of date (run 'make docs')")
    return findings


def main():
    parser = argparse.ArgumentParser(description="Generate and check docs/api contract documents.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: parent of scripts/)")
    parser.add_argument("--check", action="store_true", help="verify only, write nothing")
    args = parser.parse_args()
    root = args.root.resolve()
    api_dir = root / "docs" / "api"

    modules, findings = collect_modules(root)
    written = []
    for name in sorted(modules):
        module = modules[name]
        findings.extend(check_module(module))
        path = api_dir / f"{name}.md"
        rel = path.relative_to(root).as_posix()
        if not path.is_file():
            if args.check:
                findings.append(f"{rel}:1: [API-DOC] contract document is missing (run 'make docs')")
                continue
            api_dir.mkdir(parents=True, exist_ok=True)
            path.write_bytes(module.skeleton().encode("utf-8"))
            written.append(rel)
            continue
        text = path.read_bytes().decode("utf-8")
        if not args.check and refresh(module, text) != text:
            text = refresh(module, text)
            path.write_bytes(text.encode("utf-8"))
            written.append(rel)
        findings.extend(check_document(module, rel, text))
    known = {f"{name}.md" for name in modules} | {"README.md"}
    for path in sorted(api_dir.glob("*.md")):
        if path.name not in known:
            findings.append(f"docs/api/{path.name}:1: [API-DOC] no source file has '//! @module {path.stem}'")

    for rel in written:
        print(f"hexk_gen_api_docs: wrote {rel}")
    for finding in findings:
        print(finding)
    print(f"hexk_gen_api_docs: {len(modules)} modules, {len(findings)} findings")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
