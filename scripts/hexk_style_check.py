#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Library style checks that Verible does not cover (Gate 1).

Checks every .sv/.svh file under src/, tests/ and examples/ for:

  LIB-HDR   file header template (SPDX, copyright, file name, DOC-1 text)
  LIB-TAG   //! contract tags @module, @since, @stability            (src/ only)
  FIL-6     include guard named after the file                        (src/ only)
  LIB-PFX   library prefix on packages, classes, interfaces, modules, typedefs, enum
            literals and defines
  LIB-CORE  no UVM in src/core
  NAM-3/4   no m_ or leading-underscore names
  FIL-7     no `timescale, every delay literal has a unit
  FAC-4     no field macros in components
  FAC-7/8   no `uvm_do* family, no `uvm_declare_p_sequencer
  IFC-2     no program blocks
  DOC-6     TODO format
  FMT-1/2/3 no tabs, ASCII only, no trailing whitespace, LF line ends, one final newline,
            lines up to 120 columns

Rule IDs other than LIB-* are the IDs of the HEXK SystemVerilog/UVM style guide.

Waivers live in tests/lint/hexk_style_check.waiver, one per line:
    <RULE> <path glob> <reason, mandatory>

Exit status is 0 when there are no unwaived violations, 1 otherwise.
"""

import argparse
import fnmatch
import re
import sys
from pathlib import Path

LOWER = "hexk_"
UPPER = "HEXK_"
SCAN_DIRS = ("src", "tests", "examples")
SV_SUFFIXES = (".sv", ".svh")
WAIVER_FILE = "tests/lint/hexk_style_check.waiver"
MAX_COLUMNS = 120
ALLOWED_M_NAMES = {"m_sequencer"}  # documented UVM handle, allowed by FAC-11

SPDX_LINE = "// SPDX-License-Identifier: Apache-2.0"
COPYRIGHT_RE = re.compile(r"^// Copyright \(c\) \d{4} HEXK$")
TAG_RE = re.compile(r"^//!\s*@(\w+)\s*(.*)$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
TODO_WORD_RE = re.compile(r"\b(TODO|FIXME|XXX)\b")
TODO_FORMAT_RE = re.compile(r"^//\s*TODO:[A-Za-z0-9_]+:P[123]: \S")
DELAY_RE = re.compile(r"(?<!#)#\s*\d[\d_]*(?:\.\d+)?(?!\s*(?:fs|ps|ns|us|ms|s)\b)(?![\w.'])")
NAME_PREFIX_RE = re.compile(r"(?<![\w$`.])(m_\w+|_\w+)")
CLASS_OPEN_RE = re.compile(r"^\s*(?:virtual\s+|interface\s+)?class\s+(\w+)")
DECL_RES = (
    ("package", re.compile(r"^\s*package\s+(?:static\s+|automatic\s+)?(\w+)")),
    ("interface", re.compile(r"^\s*interface\s+(?!class\b)(?:static\s+|automatic\s+)?(\w+)")),
    ("module", re.compile(r"^\s*module\s+(?:static\s+|automatic\s+)?(\w+)")),
)
DEFINE_RE = re.compile(r"^\s*`define\s+(\w+)")
ENUM_BODY_RE = re.compile(r"\benum\b[^{;]*\{([^}]*)\}")
TYPEDEF_NAME_RE = re.compile(r"(\w+)\s*(?:\[[^\]]*\]\s*)*;\s*$")
UVM_SEQ_MACRO_RE = re.compile(r"`uvm_(?:do|create|send|rand_send)\w*|`uvm_declare_p_sequencer")
CORE_UVM_RE = re.compile(r"\buvm_pkg\b|`uvm_\w+|uvm_macros\.svh")


class Violation:
    """One finding: where, which rule, what."""

    def __init__(self, path, line, rule, text):
        self.path = path
        self.line = line
        self.rule = rule
        self.text = text

    def __str__(self):
        return f"{self.path}:{self.line}: [{self.rule}] {self.text}"


