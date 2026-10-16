# hexk_eot_registry

## 1. Summary

End-of-test registry: one singleton component that, in `check_phase`, runs the final checks
of objects which are not components themselves.

## 2. When to use / when not to use

Use it for plain objects that hold state which must be clean when the test ends: a reference
model with predictions that must all be consumed, a memory model that must have no
uninitialised reads, the bookkeeping of a sequence library. Such an object implements
`hexk_checkable` and registers once. Without the registry it has no phase to report in, and
its leftovers are silently lost; guide rule CHK-5 requires them to be reported.

Do not use it for components: a scoreboard or monitor reports leftovers in its own
`check_phase`. Do not use it for checks that need time or the DUT: `eot_check()` is a
function that runs after the run-time phases. Do not use it to decide when the test may end;
that is `hexk_objection_aggregator`.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/eot/hexk_checkable.sv`
- `src/uvm/eot/hexk_eot_registry.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/eot/hexk_checkable.sv`:

```systemverilog
// Called once in check_phase: report leftovers and a wrong final state with `uvm_error. The formatter breaks a pure virtual prototype over three lines. verilog_format: off
pure virtual function void eot_check();
```

From `src/uvm/eot/hexk_eot_registry.sv`:

```systemverilog
// Creates a registry; use get(), which creates the one registry of the simulation.
function new(string name, uvm_component parent);
// The one registry of the simulation; the first call creates it and must come before the end of build_phase.
static function hexk_eot_registry get();
// Registers an object under a name for reports; its eot_check() is called in check_phase.
function void register(hexk_checkable obj, string name);
// Forgets every registered object; for unit tests, which run many tests in one simulation.
static function void reset_for_test();
// UVM callback: calls eot_check() of every registered object and names those that reported errors.
function void check_phase(uvm_phase phase);
```
<!-- HEXK_GEN:END api -->

`check_phase` is a UVM callback; user code does not call it. `new` exists for the UVM
factory; user code calls `get()`.

## 4. Behaviour and invariants

- `get()` always returns the same registry. The first call creates it through the factory,
  with the instance name `eot_registry`, as a child of `uvm_test_top` when the test
  exists at that moment, otherwise as a top-level component.
- The first `get()` must come before the end of `build_phase`: UVM creates no components
  later. A first call after that is the fatal `HEXK_EOT_LATE`. Call `get()` once in the
  `build_phase` of the base test (`hexk_base_test` does it); after that, objects may register
  at any time before `check_phase`, also during the run.
- `register(obj, name)` adds an object. `name` is what the summary calls it. A null handle
  and a second registration of the same object are errors (`HEXK_EOT_REGISTER`) and change
  nothing. There is no way to remove an object.
- In `check_phase` the registry calls `eot_check()` of every registered object once, in the
  order of registration.
- After the calls it reports `HEXK_EOT_CHECK` with the number of objects and the names of
  those during whose `eot_check()` the count of errors and fatals of the report server went
  up. An error that a report catcher demoted is not counted. With no object registered,
  nothing is reported.
- The registry does not fail the test by itself; the errors of the objects do.
- `reset_for_test()` forgets all registered objects and keeps the registry. It is for unit
  tests that run several tests in one simulation.

`hexk_checkable`:

- `eot_check()` reports with `` `uvm_error ``. It must not consume time and should not change
  the object, so that calling it twice gives the same messages.
- An object that is not a component reports through the global reporter; put the name of the
  object into the message text.

## 5. Configuration

None. There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_EOT_CHECK` | info |  |
| `HEXK_EOT_LATE` | fatal |  |
| `HEXK_EOT_REGISTER` | error |  |
<!-- HEXK_GEN:END emits -->

`HEXK_EOT_CHECK` has verbosity `UVM_MEDIUM`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_eot_registry/hexk_eot_registry_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_eot_registry_example.sv
//
// Minimal use of hexk_eot_registry: a reference model that is a plain object, not a
// component, checks at the end of the test that every request it predicted was consumed.
// The test creates the registry in build_phase by calling get(); the model registers
// itself. Here one prediction is left over, so check_phase ends with one error from the
// model. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_eot_registry_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_checkable;
   import hexk_uvm_pkg::hexk_eot_registry;
   `include "uvm_macros.svh"

   // Reference model without a place in the component tree.
   class hexk_example_model implements hexk_checkable;
      local int unsigned predicted;
      local int unsigned consumed;

      function new();
         hexk_eot_registry registry = hexk_eot_registry::get();
         registry.register(this, "example_model");
      endfunction : new

      function void predict();
         predicted++;
      endfunction : predict

      function void consume();
         consumed++;
      endfunction : consume

      virtual function void eot_check();
         if (predicted != consumed) begin
            `uvm_error("MODEL_LEFTOVER", $sformatf("%0d predictions were never consumed", predicted - consumed))
         end
      endfunction : eot_check
   endclass : hexk_example_model

   class hexk_example_test extends uvm_test;
      hexk_example_model model;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         // The registry must exist before build_phase ends.
         void'(hexk_eot_registry::get());
         model = new();
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         model.predict();
         model.predict();
         #10ns;
         model.consume();
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_eot_registry_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **The first `get()` from a sequence or from `run_phase`.** It is too late to create the
  component then (`HEXK_EOT_LATE`). Call `get()` in the `build_phase` of the test.
- **Registering a component.** It has a `check_phase`; use it. Registering it as well runs
  its checks twice.
- **An `eot_check()` that prints a statistic and checks nothing.** Statistics belong in
  `report_phase`. `eot_check()` is for conditions that make the test fail.
- **An `eot_check()` with `` `uvm_fatal ``.** The objects registered after it are then never
  checked. Report an error.
- **Relying on the order of registration between objects.** Each `eot_check()` should stand
  alone.
- **Registering in a loop without a distinct name.** The summary then lists the same name
  several times. Give every object its own name.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests call
`check_phase` themselves. `HEXK_EOT_LATE` is not covered by a unit test, because the build
phase cannot be ended there. `run_test()` with the example runs in `make examples` on
Questa and VCS: the registry is created under `uvm_test_top` and its `check_phase` runs.
