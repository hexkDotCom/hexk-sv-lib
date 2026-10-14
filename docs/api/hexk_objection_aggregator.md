# hexk_objection_aggregator

## 1. Summary

Component that keeps the run-time phases alive while testbench objects still have work
outstanding, with one UVM objection per phase, and that can say who is busy and why.

## 2. When to use / when not to use

Use it for everything that must finish before a phase may end but is not the stimulus
itself: a scoreboard with expected items outstanding, a model with a transfer in flight, a
monitor inside a burst. Such objects implement `hexk_objectable` and are registered; they
never touch a UVM objection themselves. This is what guide rules OBJ-2 and OBJ-3 ask for:
completion is driven by the state of the checkers, not by a fixed delay, and no objection is
raised per transaction. When a test hangs, `report_busy()` turns "the test timed out" into
"`sb.rd` is waiting for 3 items".

Do not use it for the stimulus: the test raises its own objection around its top-level
sequence (OBJ-1). Do not use it as a timeout; that is `hexk_watchdog`. Do not register an
object whose `is_busy()` can stay 1 for ever by design, such as a free-running clock
generator. Sequences that object on their own follow OBJ-6 and do not need the aggregator.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/eot/hexk_objectable.sv`
- `src/uvm/eot/hexk_objection_aggregator.sv`
- `src/uvm/eot/hexk_objection_member.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/eot/hexk_objectable.sv`:

```systemverilog
// 1 while the object has work outstanding that must finish before the phase may end.
pure virtual function bit is_busy();
// What the object is waiting for, for the report of busy objects; may have several lines.
pure virtual function string busy_reason();
```

From `src/uvm/eot/hexk_objection_aggregator.sv`:

```systemverilog
// Creates the aggregator; it does nothing until objects are registered.
function new(string name, uvm_component parent);
// Registers an object under a name for reports; from then on its is_busy() is asked at the end of phases.
function void register(hexk_objectable obj, string name);
// Says that a registered object has work outstanding; the phases stay alive until the matching drop().
function void raise(hexk_objectable obj, string why = "");
// Takes back one raise() of a registered object; the phases may end when nothing is raised or busy.
function void drop(hexk_objectable obj, string why = "");
// Who is busy and why, one line per reason; "nothing is busy" when nobody is.
function string report_busy();
// UVM callback: a task phase starts; objects that are raised keep it alive from the start.
function void phase_started(uvm_phase phase);
// UVM callback: nothing objects to the end of the phase any more; busy objects hold it back.
function void phase_ready_to_end(uvm_phase phase);
// UVM callback: a task phase has ended, also by a jump, which removes every objection.
function void phase_ended(uvm_phase phase);
// UVM callback: reports objects whose raise() calls were never matched by drop().
function void check_phase(uvm_phase phase);
```
<!-- HEXK_GEN:END api -->

`hexk_objection_member` is internal. The `phase_started`, `phase_ready_to_end`, `phase_ended`
and `check_phase` functions are UVM callbacks; user code does not call them.

## 4. Behaviour and invariants

Registration:

- `register(obj, name)` adds an object. `name` is what reports call it; the full name of
  the component is a good choice. A null handle and a second registration of the same object
  are errors and change nothing.
- There is no way to remove an object. An object that is no longer used is idle.

Two ways to be busy, which can be mixed:

- **Polled.** The object only implements `is_busy()`. When a phase is ready to end, that is
  when all UVM objections on it are dropped, the aggregator asks every registered object. If
  one is busy, it raises its objection on that phase, reports `HEXK_OBJECTION_BUSY` with the
  text of `report_busy()`, and asks again every `poll_interval_ps` until none is busy. Then it
  drops the objection, and UVM asks all components again. `is_busy()` is not looked at while a
  phase is running, only at its end.
- **Explicit.** The object calls `raise(obj, why)` when it starts to wait and `drop(obj, why)`
  when it is done. Calls are counted per object. The aggregator holds its objection while the
  count of any object is above 0. Use this when the object knows the two moments anyway; it
  costs no polling.

Objections:

- The aggregator holds at most one objection on each task phase that is executing: on
  `run_phase`, and on the phase of the UVM run-time schedule (`reset_phase`, `main_phase`, ...)
  that is executing at that time. Every `raise_objection` and `drop_objection` has a
  description (OBJ-4).
- There is no membership per phase: a raised or busy member holds every task phase that is
  executing. `docs/integration.md`, "Reset and end of test", has the order of reset, end of
  the phases and final checks that the library is written for.
- A raise that is outstanding when a task phase starts holds that phase from its start. This
  also covers a `raise()` made before the run-time phases began, and a phase jump: the jump
  removes all objections of the phase that is left, and the aggregator raises again in the
  phase that starts.
- A `drop()` while a polled object is still busy, and an idle poll while a raise is
  outstanding, both leave the objection in place. It is dropped when neither holds.
- UVM ends a phase after 20 rounds of "ready to end, then held again"
  (`uvm_phase::max_ready_to_end_iterations`), whatever a component says. One hold counts as
  one round however long it lasts.
- In a testbench that does not use the run-time schedule, its twelve phases all pass at time
  0 next to `run_phase`. An object that is busy at time 0 holds the first of them, and
  `run_phase` cannot end before they have all ended. The effect is the same as holding
  `run_phase`; only the phase named in `HEXK_OBJECTION_BUSY` is `pre_reset`.

Errors:

- `drop()` without an outstanding `raise()` of that object is `HEXK_OBJECTION_IMBALANCE` and
  is ignored. A `raise()` that is still outstanding in `check_phase` is the same error.
- `raise()` or `drop()` with an object that is not registered is `HEXK_OBJECTION_UNKNOWN` and
  is ignored.
- A `poll_interval_ps` of 0 is `HEXK_OBJECTION_POLL`; the phase is then not held back.

`report_busy()`:

- One line per reason, in the order of registration: `<name>: raised: <why>`,
  `<name>: raised <n> times: <why>` with the reason of the latest raise, and
  `<name>: busy: <busy_reason()>`. The part after the last colon is left out when the reason
  is empty. Further lines of a reason with several lines are indented by four spaces.
- `nothing is busy` when no object is raised or busy.
- It calls `is_busy()` and `busy_reason()` of every object and changes nothing.

`hexk_objectable`:

- `is_busy()` and `busy_reason()` are called from the phasing code and from reports. They
  must return at once, must not report through UVM, and must not change state.

## 5. Configuration

| Member | Default | Meaning |
|---|---|---|
| `poll_interval_ps` | `100_000` (100 ns) | Time in picoseconds between two looks at `is_busy()` while the end of a phase is held back. Set it in the test, to about one clock period of the slowest interface that a polled object watches. |

`poll_interval_ps` is a whole number of picoseconds (`docs/integration.md`, "Times"): write
`` `hexk_ps(10ns) `` or `10_000`.

