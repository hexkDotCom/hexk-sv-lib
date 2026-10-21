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
// Creates a catcher that is not registered anywhere; add_to() and add_global() are the usual ways to get one.
function new(string name = "hexk_report_catcher");
// Creates a catcher and registers it for the messages of every reporter.
static function hexk_report_catcher add_global();
// Creates a catcher and registers it for the messages of one component (or other reporter) only, so that an expected error counts only when that component reports it. A null client is the fatal HEXK_CATCHER_CLIENT, and add_to() then returns null: a catcher for every reporter is made with add_global().
static function hexk_report_catcher add_to(uvm_report_object client);
// Expects min_count to max_count messages of severity sev, matching the expressions; they become demote_to. max_count is min_count unless given: the shortest call expects exactly one message. NO_LIMIT has no maximum.
function void expect_msg(string id_regex, uvm_severity sev = UVM_ERROR, string msg_regex = "", int unsigned min_count = 1, int max_count = SAME_AS_MIN, uvm_severity demote_to = UVM_INFO);
// Expects a check with this ID to fail exactly count times, with messages of severity sev: they are demoted to info and counted as an expectation, and hexk_check_stats allows the failures. One call instead of expect_msg() and hexk_check_stats::expect_failures(). id is the ID itself, not an expression: the rule compares it as text, so an ID with characters such as "." or "[" matches only itself.
function void expect_check(string id, int unsigned count = 1, uvm_severity sev = UVM_ERROR);
// Changes the severity of matching messages from one severity to another; they are not counted as expected.
function void demote(string id_regex, uvm_severity from, uvm_severity to, string msg_regex = "");
// Reports every expectation that saw fewer messages than its minimum or more than its maximum. The verdicts go through the root reporter of UVM: the `uvm_error of a catcher would report through the reporter of the last message that UVM gave to a catcher, with the actions of that reporter.
function void check_expectations();
// Number of messages caught so far by the rules registered with this ID expression and severity.
function int unsigned get_count(string id_regex, uvm_severity sev = UVM_ERROR);
// Removes every rule and count; the catcher stays registered, and check_unchecked() checks it again.
function void clear();
// Calls check_expectations() of every catcher created by add_to() or add_global() whose expectations were not checked since its last clear(); hexk_base_test calls it in its check phase, so that a test cannot forget it.
static function void check_unchecked();
// Applies the first matching rule to the message being reported; the message is always passed on.
function action_e catch();
```
<!-- HEXK_GEN:END api -->

`hexk_report_catcher_rule` is internal. Users call `expect_msg`, `expect_check` and `demote`.

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
  `HEXK_CATCHER_EXCESS`. Without a `max_count` (its default is `SAME_AS_MIN`) the maximum is
  the minimum, so `expect_msg("^DRV_PARITY$")` expects exactly one message and
  `expect_msg("^DRV_PARITY$", UVM_ERROR, "", 2)` exactly two. `hexk_report_catcher::NO_LIMIT`
  (-1) means no upper limit. `min_count` 0 with `max_count` 0 means "must not occur".
- `expect_check(id, count = 1, sev = UVM_ERROR)` is for a check macro that the test makes fail
  on purpose: it expects exactly `count` messages with exactly that ID and severity, demoted
  to info, and calls `hexk_check_stats::expect_failures(id, count)`, so that the failures do
  not fail the verdict of `hexk_base_test` either. `id` is the ID itself, not an expression: the
  rule compares it as text, so `expect_check("DATA[0]")` matches the ID `DATA[0]` and nothing
  else. `get_count` names the rule as `"^<id>$"`.
- `demote` rules also count their matches (`get_count`), but are never checked.
- `check_expectations` can be called more than once; it reports the state at each call and
  does not reset the counts. `clear` removes all rules and counts.
- Once a catcher has been checked, a message that takes an expectation over its `max_count`
  is reported as `HEXK_CATCHER_EXCESS` at once, as well as demoted: an expected error that
  comes after the check (for example in the check phase of a derived test, after `super`)
  cannot pass unnoticed. A later `check_expectations` reports the excess again.
- `hexk_report_catcher::check_unchecked()` calls `check_expectations` of every catcher created
  by `add_to` or `add_global` that was not checked since it was created or last cleared.
  `hexk_base_test` calls it in its check phase, after the check phases of the env, so in a
  test derived from it the expectations are checked even when the test does not call
  `check_expectations` itself; a test that calls it earlier in its check phase is not checked
  twice. An expectation added after a check makes the catcher unchecked again. A message that
  the test expects in a later phase is checked by the test itself.
- The verdicts of `check_expectations` are errors of the root reporter of UVM, whatever
  reported the last message before the check. No `hexk_report_catcher` applies a rule to a
  message with the ID `HEXK_CATCHER_MISSING` or `HEXK_CATCHER_EXCESS`, so no rule, however
  broad, can hide a verdict. A report catcher of another class sees them like any other
  message.
- The catcher always passes the message on (`THROW`); it never swallows one.
- `add_to(client)` registers the catcher for the messages of that component (or other
  reporter) only: an error with the same ID from another component neither counts nor is
  demoted by it (guide rule MSG-9). A null client is the fatal `HEXK_CATCHER_CLIENT`, after
  which `add_to` returns null; a catcher for every reporter comes from `add_global`.
- `add_global` registers the catcher for every reporter. Each call creates another catcher.
  UVM consults the global catchers first, in the order they were added, then those of the
  component. A rule matches the severity that the message has when it reaches the catcher,
  so a global rule that changes the severity first hides the message from the rules of a
  catcher of the component.

## 5. Configuration

None. No plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_CATCHER_CLIENT` | fatal |  |
| `HEXK_CATCHER_EXCESS` | error |  |
| `HEXK_CATCHER_MISSING` | error |  |
<!-- HEXK_GEN:END emits -->

