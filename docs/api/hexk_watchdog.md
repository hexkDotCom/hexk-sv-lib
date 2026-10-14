# hexk_watchdog

## 1. Summary

Watchdog component: ends a test that hangs with one fatal that says what was still going on,
after a global timeout or after a time without any heartbeat.

## 2. When to use / when not to use

Use one watchdog per test, created in the base test, as the safety net that guide rule OBJ-7
asks for. Set `global_timeout_ps` generously, to a few times the longest test. Let the
components that show progress, usually drivers and monitors, call `heartbeat()`, and set an
inactivity limit: a hung test then ends a short time after it stopped moving instead of at
the global timeout, and the fatal names the objects that were still busy.

Do not use it to end a test that works: a test ends through objections (OBJ-1, OBJ-2). Do not
use it for a wait on one condition in one place; that is `` `hexk_wait_timeout ``. Do not set
an inactivity limit in a testbench where nothing calls `heartbeat()`; it would fire in every
test.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/eot/hexk_watchdog.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/eot/hexk_watchdog.sv`:

```systemverilog
// Creates the watchdog; the limits are read when the run phase starts.
function new(string name, uvm_component parent);
// Says that the source made progress; any component may call it, as often as it likes.
function void heartbeat(string source);
// Sets the longest time in picoseconds without a heartbeat, counted from now; 0 switches the limit off.
function void set_inactivity_limit(longint unsigned limit_ps);
// Converts a text such as "500us" or "1.5ms" to whole picoseconds, rounded; returns 0 when the text is not <number><unit>, when the time is 2**63 ps or more, and when a time above 0 rounds to 0 ps.
static function bit parse_timeout(string text, output longint unsigned timeout_ps);
// UVM callback: reads +hexk_timeout and watches both limits until the run phase ends.
task run_phase(uvm_phase phase);
```
<!-- HEXK_GEN:END api -->

`run_phase` is a UVM callback; user code does not call it.

## 4. Behaviour and invariants

Limits:

- The watchdog works during the run phase. When `run_phase` starts it reads `+hexk_timeout`,
  reports the limits with `HEXK_WATCHDOG_START`, and starts both timers. When the run phase
  ends, the timers end with it.
- **Global timeout.** `global_timeout_ps` after the start of the run phase the watchdog reports
  the fatal. The value is read once, at the start of the run phase; set it before. 0 switches
  the limit off.
- **Inactivity.** When `inactivity_limit_ps` has passed since the latest of: the start of the
  run phase, the latest `heartbeat()`, the latest `set_inactivity_limit()`, the watchdog
  reports the fatal. 0, the default, switches the limit off.
- `set_inactivity_limit(limit_ps)` may be called at any time, also during the run; the new limit
  counts from the call. Use it to switch the limit off around a phase without activity, such
  as a long reset, and on again after it.
- A heartbeat does not move the global timeout.

Heartbeats:

- `heartbeat(source)` notes that `source` made progress now. `source` is any text; the full
  name of the calling component is a good choice. There is no registration: a source exists
  from its first heartbeat.
- A heartbeat costs two assignments and an array lookup; it may be called per item.

The fatal:

