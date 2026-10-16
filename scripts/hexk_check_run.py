#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
"""Checks how a simulation of a testbench on hexk_base_test ended.

    hexk_check_run.py [--exit-status N] LOG VERDICT [ID:SEVERITY:COUNT ...] [match=REGEX ...]
    hexk_check_run.py --check-list LIST

VERDICT is PASSED, FAILED or NONE (no verdict line, as after a fatal). Every warning, error and
fatal in the summary table that hexk_report_server prints ("Messages by severity and ID") must be
one of the given ID:SEVERITY:COUNT entries with exactly that count (SEVERITY is W, E or F), and
every given entry must be there. Each match=REGEX gives a Python regular expression that some line
of the log must match; write a space as \\s, as the entry may not contain one.
The simulation must have ended normally: the log has the whole summary table (up to the line
"Noisiest IDs:" that follows it) and the record of the simulator of its $finish (Questa
"** Note: $finish", VCS "$finish called from" or "$finish at simulation time"), and not the line
HEXK_EXAMPLE_STILL_RUNNING that the Questa run script writes when the time limit came first. A
warning, error or fatal that UVM reports after the summary table fails the run, as the table did
not count it; and when the log has the banner of hexk_tb_top_inc.svh, it must agree with VERDICT
(SIMULATION PASSED, SIMULATION FAILED, or SIMULATION FAILED - ABORTED for NONE).
--exit-status gives the exit status of the simulator, which must be 0: the simulators exit with 0
after a test that passed, failed or ended in a fatal, so another status is a failed launch, a
crash or the time limit of the run. An error or fatal that the simulator reports itself, outside
UVM (a $error, a failed assertion, a runtime error), fails the run as well: Questa marks them
"** Error" and "** Fatal", VCS "Error" and "Fatal" at the start of a line, and VCS reports a failed
assertion as '"<file>", <line>: <scope>: started at ... failed at ...'.
Prints one line and exits 1 when something differs.

--check-list checks a list of runs before anything runs: every line that is not blank or a comment
(#) is "test | seed | plusargs | verdict | expectations" (the expectations may hold a "|"
themselves, as the shell that runs the list reads them), with a test name, a number as the seed, a
verdict as above and expectations as above whose expressions compile. It names the file and the
line of every mistake, and exits 1 when there is one, or when the list holds no run.
"""
import re
import sys

SEVERITIES = {"UVM_WARNING": "W", "UVM_ERROR": "E", "UVM_FATAL": "F"}

# The records of $finish of the simulators, matched after the "# " that Questa puts before every line.
FINISH_RECORDS = [
    re.compile(r"^\*\* Note: \$finish\b"),
    re.compile(r"^\$finish (called from|at simulation time)\b"),
]

# Reports of UVM, in the compact layout of hexk_report_server (E1, W2, F1 and a time) or in the layout of UVM, with
# or without a file and line ("UVM_ERROR file(12) @ 0: ..." or "UVM_ERROR @ 0: ...").
UVM_REPORTS = [
    re.compile(r"^[EWF]\d+\s+\d"),
    re.compile(r"^UVM_(WARNING|ERROR|FATAL)\s+(\S+\(\d+\)\s+)?@"),
]

# The colours of +hexk_report_color=1 (ANSI escape sequences), removed before a line is read.
COLOURS = re.compile(r"\x1b\[[0-9;]*m")

# The banner that hexk_tb_top_inc.svh prints at the end, by verdict.
BANNERS = {"PASSED": "SIMULATION PASSED", "FAILED": "SIMULATION FAILED (", "NONE": "SIMULATION FAILED - ABORTED"}

# Errors that the simulator reports outside UVM, matched after the "# " that Questa puts before every line.
NATIVE_ERRORS = [
    re.compile(r"^\*\* (Error|Fatal)\b"),
    re.compile(r"^(Error|Fatal)(-\[[A-Za-z0-9_-]+\])?[: ]"),
    re.compile(r'^"[^"]+", \d+: \S+: started at .* failed at '),
]


def parse_expectations(entries, where):
    """The expected counts and the patterns of the entries; exits naming where on a wrong entry."""
    expected = {}
    patterns = []
    for entry in entries:
        if entry.startswith("match=") and len(entry) > len("match="):
            pattern = entry[len("match="):]
            try:
                re.compile(pattern)
            except re.error as error:
                sys.exit(f"{where}: '{entry}' is not a regular expression ({error})")
            patterns.append(pattern)
            continue
        match = re.fullmatch(r"(\S+):([WEF]):(\d+)", entry)
        if not match:
            sys.exit(f"{where}: '{entry}' is not ID:SEVERITY:COUNT with SEVERITY W, E or F, nor match=REGEX")
        expected[(match.group(1), match.group(2))] = int(match.group(3))
    return expected, patterns


