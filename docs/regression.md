# Checking how a run ended: `hexk_check_run.py`

A regression needs to know more than "the log has no UVM_ERROR": a negative test must fail in a
given way, a test that hangs must end on the watchdog, and a crash, a time limit or an error of
the simulator outside UVM must never pass. `scripts/hexk_check_run.py` checks one log of a
testbench on `hexk_base_test` (with `hexk_report_server` installed) against what the run must
end with, and checks a list of such runs before a regression starts. It needs Python 3.8 or
newer and nothing else.

## One run

```bash
python3 scripts/hexk_check_run.py [--exit-status N] LOG VERDICT [ID:SEVERITY:COUNT ...] [match=REGEX ...]
```

- `VERDICT` is `PASSED` or `FAILED` (the `TEST PASSED`/`TEST FAILED` line of `hexk_base_test`),
  or `NONE` when a fatal ends the run before that line.
- `ID:SEVERITY:COUNT` (`SEVERITY` is `W`, `E` or `F`): the run must report exactly that many
  warnings, errors or fatals with that ID. Every warning, error and fatal in the summary table of
  `hexk_report_server` must be one of the entries, and every entry must be there.
- `match=REGEX`: some line of the log must match the Python regular expression. Write a space as
  `\s`; an entry holds no space.
- `--exit-status N`: the exit status of the simulator, which must be 0. Questa and VCS exit with
  0 after a test that passed, failed or ended in a fatal, so another status is a failed start, a
  crash or a time limit (`timeout` exits with 124).

The run must also have ended normally:

- the log has the whole summary table of `hexk_report_server`, up to the line `Noisiest IDs:`
  that follows it, and the record of the simulator of its `$finish` (Questa `** Note: $finish`,
  VCS `$finish called from` or `$finish at simulation time`);
- no warning, error or fatal of UVM comes after the summary table, which did not count it, in
  the compact layout of `hexk_report_server` (also in colour, `+hexk_report_color=1`) or in the
  layout of UVM, with or without a file and line;
- an error the simulator reports outside UVM fails the run: Questa `** Error` and `** Fatal`, VCS
  `Error` and `Fatal` at the start of a line and a failed assertion
  (`"<file>", <line>: <scope>: started at ... failed at ...`);
- the line `HEXK_EXAMPLE_STILL_RUNNING` (written by `scripts/hexk_example_run.do` when the
  time limit of a Questa run came first) fails the run;
- when the log has the banner of `hexk_tb_top_inc.svh`, it must agree with `VERDICT`
  (`SIMULATION PASSED`, `SIMULATION FAILED`, or `SIMULATION FAILED - ABORTED` for `NONE`).

It prints one line, `<log>: ended as expected (<verdict>)` or the log followed by every
difference, and exits with 0 or 1.

## A list of runs

```bash
python3 scripts/hexk_check_run.py --check-list LIST
```

checks a list before anything is compiled or run. A line that is not blank and not a comment
(`#`) is one run:

```text
test | seed | plusargs | verdict | expectations
```

with a test name, a number as the seed, the plusargs of the run, a verdict as above and the
expectations as above, separated by spaces (they may hold a `|` themselves). `--check-list`
names the file and line of every mistake (a missing column, a seed that is not a number, a wrong
verdict, an expectation that is neither `ID:SEVERITY:COUNT` nor `match=` with a regular expression
that compiles) and fails on a list without a run. Lines written on Windows, with a carriage
return, are read as well.

Example, from the reference testbench:

```text
hexk_ref_pass_test   | 1  | +ref_mode=mixed | PASSED |
hexk_ref_hang_test   | 11 |                 | FAILED | REF_DONE:E:1 HEXK_SB_TIMEOUT:E:1 REF_MATCHED:E:1
hexk_ref_stall_test  | 12 |                 | NONE   | HEXK_WATCHDOG:F:1 match=no\sheartbeat\sfor
```

## Running a list

The checker does not start simulations; a project runs each line with its own flow and gives
the log, the exit status and the columns to the checker. `make reference` of this repository
does that for the reference testbench (`Makefile`, `run_reference_list`): it checks the list
first, reads it with `awk` and `read` (so the expectations keep a `|`), deletes an old log
before each run, runs the simulator with a wall-clock `timeout`, and passes the exit status:

```bash
python3 scripts/hexk_check_run.py --check-list my_list.txt
# for each line: test, seed, plusargs, verdict, expectations
run_status=0
timeout 600 ./simv -l run.log +ntb_random_seed=$seed +UVM_TESTNAME=$test $args || run_status=$?
python3 scripts/hexk_check_run.py --exit-status $run_status run.log $verdict $expectations
```

On Questa, a run that is still going at the time limit of the run script writes
`HEXK_EXAMPLE_STILL_RUNNING`, which the checker rejects.
