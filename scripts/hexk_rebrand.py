#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Rebrandable-prefix tooling.

    hexk_rebrand.py --check
    hexk_rebrand.py --prefix acme [--version-suffix 2] [--out DIR] [--force]

--check tests these rules on every text file of the repository and on every file and
directory name:

  RB-1  the prefix is written only as 'hexk_', 'HEXK_' or 'hexk-'; brand mentions are
        'HEXK' followed by a space or punctuation, a URL, or an entry of the keep-list
  RB-2  no prefixed name is built at run time: in SystemVerilog a string literal never has
        the prefix directly before its closing quote or before a format specifier
  RB-3  the prefix never appears inside another identifier
  RB-4  no prefix macros: no token pasting onto the prefix, no macro named after it

--prefix writes a copy of the repository in which the prefix is another one: identifiers,
defines, plusargs, message IDs, file and directory names, filelists, core files and
documents. Because of the rules above this is a substitution of the three written forms of
the prefix. --version-suffix adds a suffix to the prefix, for two versions of the library in
one simulation; without --prefix it gives 'hexk2_' and the like. The copy keeps LICENSE and
NOTICE, the copyright lines, links, the GitHub organisation and the FuseSoC names. NOTICE
and every file with a copyright line get a line that says what was changed (Apache-2.0,
section 4(b)). After writing, the copy is searched for the old prefix; a survivor outside
the keep-list is an error. The output is a function of the input, so a new release is
rebranded by running the script again.

