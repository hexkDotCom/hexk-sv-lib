# hexk_coverage

## 1. Summary

Two coverage helpers: `hexk_handshake_coverage`, the functional coverage of a valid/ready
handshake, and `` `hexk_cg_new ``, which creates a covergroup of a class only when the knob
`coverage` is on and names its instance.

## 2. When to use / when not to use

Use `hexk_handshake_coverage` for any interface with a valid and a ready signal, not only
`hexk_valid_ready`: connect it to a port of the monitor that writes one
`hexk_handshake_cycle_t` per clock cycle, as `cycle_ap` of `hexk_valid_ready_agent` does, or
call its `sample()` and `on_reset()` from the monitor. It shows whether the test stalled the
sender, starved the receiver and sent transfers back to back. Use `` `hexk_cg_new `` for every covergroup that a class declares, so that one
knob takes all functional coverage out of a simulation that does not need it (a debug run, a
performance run, a gate-level run) and every instance has a name that says where it is.

Do not use the handshake coverage for the payload; that needs a covergroup of the agent
which knows the fields. Do not use it as the protocol check: it does not report valid that
is taken back, it leaves that pair out. Do not use `` `hexk_cg_new `` for a covergroup with
constructor arguments or for one that is declared in a module or an interface.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/cov/hexk_handshake_coverage.sv`
- `src/uvm/hexk_coverage_macros.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/cov/hexk_handshake_coverage.sv`:

```systemverilog
// What valid and ready say in one clock cycle.
typedef enum { HEXK_HANDSHAKE_IDLE, HEXK_HANDSHAKE_WAIT, HEXK_HANDSHAKE_STALL, HEXK_HANDSHAKE_ACTIVE } hexk_handshake_state_e;
// One rising edge of the clock of a handshake, as a monitor saw it: whether a reset began since the edge before (also one that came and went between the two edges), whether the reset is asserted now, and valid and ready, which mean nothing while the reset is asserted.
typedef struct packed { bit reset_began;
// Creates the component, and its covergroups unless the knob coverage is 0.
function new(string name, uvm_component parent);
// The state that the two signals stand for.
static function hexk_handshake_state_e state_of(bit valid, bit ready);
// Analysis write: one rising edge; a reset that began forgets the cycle before, a cycle out of reset is sampled.
function void write(hexk_handshake_cycle_t t);
// Samples one clock cycle; call it once per cycle in which the interface is out of reset.
function void sample (bit valid, bit ready);
// Forgets the cycle before, so that no pair is counted across a reset.
function void on_reset();
// 1 when the covergroups exist, which they do unless the knob coverage was 0 at creation.
function bit is_enabled();
// Coverage of this instance in percent, the states and the pairs half each; 0 when the covergroups do not exist.
function real get_coverage();
// Number of calls of sample(), also through write().
function int unsigned num_samples();
```

From `src/uvm/hexk_coverage_macros.svh`:

```systemverilog
// Creates the covergroup CG of the calling class unless the knob coverage is 0, and names the instance.
`define hexk_cg_new(CG)
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- `hexk_handshake_coverage` is a `uvm_subscriber` of `hexk_handshake_cycle_t`, a packed
  struct with `reset_began`, `in_reset`, `valid` and `ready` for one rising edge of the
  clock. `write(cycle)` calls `on_reset()` when `reset_began` is 1, and then `sample(valid,
  ready)` when `in_reset` is 0.
- `sample(valid, ready)` is called once per clock cycle in which the interface is out of
  reset. The state of a cycle is one of four:

  | valid | ready | State | Meaning |
  |---|---|---|---|
  | 0 | 0 | `HEXK_HANDSHAKE_IDLE` | nothing offered, nothing accepted |
  | 0 | 1 | `HEXK_HANDSHAKE_WAIT` | the receiver waits for data |
  | 1 | 0 | `HEXK_HANDSHAKE_STALL` | the sender is held |
  | 1 | 1 | `HEXK_HANDSHAKE_ACTIVE` | a transfer |

