# hexk_report_catcher

## 1. Summary

Report catcher for negative tests: declare which errors, warnings or fatals a test expects,
have them demoted to info, and check at the end that they really occurred.

## 2. When to use / when not to use

Use it in tests that provoke errors on purpose (error injection, illegal stimulus, timeout
tests), so that the test passes only when exactly the expected messages appear and nothing
else does. This is what guide rule MSG-9 asks for: a passing test has no errors, and expected
errors are caught by ID. Use `demote` for a known, tolerated message that should not fail the
run.

Do not use it to silence errors you do not understand. Do not use it to change messages of a
passing test into a different format; that is the report server's job. Do not lower the
verbosity of infos with it; use UVM's verbosity settings.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/report/hexk_report_catcher.sv`
- `src/uvm/report/hexk_report_catcher_rule.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/report/hexk_report_catcher.sv`:

```systemverilog
// Creates a catcher that is not registered anywhere; add_global() is the usual way to get one.
function new(string name = "hexk_report_catcher");
// Creates a catcher and registers it for the messages of every reporter.
static function hexk_report_catcher add_global();
// Expects min_count to max_count messages of severity sev, matching the expressions; they become demote_to.
function void expect_msg(string id_regex, uvm_severity sev = UVM_ERROR, string msg_regex = "", int unsigned min_count = 1, int max_count = -1, uvm_severity demote_to = UVM_INFO);
// Changes the severity of matching messages from one severity to another; they are not counted as expected.
function void demote(string id_regex, uvm_severity from, uvm_severity to, string msg_regex = "");
// Reports every expectation that saw fewer messages than its minimum or more than its maximum. The verdicts go through the root reporter of UVM: the `uvm_error of a catcher would report through the reporter of the last message that UVM gave to a catcher, with the actions of that reporter.
function void check_expectations();
// Number of messages caught so far by the rules registered with this ID expression and severity.
function int unsigned get_count(string id_regex, uvm_severity sev = UVM_ERROR);
// Removes every rule and count; the catcher stays registered.
function void clear();
// Applies the first matching rule to the message being reported; the message is always passed on.
function action_e catch();
```
<!-- HEXK_GEN:END api -->

`hexk_report_catcher_rule` is internal. Users call `expect_msg` and `demote`.

## 4. Behaviour and invariants

- A rule matches a message when the message has the rule's severity, its ID matches the ID
  expression and its text matches the text expression (an empty text expression matches any
  text). Expressions follow `hexk_regex`: a match anywhere counts, so anchor IDs with `^`
  and `$`.
- Rules are tried in the order they were added. The first rule that matches is applied and
  no other. A message that matches no rule is not touched.
- Applying a rule changes the severity of the message and gives it the actions UVM has
  configured for the new severity. An error demoted to info is therefore not counted as an
  error, and a fatal demoted to info does not end the simulation.
- `expect_msg` rules count their matches and are checked by `check_expectations`:
  fewer than `min_count` is reported as `HEXK_CATCHER_MISSING`, more than `max_count` as
  `HEXK_CATCHER_EXCESS`. A `max_count` below 0 means no upper limit. `min_count` 0 with
  `max_count` 0 means "must not occur".
- `demote` rules also count their matches (`get_count`), but are never checked.
- `check_expectations` can be called more than once; it reports the state at each call and
  does not reset the counts. `clear` removes all rules and counts.
- The verdicts of `check_expectations` are errors of the root reporter of UVM, whatever
  reported the last message before the check. No `hexk_report_catcher` applies a rule to a
  message with the ID `HEXK_CATCHER_MISSING` or `HEXK_CATCHER_EXCESS`, so no rule, however
  broad, can hide a verdict. A report catcher of another class sees them like any other
  message.
- The catcher always passes the message on (`THROW`); it never swallows one.
- `add_global` registers the catcher for every reporter. Each call creates another catcher;
  catchers are consulted in the order they were added.

## 5. Configuration

None. No plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_CATCHER_EXCESS` | error |  |
| `HEXK_CATCHER_MISSING` | error |  |
<!-- HEXK_GEN:END emits -->

| ID | Meaning |
|---|---|
| `HEXK_CATCHER_MISSING` | an expectation saw fewer messages than its `min_count` |
| `HEXK_CATCHER_EXCESS` | an expectation saw more messages than its `max_count` |

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_report_catcher/hexk_report_catcher_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_catcher_example.sv
//
// Minimal use of hexk_report_catcher in a negative test: two parity errors are provoked on
// purpose, so exactly two errors with that ID are expected. They are demoted to info, and
// check_expectations() reports an error if there were fewer or more.
// In a real testbench expect_msg() is called by the test before the stimulus starts and
// check_expectations() in its check_phase. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_report_catcher_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   localparam int unsigned INJECTED_ERRORS = 2;

   hexk_report_catcher catcher;

   initial begin
      catcher = hexk_report_catcher::add_global();
      catcher.expect_msg("^DRV_PARITY$", UVM_ERROR, "", INJECTED_ERRORS, int'(INJECTED_ERRORS));

      `uvm_error("DRV_PARITY", "parity error on beat 3")
      `uvm_error("DRV_PARITY", "parity error on beat 7")

      catcher.check_expectations();
   end

endmodule : hexk_report_catcher_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Forgetting `check_expectations()`.** Without it a test that provokes nothing still
  passes. Call it in the test's `check_phase`.
- **Unanchored ID expressions.** `expect_msg("SB")` also catches `SB_LEFTOVER` and
  `USB_ERROR`. Write `"^SB_MISMATCH$"`.
- **`expect_msg(".*")`.** It demotes every error of the run. Expect the specific IDs the test
  provokes.
- **Expecting with the wrong severity.** The default severity is `UVM_ERROR`; a provoked
  `` `uvm_fatal `` needs `expect_msg(id, UVM_FATAL)`.
- **Adding a catcher per sequence.** Every `add_global` call adds one more catcher to every
  report. Create one in the test and pass the handle.
- **Using `demote` where a count matters.** `demote` never fails a test. If the message must
  occur, use `expect_msg` with a `demote_to` severity.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