def check_list(path):
    """Checks a list of runs; exits 1 naming the file and line of the first mistake, or when it holds no run."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        sys.exit(f"{path}: cannot read the list of runs ({error.strerror})")
    runs = 0
    for number, line in enumerate(lines, 1):
        line = line.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        where = f"{path}:{number}"
        fields = [field.strip() for field in line.split("|", 4)]
        if len(fields) < 4:
            sys.exit(f"{where}: a run is 'test | seed | plusargs | verdict | expectations', not '{line}'")
        test, seed, verdict = fields[0], fields[1], fields[3]
        if not re.fullmatch(r"\w+", test):
            sys.exit(f"{where}: '{test}' is not a test name")
        if not re.fullmatch(r"\d+", seed):
            sys.exit(f"{where}: the seed '{seed}' is not a number")
        if verdict not in ("PASSED", "FAILED", "NONE"):
            sys.exit(f"{where}: the verdict '{verdict}' is not PASSED, FAILED or NONE")
        parse_expectations(fields[4].split() if len(fields) == 5 else [], where)
        runs += 1
    if runs == 0:
        sys.exit(f"{path}: no runs in the list")
    print(f"{path}: {runs} runs")


def parse_arguments(argv):
    """The exit status (None when not given), the log, the verdict, the expected counts and the patterns."""
    exit_status = None
    if len(argv) >= 2 and argv[0] == "--exit-status":
        if not re.fullmatch(r"-?\d+", argv[1]):
            sys.exit(f"--exit-status needs a number, not '{argv[1]}'")
        exit_status = int(argv[1])
        argv = argv[2:]
    if len(argv) < 2 or argv[1] not in ("PASSED", "FAILED", "NONE"):
        sys.exit(__doc__)
    log, verdict = argv[0], argv[1]
    expected, patterns = parse_expectations(argv[2:], log)
    return exit_status, log, verdict, expected, patterns


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check-list":
        check_list(sys.argv[2])
        return
    exit_status, log, verdict, expected, patterns = parse_arguments(sys.argv[1:])
    problems = []
    if exit_status not in (None, 0):
        problems.append(f"the simulator exited with status {exit_status}")
    try:
        with open(log, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        print(f"{log}: no log ({error.strerror}); " + "; ".join(problems or ["the simulation did not run"]))
        sys.exit(1)
    seen = {}
    in_table = False
    table_complete = False
    finished = False
    still_running = False
    verdicts = set()
    native = []
    after_table = []
    banner = None
    for line in lines:
        text = COLOURS.sub("", line)
        text = text[2:] if text.startswith("# ") else text
        if any(pattern.match(text) for pattern in NATIVE_ERRORS):
            native.append(text.strip())
        if any(pattern.match(text) for pattern in FINISH_RECORDS):
            finished = True
        if text.startswith("SIMULATION "):
            banner = text.strip()
        if table_complete and not in_table and any(pattern.match(text) for pattern in UVM_REPORTS):
            after_table.append(re.sub(r"\s+", " ", text.strip()))
        if "HEXK_EXAMPLE_STILL_RUNNING" in text:
            still_running = True
        if "Messages by severity and ID:" in text:
            in_table, table_complete, seen = True, False, {}
            continue
        if in_table:
            match = re.match(r"\s+(UVM_\w+)\s+(\d+)\s+(\S+)\s*$", text)
            if match:
                if match.group(1) in SEVERITIES:
                    seen[(match.group(3), SEVERITIES[match.group(1)])] = int(match.group(2))
                continue
            in_table = False
            table_complete = text.startswith("Noisiest IDs:")
        match = re.search(r"\bTEST (PASSED|FAILED) \(", text)
        if match:
            verdicts.add(match.group(1))
    if not table_complete:
        problems.append("no complete summary table: the simulation did not end normally")
    if not finished:
        problems.append("no $finish: the simulation did not end normally")
    if still_running:
        problems.append("the time limit of the run came first")
    if after_table:
        problems.append(f"{len(after_table)} reports after the summary table, which did not count them, the first: "
                        f"{after_table[0][:120]}")
    if banner is not None and not banner.startswith(BANNERS[verdict]):
        problems.append(f"the banner says '{banner[:60]}', not {BANNERS[verdict]}")
    actual_verdict = "NONE" if not verdicts else "/".join(sorted(verdicts))
    if actual_verdict != verdict:
        problems.append(f"verdict {actual_verdict}, expected {verdict}")
    for key in sorted(set(seen) | set(expected)):
        if seen.get(key, 0) != expected.get(key, 0):
            problems.append(f"{key[0]}:{key[1]} seen {seen.get(key, 0)}, expected {expected.get(key, 0)}")
    if native:
        problems.append(f"{len(native)} errors of the simulator outside UVM, the first: {native[0]}")
    for pattern in patterns:
        if not any(re.search(pattern, line) for line in lines):
            problems.append(f"no line matches {pattern}")
    if problems:
        print(f"{log}: " + "; ".join(problems))
        sys.exit(1)
    print(f"{log}: ended as expected ({verdict})")


if __name__ == "__main__":
    main()