- Two covergroups, each half of the coverage: `state_cg`, the four states, sampled every
  cycle, and `pair_cg`, the pairs of consecutive cycles, sampled when there was a cycle
  before. Of the sixteen pairs fourteen count; the bin of active after active is named
  `back_to_back`. The two pairs in which valid is taken back during a stall (stall followed
  by idle or wait) are ignored bins.
- The pairs are a covergroup of their own, sampled only when there is a pair, and not a
  cross with an `iff`: Questa 2024.1 counts such a cross wrong from the second instance of
  the covergroup on (seen 2026-10-14: pairs across a reset and a pair with the cycle before
  the first are counted); VCS X-2025.06 counts both forms right.
- `on_reset()` forgets the cycle before: the first cycle after it counts as a state and not
  as the second half of a pair.
- `get_coverage()` is the coverage of this instance in percent, the mean of
  `get_inst_coverage()` of the two covergroups; other instances do not change it. It is 0
  when the covergroups do not exist.
- `num_samples()` counts the calls of `sample()`, also those through `write()`, whether the
  covergroups exist or not.
- `` `hexk_cg_new(CG) `` stands in the constructor of the class that declares the covergroup
  `CG`, where `CG = new();` would stand, without a semicolon. It creates the covergroup
  unless the knob `coverage` of `hexk_knobs` exists and is 0, and sets `option.name` of the
  instance to `<get_full_name() of the object>.<CG>`. When the covergroup is not created the
  variable stays `null`; the class tests that before it samples.
- The knob is read when the object is created. A knob that exists must be locked by then
  (`hexk_knobs::lock()`, which `hexk_base_test` calls in its `build_phase`), or the read is
  the fatal `HEXK_KNOBS_READ`. When no knob `coverage` is defined the covergroup is created.
- `option.per_instance` and `option.get_inst_coverage` can be set in the declaration of a
  covergroup only; the macro cannot set them. `state_cg` and `pair_cg` set both to 1; a covergroup of
  your own sets `option.per_instance = 1` in its declaration, and
  `option.get_inst_coverage = 1` when its instance coverage is read.
- On a simulator that does not build covergroups, such as Verilator 5.046, everything
  compiles and runs, and the coverage is 0.
- VCS X-2025.06 warns for every covergroup with `option.get_inst_coverage = 1` that the
  option has no effect without `type_option.merge_instances` (`Warning-[FCOPIGN]`). The
  warning can be ignored: `get_inst_coverage()` returns the coverage of the instance on VCS
  with or without the option, and Questa needs the option for that.

## 5. Configuration

| Knob of `hexk_knobs` | Default | Meaning |
|---|---|---|
| `coverage` | 1, defined by `hexk_base_test` | 0: `` `hexk_cg_new `` creates nothing; `+coverage=0` on the command line switches coverage off. A testbench without the base test defines the knob itself with `knobs.add_bit("coverage", 1, "...")`, or leaves it out: covergroups are created when it is absent. |

