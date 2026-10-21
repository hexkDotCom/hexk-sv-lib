#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Checks the messages of a run of an example against the list of what each example reports on purpose.

    hexk_check_example.py LIST SIM EXAMPLE LOG
    hexk_check_example.py --check-list LIST

LIST holds one line per message that an example reports on purpose:
"example simulators severity id count", separated by spaces. simulators is "all" or a
comma-separated list of questa and vcs; severity is UVM_WARNING, UVM_ERROR, UVM_FATAL, or NATIVE
for an error that the simulator reports outside UVM (a $error, a failed assertion, a runtime
error), whose id is then a text that its line contains. Blank lines and lines that start with #
are comments.

The run of EXAMPLE on SIM must report exactly the warnings, errors and fatals that the list gives
for that example and simulator, with those counts, and no other: an example that the list does
not name must report none. The counts come from the table "Messages by severity and ID" of
hexk_report_server when the log has one, else from the report lines of UVM
("UVM_ERROR file(12) @ 0: reporter [ID] text"). Errors of the simulator are the lines that start
with "** Error" or "** Fatal" (Questa) or "Error" or "Fatal" (VCS), and the failed assertions of
VCS. Prints one line and exits 1 when something differs.

--check-list checks the list alone: five columns, a known simulator and severity, a count above
0, and no line twice. It names the file and line of every mistake.
"""
import re
import sys

SIMULATORS = ("questa", "vcs")
SEVERITIES = ("UVM_WARNING", "UVM_ERROR", "UVM_FATAL", "NATIVE")

# A report of UVM in its own layout, with or without a file and line, and with the ID in brackets.
UVM_REPORT = re.compile(r"^(UVM_WARNING|UVM_ERROR|UVM_FATAL)\s+(?:\S+\(\d+\)\s+)?@\s*[^:]*:\s*\S+\s+\[([^\]]+)\]")

# A row of the table of hexk_report_server.
TABLE_ROW = re.compile(r"^\s+(UVM_\w+)\s+(\d+)\s+(\S+)\s*$")

# Errors that the simulator reports outside UVM, as in hexk_check_run.py.
NATIVE_ERRORS = [
    re.compile(r"^\*\* (Error|Fatal)\b"),
    re.compile(r"^(Error|Fatal)(-\[[A-Za-z0-9_-]+\])?[: ]"),
    re.compile(r'^"[^"]+", \d+: \S+: started at .* failed at '),
]

# The colours of +hexk_report_color=1, removed before a line is read.
COLOURS = re.compile(r"\x1b\[[0-9;]*m")


def read_list(path):
    """The entries of the list as (example, simulators, severity, id, count, line number); exits on a mistake."""
    entries = []
    mistakes = []
    seen = set()
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        sys.exit(f"{path}: cannot read the list ({error.strerror})")
    for number, line in enumerate(lines, 1):
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        where = f"{path}:{number}"
        columns = text.split()
        if len(columns) != 5:
            mistakes.append(f"{where}: {len(columns)} columns, not 5 (example simulators severity id count)")
            continue
        example, simulators, severity, ident, count = columns
        sims = SIMULATORS if simulators == "all" else tuple(simulators.split(","))
        if any(sim not in SIMULATORS for sim in sims):
            mistakes.append(f"{where}: simulators '{simulators}' is not all or a list of {', '.join(SIMULATORS)}")
        if severity not in SEVERITIES:
            mistakes.append(f"{where}: severity '{severity}' is not one of {', '.join(SEVERITIES)}")
        if not re.fullmatch(r"[1-9]\d*", count):
            mistakes.append(f"{where}: count '{count}' is not a number above 0")
            continue
        for sim in sims:
            key = (example, sim, severity, ident)
            if key in seen:
                mistakes.append(f"{where}: {example} {severity} {ident} on {sim} is listed twice")
            seen.add(key)
        entries.append((example, sims, severity, ident, int(count), number))
    if mistakes:
        sys.exit("\n".join(mistakes))
    return entries


def counts_of_log(path):
    """The warnings, errors and fatals of the log by (severity, id), and the lines of the errors of the simulator."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        print(f"{path}: no log ({error.strerror})")
        sys.exit(1)
    from_lines = {}
    from_table = None
    in_table = False
    native = []
    for line in lines:
        text = COLOURS.sub("", line)
        text = text[2:] if text.startswith("# ") else text
        if any(pattern.match(text) for pattern in NATIVE_ERRORS):
            native.append(text.strip())
        if "Messages by severity and ID:" in text:
            in_table, from_table = True, {}
            continue
        if in_table:
            match = TABLE_ROW.match(text)
            if match:
                if match.group(1) in ("UVM_WARNING", "UVM_ERROR", "UVM_FATAL"):
                    key = (match.group(1), match.group(3))
                    from_table[key] = from_table.get(key, 0) + int(match.group(2))
                continue
            in_table = False
        match = UVM_REPORT.match(text)
        if match:
            key = (match.group(1), match.group(2))
            from_lines[key] = from_lines.get(key, 0) + 1
    return (from_table if from_table is not None else from_lines), native


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check-list":
        entries = read_list(sys.argv[2])
        print(f"{sys.argv[2]}: {len(entries)} entries")
        return
    if len(sys.argv) != 5 or sys.argv[2] not in SIMULATORS:
        sys.exit(__doc__)
    list_path, sim, example, log = sys.argv[1:]
    expected = {}
    native_expected = {}
    for name, sims, severity, ident, count, _ in read_list(list_path):
        if name != example or sim not in sims:
            continue
        if severity == "NATIVE":
            native_expected[ident] = count
        else:
            expected[(severity, ident)] = count
    seen, native = counts_of_log(log)
    problems = []
    for key in sorted(set(seen) | set(expected)):
        if seen.get(key, 0) != expected.get(key, 0):
            problems.append(f"{key[0]} {key[1]} seen {seen.get(key, 0)}, expected {expected.get(key, 0)}")
    native_seen = {ident: 0 for ident in native_expected}
    for line in native:
        ident = next((ident for ident in native_expected if ident in line), None)
        if ident is None:
            problems.append(f"an error of the simulator that the list does not give: {line[:120]}")
        else:
            native_seen[ident] += 1
    for ident, count in native_expected.items():
        if native_seen[ident] != count:
            problems.append(f"NATIVE {ident} seen {native_seen[ident]}, expected {count}")
    if problems:
        print(f"{log}: " + "; ".join(problems))
        sys.exit(1)
    print(f"{log}: the messages are as expected")


if __name__ == "__main__":
    main()