| ID | Meaning |
|---|---|
| `HEXK_CATCHER_MISSING` | an expectation saw fewer messages than its `min_count` |
| `HEXK_CATCHER_EXCESS` | an expectation saw more messages than its `max_count`, at its check or, after the check, at the message that went over |
| `HEXK_CATCHER_CLIENT` | `add_to` was given a null client |

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
// purpose, so exactly two errors with that ID are expected: a count without a maximum is
// exact. They are demoted to info, and check_expectations() reports an error if there were
// fewer or more. In a real testbench expect_msg() is called by the test before the stimulus
// starts; a test derived from hexk_base_test has the expectations checked in its check
// phase, any other test calls check_expectations() in its check_phase. A check that fails on
// purpose is declared with expect_check(id, count). Needs UVM and src/uvm/hexk_uvm.f.

module hexk_report_catcher_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   localparam int unsigned INJECTED_ERRORS = 2;

   hexk_report_catcher catcher;

   initial begin
      catcher = hexk_report_catcher::add_global();
      catcher.expect_msg("^DRV_PARITY$", UVM_ERROR, "", INJECTED_ERRORS);

      `uvm_error("DRV_PARITY", "parity error on beat 3")
      `uvm_error("DRV_PARITY", "parity error on beat 7")

      catcher.check_expectations();
   end

endmodule : hexk_report_catcher_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Forgetting `check_expectations()` outside `hexk_base_test`.** Without it a test that
  provokes nothing still passes. A test derived from `hexk_base_test` gets it in the check
  phase; any other test calls it in its `check_phase`, or calls `check_unchecked()`.
- **A global expectation for an error that one component reports.** An error with the same
  ID from another component, such as a second scoreboard, then counts as the expected one.
  Add the catcher to the component: `hexk_report_catcher::add_to(env.result_sb)`.
- **`expect_msg` with `NO_LIMIT` for a message that the test provokes a known number of
  times.** An error storm then passes. Give the count, which is also the maximum.
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
- **`expect_msg` and `expect_failures` for a failing check.** Two declarations that can
  disagree; `expect_check(id, count)` makes both.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
