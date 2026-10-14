# hexk_wait_macros

## 1. Summary

Waits that cannot hang: wait for a condition, or run some statements, with a time limit
after which a UVM error (or fatal) with the caller's message ID is reported.

## 2. When to use / when not to use

Use them wherever testbench code waits for the DUT to do something that it might never do:
a driver waiting for `ready`, a sequence waiting for an interrupt, a test waiting for a
status bit. A hang then becomes an error with an ID, at the place that waited, long before
the global timeout. Use `hexk_wait_util` when the code wants to decide itself what a timeout
means.

Do not use them as the end-of-test mechanism or in place of the global timeout (guide rule
OBJ-7). Do not use a time limit where an event is certain to come; a plain `wait` or `@` is
right there. Do not use them in functions: time passes.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_wait_macros.svh`
- `src/uvm/stim/hexk_wait_util.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_wait_macros.svh`:

```systemverilog
// Internal: waits for a condition with a time limit and reports with the given severity. A condition that is X or Z is not true: wait() goes on waiting for it, so the timeout must report it too.
`define hexk_wait_or_report(COND, TIMEOUT, ID, SEVERITY)
// Internal: runs statements with a time limit and reports with the given severity.
`define hexk_spin_or_report(BODY, TIMEOUT, ID, SEVERITY)
// The time T of the calling scope as a whole number of picoseconds, for the _ps arguments of the library. Dividing by 1s gives seconds whatever the time unit of the caller is.
`define hexk_ps(T)
// Waits until COND is true; reports an error with ID if it is not true after TIMEOUT.
`define hexk_wait_timeout(COND, TIMEOUT, ID)
// Waits until COND is true; reports a fatal with ID if it is not true after TIMEOUT.
`define hexk_wait_timeout_fatal(COND, TIMEOUT, ID)
// Runs BODY, one or more statements with their semicolons; ends them with an error if they take longer than TIMEOUT.
`define hexk_spinwait(BODY, TIMEOUT, ID)
```

From `src/uvm/stim/hexk_wait_util.sv`:

```systemverilog
// The simulation time in picoseconds.
static function longint unsigned now_ps();
// Waits until flag is 1 or timeout_ps has passed; timed_out is 1 when the timeout came first.
static task wait_or_timeout(ref bit flag, input longint unsigned timeout_ps, output bit timed_out);
// Waits until the event is triggered or timeout_ps has passed; timed_out is 1 when the timeout came first.
static task wait_event_or_timeout(event e, longint unsigned timeout_ps, output bit timed_out);
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

Macros:

- Each macro is one complete `begin ... end` statement, like the `` `uvm_* `` macros: no
  semicolon follows it.
- `hexk_wait_timeout(COND, TIMEOUT, ID)` returns as soon as `COND` is true, at once if it
  already is. When `TIMEOUT` has passed and `COND` is still not true, it reports the error
  `timeout after <time> waiting for: <COND as text>` and returns; execution continues with
  the statement after the macro in both cases. `hexk_wait_timeout_fatal` reports a fatal.
- A condition that is X or Z is not true: a signal that never leaves X ends in the timeout
  report.
- When the condition becomes true in the very time step in which the timeout ends, nothing
  is reported.
- `hexk_spinwait(BODY, TIMEOUT, ID)` runs `BODY`. When `BODY` has not finished after
  `TIMEOUT`, its threads are ended, the error `timeout after <time>: the statements did not
  finish` is reported, and execution continues after the macro.
- `BODY` is one or more complete statements, each with its semicolon:
  `` `hexk_spinwait(wait_for_idle();, 1ms, "ID") ``.
- `TIMEOUT` is evaluated in the scope of the macro call, so a literal with a unit (`10us`)
  always means what it says.
- The message is reported through the reporter of the calling scope, like the check macros.
- Threads that the caller started before the macro are not affected: the macro ends only
  the threads it started itself.