- Both limits end in `` `uvm_fatal("HEXK_WATCHDOG", ...) ``. Its text has the reason,
  `global timeout of <time> reached` or `no heartbeat for <time>`, then `Busy objects:` with
  `report_busy()` of the aggregator, or a line saying that none is connected, then
  `Heartbeats:` with one line per source in the order of their first heartbeat:
  `<source>: <n> heartbeats, last at <time>, <time> ago`.
- Times are printed in nanoseconds with three decimals, whatever `$timeformat` is.
- A fatal ends the simulation. If a report catcher demotes it, the global timer is finished
  and the inactivity timer waits for the next `set_inactivity_limit()`.

`+hexk_timeout` and `parse_timeout`:

- `+hexk_timeout=<number><unit>` replaces `global_timeout_ps`, whatever the test set. The number
  is unsigned and may have a decimal point; the unit is `fs`, `ps`, `ns`, `us`, `ms` or `s`
  in any case, as `hexk_report_cfg::time_unit_of()` reads it, and is required:
  `+hexk_timeout=500us`, `+hexk_timeout=1.5ms`. `0ps` switches the global timeout off.
- A value in any other form is the error `HEXK_WATCHDOG_ARG`, and `global_timeout_ps` keeps its
  value. So is a time of 2**63 ps (about 106 days) or more, which does not fit, and a time
  above 0 that rounds to 0 ps, such as `0.4ps`, which would switch the timeout off.
- `parse_timeout(text, timeout_ps)` is the conversion behind the plusarg. It returns 1 and the
  time in whole picoseconds, rounded (so `1500fs` is 2 ps), or 0 and a time of 0.

## 5. Configuration

| Member | Default | Meaning |
|---|---|---|
| `global_timeout_ps` | `1_000_000_000` (1 ms) | Longest time in picoseconds the run phase may take; 0 = off. Read at the start of the run phase. |
| `inactivity_limit_ps` | `0` (off) | Longest time in picoseconds without a heartbeat. Set it before the run phase, or with `set_inactivity_limit()` during it. |
| `aggregator` | `null` | `hexk_objection_aggregator` whose `report_busy()` goes into the fatal. |

| Plusarg | Meaning |
|---|---|
| `+hexk_timeout=<number><unit>` | Overrides `global_timeout_ps`. |

The two limits are whole picoseconds (`docs/integration.md`, "Times"): write
`` `hexk_ps(200ns) `` or `200_000`. `+hexk_timeout` takes a number with a unit.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_WATCHDOG` | fatal |  |
| `HEXK_WATCHDOG_ARG` | error |  |
| `HEXK_WATCHDOG_START` | info |  |
<!-- HEXK_GEN:END emits -->

`HEXK_WATCHDOG_START` has verbosity `UVM_MEDIUM`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_watchdog/hexk_watchdog_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_watchdog_example.sv
//
// Minimal use of hexk_watchdog: a test whose stimulus stops making progress. The driver
// gives a heartbeat for every item it sends; after the fifth item it waits for a response
// that never comes. The global timeout of 100 us would end the test much later; the
// inactivity limit of 200 ns ends it 200 ns after the last heartbeat, with a fatal that
// names the busy scoreboard and the last heartbeat of the driver.
// Run it with +hexk_timeout=1us to see the global timeout from the command line.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_watchdog_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::hexk_watchdog;
   `include "uvm_macros.svh"

   // Scoreboard that waits for one response for ever.
   class hexk_example_scoreboard extends uvm_scoreboard implements hexk_objectable;
      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function bit is_busy();
         return 1;
      endfunction : is_busy

      virtual function string busy_reason();
         return "waiting for the response to item 5";
      endfunction : busy_reason
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator objections;
      hexk_watchdog             watchdog;
      hexk_example_scoreboard   scoreboard;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections = hexk_objection_aggregator::type_id::create("objections", this);
         watchdog   = hexk_watchdog::type_id::create("watchdog", this);
         scoreboard = hexk_example_scoreboard::type_id::create("scoreboard", this);
         objections.register(scoreboard, scoreboard.get_full_name());
         watchdog.aggregator          = objections;
         watchdog.global_timeout_ps   = `hexk_ps(100us);
         watchdog.inactivity_limit_ps = `hexk_ps(200ns);
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "stimulus");
         repeat (5) begin
            #20ns;
            watchdog.heartbeat("driver");
         end
         // The response never comes: without the watchdog the test would hang here.
         wait (0);
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_watchdog_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **A global timeout as the way the test ends** ("run for 1 ms, then stop"). The test then
  ends with a fatal, and a shorter or longer DUT run changes the result. End the test with
  objections (OBJ-7).
- **A global timeout just above the expected length of the test.** A slower seed, a
  gate-level run or more traffic then fails without a bug. Keep a wide margin and let the
  inactivity limit catch the hangs early.
- **A heartbeat from a clock or from a free-running thread.** It proves nothing; the test
  can hang while the clock runs. Give heartbeats where work is completed: an item driven, a
  transaction monitored, an item matched.
- **One heartbeat source name for everything.** The fatal then cannot say which part
  stopped. Use the name of the component.
- **Setting `global_timeout_ps` in `run_phase`.** It is read when the run phase starts. Set it
  in `build_phase`, or use `+hexk_timeout`.
- **`+hexk_timeout=1000` without a unit.** It is an error on purpose: a bare number has a
  different meaning in every testbench.
- **Demoting `HEXK_WATCHDOG` to keep a regression green.** The test hung; fix the cause.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests start
`run_phase` themselves and demote the fatal. `+hexk_timeout` is not given to the unit test
simulation, which all suites share; its conversion is tested through `parse_timeout()`.
The example runs in `make examples` on Questa and VCS; its runs with `+hexk_timeout=1us`
and with a malformed value were done by hand on Questa 2024.1.