This file is not checked: it states the rules and therefore quotes the forbidden forms.
LICENSE is third-party text. A file LOCAL_SKIP_FILE in the root, when it exists, names more
paths, one per line ('#' starts a comment): a file is copied but not checked, and a directory
(written with a trailing '/') is neither checked nor copied.
"""

import argparse
import re
import shutil
import sys
from pathlib import Path

LOWER = "hexk_"
UPPER = "HEXK_"
DASHED = LOWER[:-1] + "-"
STEM_RE = re.compile(LOWER[:-1], re.IGNORECASE)
SKIP_DIRS = {".git", "build", "obj_dir", "__pycache__", ".venv", "node_modules"}
SKIP_FILES = {
    "LICENSE",
    "scripts/" + LOWER + "rebrand.py",
}
# Directories of the root that are neither checked nor copied; filled from LOCAL_SKIP_FILE.
SKIP_ROOT_DIRS = set()
# Optional list of further paths to skip, for files that are not part of the published tree.
LOCAL_SKIP_FILE = ".rebrand_skip"
# Copied as they are (rule 5); NOTICE gets one more line.
VERBATIM_FILES = {"LICENSE", "NOTICE"}
SV_SUFFIXES = (".sv", ".svh")
IDENT_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
# Names of this repository as the notes of a copy quote them; not to be turned into names of the copy.
ORIGIN = DASHED + "sv-lib"
ORIGIN_MARK = "Modified from " + ORIGIN
# The note of a rebranding, of this run or of an earlier one: it names prefixes and is left as it is.
NOTE_RE = re.compile(r"Modified from \S+ v\S+: the prefix \S+ was changed to \S+")
# Written into the output directory; --force deletes only a directory that holds it.
MARKER_FILE = ".rebrand_output"
# Prefixes that would collide with names of other libraries or of the language.
DENIED_PREFIXES = {"uvm", "ovm", "vmm", "svunit", "svt", "std", "sv"}
NEW_PREFIX_RE = re.compile(r"^[a-z][a-z0-9]*$")
SUFFIX_RE = re.compile(r"^[a-z0-9]+$")
COPYRIGHT_RE = re.compile(r"^(\s*(?://|#))\s*Copyright \(c\) \d{4} ")

# Brand mentions that a rebrand must leave alone (rule 5): spans matching these are skipped.
KEEP_RES = (
    re.compile(r"https?://[^\s)>\]\"'`]+"),                       # links
    re.compile(r"(?<![A-Za-z0-9_])hexkDotCom(?![A-Za-z0-9_])"),   # GitHub organisation
    re.compile(r"(?<![A-Za-z0-9_])hexkdotcom:hexk:[a-z0-9_]+"),   # FuseSoC VLNV
)
FORMS_RE = re.compile("(?<![A-Za-z0-9_])(?:" + LOWER + "|" + UPPER + "|" + DASHED + ")")
STRING_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
PASTE_RE = re.compile("(?:" + LOWER + "|" + UPPER + ")``|``(?:" + LOWER + "|" + UPPER + ")")
PREFIX_MACRO_RE = re.compile(r"`define\s+" + UPPER + r"(?:PFX|PREFIX)\b")


def kept_spans(line):
    """Character ranges of the line that hold keep-list brand mentions."""
    return [match.span() for regex in KEEP_RES for match in regex.finditer(line)]


def check_forms(line):
    """Rules 1 and 3 on one line of text or one path component; return a list of (rule, text)."""
    found = []
    kept = kept_spans(line)
    for match in STEM_RE.finditer(line):
        start, end = match.span()
        if any(lo <= start and end <= hi for lo, hi in kept):
            continue
        word = match.group(0)
        before = line[start - 1] if start > 0 else ""
        after = line[end] if end < len(line) else ""
        shown = line[max(start - 8, 0):end + 8].strip()
        if before and before in IDENT_CHARS:
            found.append(("RB-3", f"prefix inside another identifier: '{shown}'"))
        elif word == LOWER[:-1]:
            if after not in ("_", "-"):
                found.append(("RB-1", f"bare lower-case prefix without '_' or '-': '{shown}'"))
        elif word == UPPER[:-1]:
            if after and after in IDENT_CHARS and after != "_":
                found.append(("RB-3", f"prefix runs into another identifier: '{shown}'"))
        else:
            found.append(("RB-1", f"mixed-case prefix: '{shown}'"))
    return found


def check_sv_line(line):
    """Rules 2 and 4 on one line of SystemVerilog; return a list of (rule, text)."""
    found = []
    for literal in STRING_RE.finditer(line):
        body = literal.group(1)
        for prefix in (LOWER, UPPER):
            position = body.find(prefix)
            while position >= 0:
                rest = body[position + len(prefix):]
                if rest == "" or rest.startswith("%"):
                    found.append(("RB-2", f"prefixed name built at run time: \"{body}\""))
                position = body.find(prefix, position + 1)
    if PASTE_RE.search(line):
        found.append(("RB-4", "token pasting onto the prefix"))
    if PREFIX_MACRO_RE.search(line):
        found.append(("RB-4", "prefix macro"))
    return found


def repo_files(root, with_skipped=False):
    """Every checked file of the repository, sorted for stable output."""
    files = []
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if any(relative.as_posix() == d or relative.as_posix().startswith(d + "/") for d in SKIP_ROOT_DIRS):
            continue
        if relative.as_posix() == MARKER_FILE:
            continue  # the tree is itself a copy: its marker is not part of it
        if path.is_file() and (with_skipped or relative.as_posix() not in SKIP_FILES):
            files.append(path)
    return sorted(files)


def run_check(root):
    """Check the whole repository; return the number of violations."""
    count = 0
    files = repo_files(root)
    names = set()
    for path in files:
        relative = path.relative_to(root)
        names.update(relative.parts)
        try:
            text = path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            continue  # binary file: nothing to rebrand inside it
        is_sv = path.suffix in SV_SUFFIXES
        for num, line in enumerate(text.splitlines(), 1):
            found = check_forms(line)
            if is_sv:
                found.extend(check_sv_line(line))
            for rule, message in found:
                print(f"{relative.as_posix()}:{num}: [{rule}] {message}")
                count += 1
    for name in sorted(names):
        for rule, message in check_forms(name):
            print(f"{name}: [{rule}] in a file or directory name: {message}")
            count += 1
    print(f"{LOWER}rebrand --check: {len(files)} files, {count} violations")
    return count


class Rebrand:
    """One rebranding: the new forms of the prefix and the substitution."""

    def __init__(self, stem, version):
        self.stem = stem
        self.forms = {LOWER: stem + "_", UPPER: stem.upper() + "_", DASHED: stem + "-"}
        self.note = f"{ORIGIN_MARK} v{version}: the prefix {LOWER} was changed to {stem}_."

    def text(self, line):
        """One line, or one path component, with every form of the prefix replaced outside the keep-list."""
        kept = kept_spans(line) + [match.span() for match in NOTE_RE.finditer(line)]

        def replace(match):
            start, end = match.span()
            if any(lo <= start and end <= hi for lo, hi in kept):
                return match.group(0)
            return self.forms[match.group(0)]

        return FORMS_RE.sub(replace, line)

    def path(self, relative):
        """The path of a file in the copy."""
        return Path(*[self.text(part) for part in relative.parts])

    def file_text(self, text):
        """The text of a file in the copy: the prefix replaced, and a note after the copyright line."""
        lines = [self.text(line) for line in text.splitlines(keepends=True)]
        for index, line in enumerate(lines[:8]):
            match = COPYRIGHT_RE.match(line)
            if match:
                ending = line[len(line.rstrip("\r\n")):]
                lines.insert(index + 1, f"{match.group(1)} {self.note}{ending}")
                break
        return "".join(lines)

    def survivors(self, line):
        """The places of a line of the copy where the old prefix is left outside the keep-list."""
        found = []
        kept = kept_spans(line) + [match.span() for match in NOTE_RE.finditer(line)]
        for match in STEM_RE.finditer(line):
            start, end = match.span()
            if any(lo <= start and end <= hi for lo, hi in kept):
                continue
            after = line[end] if end < len(line) else ""
            if match.group(0) == UPPER[:-1] and (after == "" or after not in IDENT_CHARS + "-"):
                continue  # the brand: 'HEXK' followed by a space or punctuation (rule 5)
            if line[start:].lower().startswith(self.stem) and self.stem != LOWER[:-1]:
                continue  # the new prefix begins with the old one, as with --version-suffix
            found.append(line[max(start - 12, 0):end + 12].strip())
        return found


def prepare_output(out, root, force):
    """Create the output directory, empty; return an error text or ''."""
    if out == root or root in out.parents and not any(part in SKIP_DIRS for part in out.relative_to(root).parts):
        return f"the output directory {out} is inside the tree that is copied; choose one outside, or under build/"
    if out.exists():
        if not out.is_dir():
            return f"{out} exists and is not a directory"
        if any(out.iterdir()):
            if not force:
                return f"{out} is not empty; give --force to replace a copy made by this script"
            if not (out / MARKER_FILE).is_file():
                return f"{out} is not empty and was not written by this script (no {MARKER_FILE}); not touched"
            # The directory itself stays: a shell or an editor may have it open.
            for child in out.iterdir():
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
    out.mkdir(parents=True, exist_ok=True)
    return ""


def run_rebrand(root, stem, out, force):
    """Write the rebranded copy and search it for the old prefix; return the number of problems."""
    version = (root / "VERSION").read_text(encoding="utf-8").strip() if (root / "VERSION").is_file() else "unknown"
    rebrand = Rebrand(stem, version)
    problem = prepare_output(out, root, force)
    if problem:
        print(f"{LOWER}rebrand: {problem}")
        return 1
    (out / MARKER_FILE).write_text(rebrand.note + "\n", encoding="utf-8")
    count = 0
    files = repo_files(root, with_skipped=True)
    skipped_in_copy = {rebrand.path(Path(name)).as_posix() for name in SKIP_FILES}
    for path in files:
        relative = path.relative_to(root)
        target = out / rebrand.path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        data = path.read_bytes()
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            text = None  # binary file: copied as it is
        if text is None:
            target.write_bytes(data)
        elif relative.as_posix() in VERBATIM_FILES:
            if relative.as_posix() == "NOTICE":
                text = text.rstrip("\n") + f"\n\n{rebrand.note}\n"
            target.write_bytes(text.encode("utf-8"))
        else:
            target.write_bytes(rebrand.file_text(text).encode("utf-8"))
        shutil.copymode(path, target)
        # Search what was written. The files that state the rules quote forms that no rule allows.
        written = target.relative_to(out).as_posix()
        if text is None or relative.as_posix() in VERBATIM_FILES or written in skipped_in_copy:
            continue
        for part in target.relative_to(out).parts:
            for shown in rebrand.survivors(part):
                print(f"{written}: old prefix in a file or directory name: '{shown}'")
                count += 1
        for num, line in enumerate(target.read_bytes().decode("utf-8").splitlines(), 1):
            for shown in rebrand.survivors(line):
                print(f"{written}:{num}: old prefix left: '{shown}'")
                count += 1
    print(f"{LOWER}rebrand: {len(files)} files written to {out} with the prefix {stem}_, {count} places with the old prefix")
    return count


def new_stem(prefix, suffix):
    """The new prefix without its underscore, or an error text starting with '!'."""
    stem = prefix[:-1] if prefix.endswith("_") else prefix
    if not NEW_PREFIX_RE.match(stem):
        return f"!the prefix '{prefix}' must be lower-case letters and digits and begin with a letter"
    if suffix and not SUFFIX_RE.match(suffix):
        return f"!the version suffix '{suffix}' must be lower-case letters and digits"
    stem += suffix
    if stem == LOWER[:-1]:
        return "!the new prefix is the old one; give --prefix or --version-suffix"
    if stem in DENIED_PREFIXES:
        return f"!the prefix '{stem}_' is that of another library or of the language"
    return stem


def read_local_skips(root):
    """Add the paths of LOCAL_SKIP_FILE, if the root has one, to the skip lists."""
    path = root / LOCAL_SKIP_FILE
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        entry = line.split("#", 1)[0].strip()
        if entry.endswith("/"):
            SKIP_ROOT_DIRS.add(entry.rstrip("/"))
        elif entry:
            SKIP_FILES.add(entry)


def main():
    parser = argparse.ArgumentParser(description="Rebrandable prefix: check the rules, or write a rebranded copy.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: parent of scripts/)")
    parser.add_argument("--check", action="store_true", help="check rules 1-4 and exit")
    parser.add_argument("--prefix", help="new prefix, without the underscore: 'acme' gives acme_, ACME_ and acme-")
    parser.add_argument("--version-suffix", default="", help="suffix of the prefix, for two versions side by side")
    parser.add_argument("--out", type=Path, help="directory of the copy (default: build/rebrand/<prefix> in the root)")
    parser.add_argument("--force", action="store_true", help="replace a copy that this script wrote before")
    args = parser.parse_args()
    root = args.root.resolve()
    read_local_skips(root)
    if args.check:
        return 1 if run_check(root) else 0
    if args.prefix is None and not args.version_suffix:
        parser.error("give --check, or --prefix and/or --version-suffix")
    stem = new_stem(args.prefix if args.prefix is not None else LOWER[:-1], args.version_suffix)
    if stem.startswith("!"):
        parser.error(stem[1:])
    out = (args.out if args.out is not None else root / "build" / "rebrand" / stem).resolve()
    return 1 if run_rebrand(root, stem, out, args.force) else 0


if __name__ == "__main__":
    sys.exit(main())
