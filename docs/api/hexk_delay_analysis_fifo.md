# hexk_delay_analysis_fifo

## 1. Summary

Analysis FIFO whose items become visible a set time or a set number of clock events after
they were written, in the order in which they were written.

## 2. When to use / when not to use

Use it to model latency between two parts of a testbench without blocking the writer: a
monitor at the input of a pipelined DUT writes what it sees, and the predictor or scoreboard
on the other side must see each item only when the DUT has it at its output. Without the
FIFO, the monitor or the predictor would have to wait or count cycles themselves.

Do not use it to model a latency that varies per item and depends on data; that is a model.
Do not use it in place of a scoreboard that matches out of order. Do not use it to
synchronise two clock domains of the DUT model; it delays, it does not resample.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/tlm/hexk_delay_analysis_fifo.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/tlm/hexk_delay_analysis_fifo.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the FIFO; without a latency it behaves like uvm_tlm_analysis_fifo.
function new(string name, uvm_component parent = null);
// UVM callback: counts the clock events and moves the items into the FIFO when their delay is over.
task run_phase(uvm_phase phase);
// Gives the event whose triggers count as cycles for latency_cycles.
function void set_clock(event clock_event);
// Number of items that were written and are not visible yet.
function int unsigned num_in_flight();
// UVM FIFO method behind write() and put(): keeps the item aside until its delay is over.
function bit try_put(input T t);
// UVM FIFO method: as try_put(). UVM's own put() goes to the FIFO directly; the FIFO has no size limit, so this one never waits either.
task put(input T t);
// UVM FIFO method: empties the FIFO and drops the items that are not visible yet.
function void flush();
// hexk_objectable: 1 while items are waiting for the end of their delay or are visible and not yet read.
virtual function bit is_busy();
// hexk_objectable: how many items are waiting and how many are visible and not yet read.
virtual function string busy_reason();
```
<!-- HEXK_GEN:END api -->

`try_put`, `flush` and `run_phase` are methods of UVM that the class overrides; `is_busy` and
`busy_reason` implement `hexk_objectable`. Everything else is inherited from
`uvm_tlm_analysis_fifo`: `analysis_export`, `get`, `try_get`, `peek`, `used`, `is_empty` and
the get/peek exports.

## 4. Behaviour and invariants

- Type parameter: `T` is the type of the items, any type a `uvm_tlm_analysis_fifo` takes;
  its default, `int`, is only there so that the class has one. Give it the item class.
- `write()` through `analysis_export`, and `put()`/`try_put()`, never block and always
  accept the item. The item is kept aside and enters the FIFO when its delay is over. Until
  then `try_get()`, `used()` and `is_empty()` do not see it; `num_in_flight()` counts it.
- **Delay by time.** With `latency_cycles` 0 an item becomes visible `latency_ps`
  picoseconds after it was written. A time after `hexk_wait_util::LAST_PS` (about 2.56 hours
  of simulation) is never reached, as for every wait of the library: the item waits until a
  flush.
- **Delay by clock events.** With `latency_cycles` above 0 an item becomes visible when the
  event given with `set_clock()` has triggered that many times after the write; `latency_ps`
  is then ignored. A trigger in the time step of the write never counts, whichever of the two
  the simulator runs first: an item that a monitor writes at a clock edge becomes visible
  `latency_cycles` edges later, as in a pipeline of that many stages. It becomes visible
  in the time step of that edge; a reader that is blocked in `get()` gets it there.
- `latency_cycles` above 0 without `set_clock()` is the error `HEXK_DELAY_FIFO_CLOCK`,
  reported once; the items are then not delayed.
- With `latency_ps` 0, `latency_cycles` 0 and nothing waiting, an item is visible at once, in
  the call of `write()`.
- **Order.** Items become visible in the order in which they were written. Both values are
  read at the write, so they can change between two writes; an item with a shorter delay
  then waits behind the items written before it and never overtakes them.
- The FIFO has no size limit, like `uvm_tlm_analysis_fifo`.
- The FIFO keeps the handle that is written and does not copy the item; see
  `docs/integration.md`, "Items after they are published".
- Cost: a write with a delay appends one entry to the queue of waiting items, and a write
  without a delay while nothing waits goes to the FIFO at once. One thread per FIFO releases
  the items one after the other, and with a clock the counting thread looks at the items of
  the current time step only.
- `flush()` empties the FIFO and drops the items that are still waiting. An item written
  after the flush has its own delay only: it does not wait for the delay of a dropped item,
  also when the clock has stopped.
- The delays are served by `run_phase` of the FIFO. Items written before the run phase wait
  until it starts; items still waiting when the run phase ends are lost.
- `is_busy()` is 1 while an item is waiting for the end of its delay or is visible and not
  yet read; `busy_reason()` gives both numbers. Register the FIFO with
  `hexk_objection_aggregator`, and the phase is held until every item has arrived and was
  read. A FIFO that nobody reads holds the phase until `hexk_watchdog` ends the test and
  names it.

## 5. Configuration

| Member | Default | Meaning |
|---|---|---|
| `latency_ps` | 0 | Delay of an item in picoseconds, when `latency_cycles` is 0. |
| `latency_cycles` | 0 | Delay of an item in triggers of the clock event; 0 selects `latency_ps`. |

`latency_ps` is a whole number of picoseconds (`docs/integration.md`, "Times"): write
`` `hexk_ps(30ns) `` or `30_000`.