def blank_comments_and_strings(text):
    """Return (code, comments).

    code is text with comments and string-literal contents replaced by spaces, so that line
    and column positions are unchanged. comments is a list of (line number, comment text).
    """
    out = []
    comments = []
    i = 0
    line = 1
    size = len(text)
    while i < size:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < size else ""
        if ch == "/" and nxt == "/":
            end = text.find("\n", i)
            end = size if end < 0 else end
            comments.append((line, text[i:end]))
            out.append(" " * (end - i))
            i = end
        elif ch == "/" and nxt == "*":
            end = text.find("*/", i + 2)
            end = size if end < 0 else end + 2
            body = text[i:end]
            comments.append((line, body))
            out.append("".join("\n" if c == "\n" else " " for c in body))
            line += body.count("\n")
            i = end
        elif ch == '"':
            j = i + 1
            while j < size and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            j = min(j, size)
            out.append('"' + " " * (j - i - 1))
            if j < size and text[j] == '"':
                out.append('"')
                j += 1
            i = j
        else:
            if ch == "\n":
                line += 1
            out.append(ch)
            i += 1
    return "".join(out), comments


def has_prefix(name):
    """True when name carries the library prefix in either case."""
    return name.startswith(LOWER) or name.startswith(UPPER)


class FileChecker:
    """Runs every check on one file and collects the violations."""

    def __init__(self, root, path):
        self.path = path
        self.rel = path.relative_to(root).as_posix()
        self.in_src = self.rel.startswith("src/")
        self.in_core = self.rel.startswith("src/core/")
        self.raw = path.read_bytes()
        self.text = self.raw.decode("utf-8", errors="replace")
        self.lines = self.text.split("\n")
        self.code, self.comments = blank_comments_and_strings(self.text)
        self.code_lines = self.code.split("\n")
        self.violations = []

    def add(self, line, rule, text):
        self.violations.append(Violation(self.rel, line, rule, text))

    def run(self):
        self.check_text_hygiene()
        last_header_line = self.check_header()
        if self.in_src:
            self.check_tags()
            self.check_guard(last_header_line)
        self.check_prefixes()
        self.check_code_rules()
        self.check_todos()
        return self.violations

    def check_text_hygiene(self):
        if b"\r" in self.raw:
            self.add(1, "FMT-2", "CR characters found; files use LF line ends")
        if self.raw and not self.raw.endswith(b"\n"):
            self.add(len(self.lines), "FMT-2", "file does not end with a newline")
        if self.raw.endswith(b"\n\n"):
            self.add(len(self.lines), "FMT-2", "file ends with more than one newline")
        for num, line in enumerate(self.lines, 1):
            line = line.rstrip("\r")
            if "\t" in line:
                self.add(num, "FMT-1", "tab character")
            if not line.isascii():
                self.add(num, "FMT-2", "non-ASCII character")
            if line != line.rstrip():
                self.add(num, "FMT-2", "trailing whitespace")
            if len(line) > MAX_COLUMNS:
                self.add(num, "FMT-3", f"line is {len(line)} columns, limit is {MAX_COLUMNS}")

    def check_header(self):
        """Check the file header; return the index of the last header comment line."""
        lines = self.lines
        name = self.path.name
        expected = (
            (0, lambda s: s == SPDX_LINE, f"line 1 must be '{SPDX_LINE}'"),
            (1, lambda s: bool(COPYRIGHT_RE.match(s)), "line 2 must be '// Copyright (c) <year> HEXK'"),
            (2, lambda s: s == "//", "line 3 must be '//'"),
            (3, lambda s: s == f"// {name}", f"line 4 must be '// {name}'"),
            (4, lambda s: s == "//", "line 5 must be '//'"),
        )
        for index, test, text in expected:
            if index >= len(lines) or not test(lines[index]):
                self.add(index + 1, "LIB-HDR", text)
                return min(index, len(lines) - 1)
        if len(lines) < 6 or not re.match(r"^// \S", lines[5]):
            self.add(6, "LIB-HDR", "line 6 must start the DOC-1 description: a one-line summary")
        last = 4
        for index in range(5, len(lines)):
            if not lines[index].startswith("//"):
                break
            last = index
        return last

    def tags(self):
        """Return {tag: (line number, value)} of the //! lines in the header."""
        found = {}
        for num, line in enumerate(self.lines, 1):
            if not line.startswith("//"):
                break
            match = TAG_RE.match(line)
            if match:
                found.setdefault(match.group(1), (num, match.group(2).strip()))
        return found

    def check_tags(self):
        found = self.tags()
        for tag in ("module", "since", "stability"):
            if tag not in found:
                self.add(1, "LIB-TAG", f"header has no '//! @{tag}' tag")
        if "module" in found and not found["module"][1].startswith(LOWER):
            self.add(found["module"][0], "LIB-TAG", f"@module value must start with '{LOWER}'")
        if "since" in found and not SEMVER_RE.match(found["since"][1]):
            self.add(found["since"][0], "LIB-TAG", "@since value must be a version like 0.1.0")
        if "stability" in found and found["stability"][1] not in ("experimental", "stable"):
            self.add(found["stability"][0], "LIB-TAG", "@stability must be experimental or stable")

    def check_guard(self, last_header_line):
        guard = self.path.name.upper().replace(".", "_")
        body = [(num, line.strip()) for num, line in enumerate(self.lines, 1) if line.strip()]
        after_header = [(num, line) for num, line in body if num > last_header_line + 1]
        if len(after_header) < 3:
            self.add(len(self.lines), "FIL-6", f"file has no include guard {guard}")
            return
        (num_a, first), (num_b, second) = after_header[0], after_header[1]
        num_z, final = after_header[-1]
        if first != f"`ifndef {guard}":
            self.add(num_a, "FIL-6", f"first line after the header must be '`ifndef {guard}'")
        if second != f"`define {guard}":
            self.add(num_b, "FIL-6", f"second line after the header must be '`define {guard}'")
        if final != f"`endif  // {guard}":
            self.add(num_z, "FIL-6", f"last line must be '`endif  // {guard}' (two spaces, as Verible formats it)")

    def check_prefixes(self):
        class_depth = 0
        statement = None
        statement_line = 0
        for num, line in enumerate(self.code_lines, 1):
            match = DEFINE_RE.match(line)
            if match and not has_prefix(match.group(1)):
                self.add(num, "LIB-PFX", f"define '{match.group(1)}' needs the {UPPER} or {LOWER} prefix")
            for kind, regex in DECL_RES:
                match = regex.match(line)
                if match and not match.group(1).startswith(LOWER):
                    self.add(num, "LIB-PFX", f"{kind} '{match.group(1)}' needs the {LOWER} prefix")
            if re.match(r"^\s*program\b", line):
                self.add(num, "IFC-2", "program blocks are not used")
            match = CLASS_OPEN_RE.match(line)
            if match:
                if class_depth == 0 and not match.group(1).startswith(LOWER):
                    self.add(num, "LIB-PFX", f"class '{match.group(1)}' needs the {LOWER} prefix")
                class_depth += 1
            if re.search(r"\bendclass\b", line):
                class_depth = max(class_depth - 1, 0)
            if statement is None and class_depth == 0 and re.match(r"^\s*typedef\b", line):
                statement = ""
                statement_line = num
            if statement is not None:
                statement += " " + line.strip()
                if ";" in line and statement.count("{") == statement.count("}"):
                    self.check_typedef(statement_line, statement)
                    statement = None

    def check_typedef(self, num, statement):
        if re.match(r"^\s*typedef\s+(?:class|interface\s+class|enum|struct|union)\s+\w+\s*;", statement):
            return  # forward declaration; the real declaration is checked where it is
        match = TYPEDEF_NAME_RE.search(statement)
        if match and not match.group(1).startswith(LOWER):
            self.add(num, "LIB-PFX", f"typedef '{match.group(1)}' needs the {LOWER} prefix")
        body = ENUM_BODY_RE.search(statement)
        if not body:
            return
        for item in body.group(1).split(","):
            literal = re.match(r"\s*(\w+)", item)
            if literal and not literal.group(1).startswith(UPPER):
                self.add(num, "LIB-PFX", f"enum literal '{literal.group(1)}' needs the {UPPER} prefix")

    def check_code_rules(self):
        for num, line in enumerate(self.code_lines, 1):
            if "`timescale" in line:
                self.add(num, "FIL-7", "`timescale is not used; declare timeunit in the top module")
            if DELAY_RE.search(line):
                self.add(num, "FIL-7", "delay literal has no time unit")
            for match in NAME_PREFIX_RE.finditer(line):
                name = match.group(1)
                if name in ALLOWED_M_NAMES:
                    continue
                rule = "NAM-3" if name.startswith("m_") else "NAM-4"
                self.add(num, rule, f"name '{name}' uses a forbidden prefix")
            match = UVM_SEQ_MACRO_RE.search(line)
            if match:
                rule = "FAC-8" if "p_sequencer" in match.group(0) else "FAC-7"
                self.add(num, rule, f"{match.group(0)} is not used")
            if "`uvm_component_utils_begin" in line or "`uvm_component_param_utils_begin" in line:
                self.add(num, "FAC-4", "field macros are not used in components")
        if self.in_core:
            # Strings are blanked in self.code, so look at the text with only comments removed.
            for num, line in enumerate(self.lines, 1):
                bare = line.split("//", 1)[0]
                if CORE_UVM_RE.search(bare):
                    self.add(num, "LIB-CORE", "src/core must not reference UVM")

    def check_todos(self):
        for num, comment in self.comments:
            if TODO_WORD_RE.search(comment) and not TODO_FORMAT_RE.match(comment):
                self.add(num, "DOC-6", "TODO format is '// TODO:<owner>:<P1|P2|P3>: <text>'")