There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_OBJECTION_BUSY` | info |  |
| `HEXK_OBJECTION_IMBALANCE` | error |  |
| `HEXK_OBJECTION_POLL` | error |  |
| `HEXK_OBJECTION_REGISTER` | error |  |
| `HEXK_OBJECTION_UNKNOWN` | error |  |
<!-- HEXK_GEN:END emits -->

`HEXK_OBJECTION_BUSY` has verbosity `UVM_LOW`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_objection_aggregator/hexk_objection_aggregator_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_objection_aggregator_example.sv
//
// Minimal use of hexk_objection_aggregator: a scoreboard that only says whether it is busy,
// and a test that raises one objection around its stimulus. The stimulus ends after 100 ns
// with two responses outstanding; they arrive at 250 ns. Without the aggregator the run
// phase would end at 100 ns. With it, the phase is held until the scoreboard is empty, and
// the log says who is waiting and for what. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_objection_aggregator_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   `include "uvm_macros.svh"

   // Scoreboard that counts outstanding responses; it never touches an objection itself.
   class hexk_example_scoreboard extends uvm_scoreboard implements hexk_objectable;
      local int unsigned outstanding;

      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      // The stimulus announces responses it expects.
      function void expect_responses(int unsigned count);
         outstanding += count;
      endfunction : expect_responses

      // The monitor delivers the responses; this example checks nothing else.
      function void all_responses_seen();
         outstanding = 0;
      endfunction : all_responses_seen

      virtual function bit is_busy();
         return outstanding != 0;
      endfunction : is_busy

      virtual function string busy_reason();
         return $sformatf("waiting for %0d responses", outstanding);
      endfunction : busy_reason
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator objections;
      hexk_example_scoreboard   scoreboard;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections = hexk_objection_aggregator::type_id::create("objections", this);
         scoreboard = hexk_example_scoreboard::type_id::create("scoreboard", this);
         objections.register(scoreboard, scoreboard.get_full_name());
         // The responses of this example come on a 10 ns grid.
         objections.poll_interval_ps = `hexk_ps(10ns);
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "stimulus");
         scoreboard.expect_responses(2);
         fork
            begin
               #250ns;
               scoreboard.all_responses_seen();
            end
         join_none
         #100ns;
         phase.drop_objection(this, "stimulus");
      endtask : run_phase

      function void report_phase(uvm_phase phase);
         super.report_phase(phase);
         `uvm_info("EXAMPLE", $sformatf("run phase ended at %0t", $realtime), UVM_NONE)
      endfunction : report_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_objection_aggregator_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **An objection per item** (`raise()` in `write()`, `drop()` on every match). It works,
  because the calls are only counted, but it is the hot path OBJ-3 warns about. Raise when the
  queue goes from empty to not empty and drop when it is empty again, or implement
  `is_busy()` and let the aggregator poll.
- **`is_busy()` that does work**: one that walks a large queue, reports, or waits. It is
  called at every poll. Return a comparison of a counter.
- **An empty `busy_reason()`.** The report then says only that the object is busy. Say what
  it waits for and how much: "3 items, oldest id 17 since 1200 ns".
- **Using the aggregator for the stimulus.** The top-level sequence is covered by the one
  objection of the test (OBJ-1). The aggregator is for what the stimulus leaves behind.
- **A fixed delay at the end of the test "to let things settle"** (OBJ-2). Register what has
  to settle instead.
- **Registering an object that is busy by design for ever.** The phase never ends, and the
  watchdog fires. Such an object is not an objectable.
- **A `poll_interval_ps` of a different order of magnitude than the testbench clocks.** Far
  below a clock period it costs simulation time; far above, every held phase ends late by up
  to one interval.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests call the
phase callbacks themselves, because the UVM phases do not run in a unit test simulation;
`run_test()` with the example runs in `make examples` on Questa and VCS.
