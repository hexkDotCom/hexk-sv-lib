#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Propagate the VERSION file into the files that repeat the version.

Writes src/core/hexk_version.svh and sets the version field of the 'name:' line of every
FuseSoC .core file, so that VERSION is the only place a version is typed by hand.

    hexk_gen_version.py           rewrite the derived files
    hexk_gen_version.py --check   exit 1 if a derived file disagrees with VERSION
    hexk_gen_version.py --print   print the version and exit
"""

import argparse
import re
import sys
from pathlib import Path

LOWER = "hexk_"
VERSION_HEADER = "src/core/hexk_version.svh"
# Files that are infrastructure, not modules: no feature-test define.
NO_FEATURE_DEFINE = {
    "hexk_core_pkg", "hexk_version", "hexk_sim_compat",
    "hexk_uvm_pkg", "hexk_macros", "hexk_uvm_compat",
}
MODULE_TAG_RE = re.compile(r"^//!\s*@module\s+(\w+)\s*$", re.MULTILINE)
CORE_FILES = (
    "hexk_sv_lib.core", "src/core/hexk_core.core", "src/uvm/hexk_uvm.core",
    "src/agents/hexk_clk_rst/hexk_clk_rst.core",
    "src/agents/hexk_valid_ready/hexk_valid_ready.core",
    "src/agents/hexk_pins/hexk_pins.core",
)
SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
CORE_NAME_RE = re.compile(r'^(name:\s*"[^":]+:[^":]+:[^":]+:)[^"]*(")\s*$', re.MULTILINE)

HEADER_TEMPLATE = """\
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_version.svh
//
// Version of hexk-sv-lib as preprocessor defines.
// GENERATED from the VERSION file by `make version`; do not edit by hand (FIL-10).
// Include it where code has to adapt to the library version at compile time. The file
// only defines macros, so it can be included at any scope and any number of times.
// The HEXK_HAS_<MODULE> defines say which modules this release contains; test them with
// `ifdef in code that must also compile against an older release.
//
//! @module    hexk_version
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_VERSION_SVH
`define HEXK_VERSION_SVH

// Major version number (SemVer): incompatible API changes.
`define HEXK_VERSION_MAJOR {major}

// Minor version number (SemVer): added functionality; may break APIs before 1.0.0.
`define HEXK_VERSION_MINOR {minor}

// Patch version number (SemVer): fixes only.
`define HEXK_VERSION_PATCH {patch}

// Full version as a string literal, for banners and log files.
`define HEXK_VERSION_STR "{major}.{minor}.{patch}"
{features}
`endif  // HEXK_VERSION_SVH
"""


def read_version(root):
    """Return (major, minor, patch) from VERSION or exit with a message."""
    text = (root / "VERSION").read_text(encoding="utf-8").strip()
    match = SEMVER_RE.match(text)
    if not match:
        sys.exit(f"hexk_gen_version: VERSION holds '{text}', expected <major>.<minor>.<patch>")
    return match.groups()


def feature_defines(root):
    """Text of the feature-test defines, one per module found under src/."""
    modules = set()
    for path in (root / "src").rglob("*"):
        if path.is_file() and path.suffix in (".sv", ".svh"):
            modules.update(MODULE_TAG_RE.findall(path.read_text(encoding="utf-8")))
    text = ""
    for name in sorted(modules - NO_FEATURE_DEFINE):
        define = (LOWER + "has_" + name[len(LOWER):]).upper()
        text += f"\n// Defined when {name} is part of this release.\n`define {define}\n"
    return text


def derived_files(root, version):
    """Return {path: wanted content} for every file derived from VERSION."""
    major, minor, patch = version
    header = HEADER_TEMPLATE.format(major=major, minor=minor, patch=patch, features=feature_defines(root))
    wanted = {root / VERSION_HEADER: header}
    for name in CORE_FILES:
        path = root / name
        if not path.is_file():
            sys.exit(f"hexk_gen_version: {name} is missing")
        text = path.read_text(encoding="utf-8")
        new_text, count = CORE_NAME_RE.subn(rf"\g<1>{major}.{minor}.{patch}\g<2>", text)
        if count != 1:
            sys.exit(f"hexk_gen_version: {name} needs exactly one 'name: \"<v>:<l>:<n>:<version>\"' line")
        wanted[path] = new_text
    return wanted


def main():
    parser = argparse.ArgumentParser(description="Generate the files derived from VERSION.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="repository root (default: parent of scripts/)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true", help="verify only, write nothing")
    group.add_argument("--print", action="store_true", dest="show", help="print the version")
    args = parser.parse_args()
    root = args.root.resolve()

    version = read_version(root)
    if args.show:
        print(".".join(version))
        return 0

    stale = []
    for path, content in derived_files(root, version).items():
        current = path.read_bytes().decode("utf-8") if path.is_file() else None
        if current == content:
            continue
        stale.append(path.relative_to(root).as_posix())
        if not args.check:
            path.write_bytes(content.encode("utf-8"))

    label = ".".join(version)
    if args.check and stale:
        print(f"hexk_gen_version: out of date for VERSION {label}: {', '.join(stale)} (run 'make version')")
        return 1
    print(f"hexk_gen_version: version {label}, " + (f"updated {', '.join(stale)}" if stale else "all files up to date"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