There are no plusargs of the module itself.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_coverage/hexk_coverage_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_coverage_example.sv
//
// Minimal use of the coverage helpers: a monitor of a valid/ready stream writes one
// hexk_handshake_cycle_t per clock cycle to its port cycle_ap, where the test connects a
// hexk_handshake_coverage, and has a covergroup of its own for the transferred data, which it
// creates with `hexk_cg_new. The test defines the knob coverage, drives the stream with random
// gaps and backpressure for 300 cycles, and prints both coverage numbers at the end. With
// +coverage=0 on the command line no covergroup is created and the test says so.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_coverage_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_handshake_coverage;
   import hexk_uvm_pkg::hexk_handshake_cycle_t;
   `include "hexk_macros.svh"

   // The stream that is covered.
   bit       clk;
   bit       rst_n;
   bit       valid;
   bit       ready;
   bit [7:0] data;

   always #5ns clk = !clk;

   class hexk_example_monitor extends uvm_component;
      // One record per rising edge of the clock.
      uvm_analysis_port #(hexk_handshake_cycle_t) cycle_ap;

      // verilator lint_off COVERIGN
      // verilator lint_off UNDRIVEN
      covergroup data_cg with function sample (bit [7:0] value);
         option.per_instance = 1;
         option.get_inst_coverage = 1;
         value_cp: coverpoint value {bins zero = {0}; bins low = {[1 : 127]}; bins high = {[128 : 255]};}
      endgroup : data_cg
      // verilator lint_on UNDRIVEN
      // verilator lint_on COVERIGN

      `uvm_component_utils(hexk_example_monitor)

      function new(string name, uvm_component parent);
         super.new(name, parent);
         cycle_ap = new("cycle_ap", this);
         // Where "data_cg = new();" would stand: created unless the knob coverage is 0.
         `hexk_cg_new(data_cg)
      endfunction : new

      task run_phase(uvm_phase phase);
         hexk_handshake_cycle_t cycle;
         bit                    was_in_reset;
         forever begin
            @(posedge clk);
            cycle.reset_began = !rst_n && !was_in_reset;
            cycle.in_reset    = !rst_n;
            cycle.valid       = valid;
            cycle.ready       = ready;
            cycle_ap.write(cycle);
            was_in_reset = !rst_n;
            if (rst_n && valid && ready && data_cg != null) begin
               data_cg.sample(data);
            end
         end
      endtask : run_phase

      // Coverage of the data with one decimal, or "off".
      function string data_coverage();
         if (data_cg == null) begin
            return "off";
         end
         return $sformatf("%0.1f%%", data_cg.get_inst_coverage());
      endfunction : data_coverage
   endclass : hexk_example_monitor

   class hexk_example_test extends uvm_test;
      hexk_example_monitor    monitor;
      hexk_handshake_coverage handshake;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         hexk_knobs knobs = hexk_knobs::get();
         super.build_phase(phase);
         // The knob must be final before the first covergroup is created.
         knobs.add_bit("coverage", 1, "functional coverage: covergroups are created");
         knobs.lock();
         monitor   = hexk_example_monitor::type_id::create("monitor", this);
         handshake = hexk_handshake_coverage::type_id::create("handshake", this);
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         monitor.cycle_ap.connect(handshake.analysis_export);
      endfunction : connect_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "stimulus");
         repeat (2) @(negedge clk);
         rst_n = 1;
         repeat (300) begin
            @(negedge clk);
            // A sender that is held keeps valid and data; otherwise it sends in two cycles of three.
            if (!(valid && !ready)) begin
               valid = ($urandom_range(0, 2) != 0);
               data  = 8'($urandom_range(0, 255));
            end
            ready = ($urandom_range(0, 2) != 0);
         end
         phase.drop_objection(this, "stimulus");
      endtask : run_phase

      function void report_phase(uvm_phase phase);
         if (!handshake.is_enabled()) begin
            `uvm_info("EXAMPLE", $sformatf("coverage is off; %0d cycles seen", handshake.num_samples()), UVM_NONE)
         end else begin
            `uvm_info("EXAMPLE", $sformatf(
                      "%0d cycles: handshake coverage %0.1f%%, data coverage %s",
                      handshake.num_samples(),
                      handshake.get_coverage(),
                      monitor.data_coverage()
                      ), UVM_NONE)
         end
      endfunction : report_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_coverage_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`sample()` during reset.** The signals mean nothing then, and the cycle after the reset
  would pair with one before it. Call `on_reset()` instead.
- **`sample()` on every change of a signal.** The states are per clock cycle; call it at the
  clock edge at which the monitor samples the interface.
- **`my_cg.sample()` without a test for `null`.** With the knob at 0 that is a null handle.
- **`my_cg = new();` next to the macro.** The covergroup then exists whatever the knob says.
- **A covergroup created with the macro before the knobs are locked.** The read of the knob
  is a fatal. Create components in `build_phase`, after the test has locked the knobs.
- **Waiting for 100 % on an interface where a stall cannot happen.** Exclude the bins in
  the coverage tool, with the reason.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The tests of the coverage
numbers and of the instance name run on Questa and VCS; on Verilator, which does not build
covergroups, the tests of the knob, of the states and of the sample count run.