There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_DELAY_FIFO_CLOCK` | error |  |
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_delay_analysis_fifo/hexk_delay_analysis_fifo_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_analysis_fifo_example.sv
//
// Minimal use of hexk_delay_analysis_fifo: a monitor at the input of a DUT with a pipeline
// of three clock cycles writes what it sees; the predictor must get each input when the DUT
// has it at its output. The FIFO between the two holds every item for three clock events,
// so the predictor needs no knowledge of the pipeline and the monitor is never blocked.
// The FIFO is registered with the objection aggregator: the run phase does not end while an
// item is still on its way. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_delay_analysis_fifo_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay_analysis_fifo;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   `include "uvm_macros.svh"

   localparam int unsigned PIPELINE_DEPTH = 3;
   localparam int unsigned NUM_ITEMS = 4;

   bit   clk;
   event clk_event;

   always #5ns clk = !clk;
   always @(posedge clk) begin
      ->clk_event;
   end

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator       objections;
      hexk_delay_analysis_fifo #(int) pipeline_fifo;
      uvm_analysis_port #(int)        monitor_port;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections    = hexk_objection_aggregator::type_id::create("objections", this);
         pipeline_fifo = hexk_delay_analysis_fifo#(int)::type_id::create("pipeline_fifo", this);
         monitor_port  = new("monitor_port", this);
         pipeline_fifo.latency_cycles = PIPELINE_DEPTH;
         pipeline_fifo.set_clock(clk_event);
         objections.register(pipeline_fifo, pipeline_fifo.get_full_name());
         objections.poll_interval_ps = `hexk_ps(10ns);
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         monitor_port.connect(pipeline_fifo.analysis_export);
      endfunction : connect_phase

      task run_phase(uvm_phase phase);
         super.run_phase(phase);
         // The predictor: takes every item when it leaves the pipeline.
         fork
            forever begin
               int item;
               pipeline_fifo.get(item);
               `uvm_info("EXAMPLE", $sformatf("predictor got %0d at %0t", item, $realtime), UVM_NONE)
            end
         join_none
         // The monitor: sees one input per clock cycle.
         phase.raise_objection(this, "stimulus");
         for (int unsigned i = 0; i < NUM_ITEMS; i++) begin
            @(posedge clk);
            monitor_port.write(int'(100 + i));
            `uvm_info("EXAMPLE", $sformatf("monitor saw %0d at %0t", 100 + i, $realtime), UVM_NONE)
         end
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_delay_analysis_fifo_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **A `#delay` in the monitor or in `write()` of the receiver** to model the pipeline. The
  monitor then misses what happens meanwhile, and `write()` is a function. Put the FIFO
  between them.
- **Not registering the FIFO with the objection aggregator.** The last items are still on
  their way when the stimulus is done; the phase ends, and the scoreboard reports leftovers
  that are not real.
- **A clock event that is triggered at both edges**, or a signal change used as event. The
  latency is then counted in half cycles. Trigger a named event once per cycle.
- **Changing `latency_ps` to "catch up".** Items never overtake; a shorter latency only takes
  effect when the queue has drained.
- **A delayed FIFO per pipeline stage.** One FIFO with the total latency does the same.
- **A registered FIFO without a reader**, or a reader that stops before the end. The FIFO
  stays busy with the unread items, and the test ends only through the watchdog.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests start
`run_phase` themselves; `run_test()` with the example runs in `make examples` on Questa
and VCS.