def load_waivers(root):
    """Return (waivers, problems); a waiver is (rule, path glob, reason, line number)."""
    waivers = []
    problems = []
    path = root / WAIVER_FILE
    if not path.is_file():
        return waivers, problems
    for num, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 2)
        if len(parts) < 3:
            problems.append(Violation(WAIVER_FILE, num, "LIB-WAIVE", "waiver needs '<RULE> <path glob> <reason>'"))
            continue
        waivers.append((parts[0], parts[1], parts[2], num))
    return waivers, problems


def find_files(root):
    """All SystemVerilog files in the scanned directories, sorted for stable output."""
    files = []
    for name in SCAN_DIRS:
        base = root / name
        if base.is_dir():
            files.extend(p for p in base.rglob("*") if p.is_file() and p.suffix in SV_SUFFIXES)
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(description="hexk-sv-lib library style check (Gate 1).")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: parent of scripts/)")
    parser.add_argument("files", nargs="*", type=Path, help="check only these files (default: all)")
    args = parser.parse_args()
    root = args.root.resolve()

    files = [f.resolve() for f in args.files] if args.files else find_files(root)
    waivers, violations = load_waivers(root)
    used = set()
    for path in files:
        for violation in FileChecker(root, path).run():
            waived = False
            for rule, glob, _reason, num in waivers:
                if rule == violation.rule and fnmatch.fnmatch(violation.path, glob):
                    used.add(num)
                    waived = True
            if not waived:
                violations.append(violation)
    if not args.files:
        for rule, glob, _reason, num in waivers:
            if num not in used:
                violations.append(Violation(WAIVER_FILE, num, "LIB-WAIVE", f"unused waiver '{rule} {glob}'"))

    for violation in violations:
        print(violation)
    print(f"hexk_style_check: {len(files)} files, {len(violations)} violations")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
