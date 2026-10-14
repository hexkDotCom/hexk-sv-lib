#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Run slang through the pyslang package with the command line of the slang binary.

The pyslang wheel ships the slang library but no 'slang' executable. This wrapper gives
Gate 1 the same command line on every machine: 'pip install pyslang' is the only setup.

    hexk_slang.py [slang options and files ...]

Exit status is 0 when slang reports no errors (warnings count as errors when the options
say so, for example with -Werror), 1 otherwise, and 2 for a bad command line.
"""

import sys

try:
    from pyslang.driver import Driver
except ImportError:
    sys.exit("hexk_slang: the pyslang package is missing; install it with 'pip install pyslang'")


def main():
    driver = Driver()
    driver.addStandardArgs()
    # parseCommandLine takes one string and splits it like a shell, so quote each argument.
    line = " ".join('"' + arg.replace("\\", "\\\\").replace('"', '\\"') + '"' for arg in sys.argv)
    if not driver.parseCommandLine(line):
        return 2
    if not driver.processOptions():
        return 2
    if not driver.parseAllSources():
        return 1
    return 0 if driver.runFullCompilation(False) else 1


if __name__ == "__main__":
    sys.exit(main())
