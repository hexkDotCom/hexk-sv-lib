# tests/unit

SVUnit unit tests, one directory per module, one file `<module>_unit_test.sv` per module.
Each test is named after the behaviour it proves. Checks that must fire are tested with
`hexk_report_catcher`.

`make test SIM=verilator [TEST=<module>]` runs the tests on Verilator; it is part of
`make pre_sim`. There are two simulations: tests that do not mention UVM run against the
core filelist alone; the others are compiled with UVM 2020 (`UVM_SIM_HOME`), with only the
regex part of the UVM DPI library (`hexk_uvm_regex_dpi.cc`). Verilator cannot compile UVM
1.2. The full logs are `$SVUNIT_OUT/core/test.log` and `$SVUNIT_OUT/uvm/test.log`.

A group of tests passes on every simulator when SVUnit reports PASSED **and** the UVM errors
and fatals in its log are exactly those that `expected_uvm_errors.txt` lists for the suites
that ran. SVUnit alone would pass a test whose code reports an error that the test does not
check. A negative test demotes the errors it provokes with `hexk_report_catcher` and checks
their count; since the catcher hides them from this check, a test of a legal case checks
that the count is 0. Only the suites that test reporting itself let errors through, and the
list says which and how many. The check reads lines in the layout of UVM: a message printed
while a test has switched the report server to another layout is not seen by it.

The core has no UVM and reports an illegal argument with `$error`, so the same group also
fails unless the core messages in its log, per suite and with their full text and count, are
exactly those that `expected_core_errors.txt` lists: a negative test that gets its fallback
value without its message fails, and so does a legal call that reports one.
`scripts/hexk_core_errors.awk` finds them in the log of each simulator. A new negative test
of the core adds its message there.

`make test SIM=questa UVM=1.2|2020 [TEST=<module>]` runs the same two groups on Questa
(Gate 2); the logs are `$SVUNIT_OUT/questa_core/test.log` and
`$SVUNIT_OUT/questa_uvm_<UVM>/test.log`. SVUnit only generates the test runner there
(`buildSVUnit`); `vlog` and `vsim` are called by the Makefile. UVM is compiled from the
Accellera sources (`UVM_HOME`) together with its DPI code, so a C compiler must be on the
`PATH`. On Windows this runs from Git Bash with a native GNU make and MinGW-w64 GCC. Two
things are specific to Windows: the paths that SVUnit writes (`/d/...`) are rewritten to
`d:/...`, and `mingw_compat/regex.h` stands in for the POSIX `regex.h` that MinGW-w64 does
not have, so regular expressions run on `std::regex` there. On Linux neither applies; that
branch of the Makefile has not been run.

`make examples SIM=questa UVM=1.2|2020` compiles and runs every example of `examples/` on
Questa. The unit tests give the library plain variables; the examples use it the way a
testbench does, with members of objects, virtual interfaces and real UVM phases, and that
is how the first compile error that only Questa reports was found. An example passes when
it compiles and its simulation ends: several provoke errors or a fatal on purpose, so
their messages are not counted. Plusargs of an example are in `<example>.plusargs` next to
it.

Two tool limits shape every test body (between `` `SVTEST `` and `` `SVTEST_END ``):

- Only macro calls and call statements, no assignments or loops; put those in helper
  functions of the test module. Verible cannot see the task that the SVUnit macros open, so
  anything else is a syntax error for it. For the same reason the formatter is switched off
  around the test block.
- Compare results as text with `` `FAIL_UNLESS_STR_EQUAL ``. The other SVUnit checks turn
  their argument into a string, which Verilator rejects when the argument holds a string
  literal.

All UVM-layer suites run in one simulation, so a suite must not leave global UVM state
behind: use the report server that is installed (`hexk_report_server::get_installed()`)
instead of installing another one, put a replaced report server back, and clear the rules
of a report catcher in `teardown()`. Simulation time is shared as well: a suite starts at the
time the suite before it ended, so a test must not expect the time to be 0.

A test that needs plusargs lists them in `<module>_unit_test.plusargs` next to the test, one
per line; `make test` puts them on the simulation command line.

Verilator has two-state variables, so the few tests that need an X bit are inside
`` `ifndef VERILATOR ``: compiled by the other tools, run on four-state simulators only. The
same holds for the one test that overrides a `soft` constraint, which Verilator 5.046
treats as a hard one.
Constrained randomization on Verilator needs the z3 solver on the `PATH`; a randomization
that a test makes fail on purpose prints `%Warning-UNSATCONSTR` lines in the log, and the
lines Verilator names there are not always the ones that conflict.

Library code reports illegal arguments with `$error`. The tests call such code on purpose
and check the returned value; `make test` raises Verilator's error limit so that the run
continues.