- The waits are not counted in `hexk_check_stats`.

`hexk_wait_util`:

- `wait_or_timeout(flag, timeout_ps, timed_out)` returns when `flag` is 1 or `timeout_ps`
  picoseconds have passed. `timed_out` is 1 exactly when `flag` is still 0 at that moment. A
  timeout of 0 does not wait.
- `wait_event_or_timeout(e, timeout_ps, timed_out)` does the same for an event. An event that
  was triggered before the call is not seen.
- Nothing is reported; the caller decides.
- `timeout_ps` is a whole number of picoseconds, like every time that crosses the API of the
  library (`docs/integration.md`, "Times"), so it means the same whatever the time unit of
  the caller is. Write it as `` `hexk_ps(10us) `` or as `10_000_000`.
- `now_ps()` returns the simulation time in picoseconds.

`` `hexk_ps(T) ``:

- Gives the time `T` of the calling scope as a `longint` number of picoseconds: it divides
  `T` by `1s` in that scope, which gives seconds whatever its time unit is, and multiplies by
  10^12, rounding to the nearest picosecond.
- `T` is evaluated in the calling scope like any other expression, so a literal that is
  finer than the precision of that scope is what the simulator makes of it there.
- Exact up to 2^53 ps (about 2.5 hours); a longer time may be off by a picosecond.

## 5. Configuration

None.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

The macros report with the ID given by the caller.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_wait_macros/hexk_wait_macros_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_wait_macros_example.sv
//
// Minimal use of the wait macros: wait for a signal with a time limit, run statements with
// a time limit, and use hexk_wait_util where the outcome is wanted as a value.
// Here ready rises after 30 ns, so the first wait returns then without a message; the
// handshake task is slower than its limit and is ended with a UVM error.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_wait_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_wait_util;

   bit ready;
   bit timed_out;

   // Stands for a handshake that takes too long.
   task automatic slow_handshake();
      #500ns;
   endtask : slow_handshake

   initial begin
      #30ns;
      ready = 1;
   end

   initial begin
      `hexk_wait_timeout(ready, 100ns, "EXAMPLE_READY")
      $info("ready seen at %0t", $realtime);

      `hexk_spinwait(slow_handshake();, 200ns, "EXAMPLE_HANDSHAKE")

      ready = 0;
      hexk_wait_util::wait_or_timeout(ready, 50ns, timed_out);
      $info("second wait timed out: %0b", timed_out);
   end

endmodule : hexk_wait_macros_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`fork ... join_any; disable fork;` written by hand.** Without an enclosing `fork ... join`
  the `disable fork` also ends every other thread the caller started. The macros and
  `hexk_wait_util` contain that isolation.
- **A timeout without a unit** (`` `hexk_wait_timeout(done, 1000, "ID") ``). The number is then
  in the time unit of the calling scope, whatever that is. Write `1us`.
- **A time with a unit where picoseconds are expected**
  (`hexk_wait_util::wait_or_timeout(flag, 10us, timed_out)`). The literal becomes a number in
  the time unit of the caller, and the task reads it as picoseconds. Write `` `hexk_ps(10us) ``.
- **A condition with side effects.** `COND` is evaluated repeatedly and is turned into text
  for the message. Use a variable or a function without side effects.
- **A string literal inside `COND`.** The condition becomes part of the message as text;
  some tools reject a quote inside it. Compare against a variable or a parameter.
- **`BODY` without its semicolon.** `` `hexk_spinwait(wait_for_idle(), 1ms, "ID") `` does not
  compile. Write `wait_for_idle();`.
- **Using `hexk_wait_timeout` to end the test.** End of test is decided by objections
  (guide rules OBJ-1 to OBJ-7), not by waiting for a fixed time.
- **Ignoring that execution continues.** After a timeout the code after the macro runs with
  the condition still false. Check it again, or use the `_fatal` variant, if continuing
  makes no sense.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
