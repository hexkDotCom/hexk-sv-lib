# hexk_base_test

## 1. Summary

Optional common base test and an include for the testbench top module: together they set up
the report server, knobs, objection aggregator, end-of-test registry and watchdog, and end
every test with one line, `TEST PASSED` or `TEST FAILED`.

## 2. When to use / when not to use

Use `hexk_base_test` as the level between `uvm_test` and the base test of a block (guide rule
TST-1): it holds what every test of every block needs and nothing that belongs to one block.
A block base test extends it, builds its env and cfg, and overrides the hooks. Use
`hexk_tb_top_inc.svh` in the testbench top module instead of an `initial` block with
`run_test()`, so that the report server is installed before the first message.

Both are optional, and each works without the other. A project with its own common base
test can create the same building blocks itself: `docs/integration.md`, "Using the pieces from
your own base test", has the steps with code, and the contract documents of
`hexk_report_server`, `hexk_knobs`, `hexk_objection_aggregator`, `hexk_eot_registry` and
`hexk_watchdog` say more. Each policy of the base test can also be switched off one by one
(section 5). Do not put block-specific code into a copy of the base test; extend it.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/base/hexk_base_test.sv`
- `src/uvm/base/hexk_tb_top_inc.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/base/hexk_base_test.sv`:

```systemverilog
// Creates the test; everything else happens in build_phase.
function new(string name, uvm_component parent);
// Hook: factory overrides of the test; called first in build_phase, before anything is created.
virtual function void do_type_overrides();
// Hook: knobs of the block or of the test; called in build_phase before the knobs are locked.
virtual function void define_knobs();
// Hook: changes to the cfg of the block before it is randomized; called last in build_phase, when knobs can be read.
virtual function void modify_cfg();
// UVM callback: sets up report server, knobs, aggregator, registry and watchdog, and calls the hooks.
function void build_phase(uvm_phase phase);
// UVM callback: stops the objections of the run-time phases from propagating up the hierarchy, unless stop_objection_propagation is 0.
function void start_of_simulation_phase(uvm_phase phase);
// UVM callback: reports the statistics of the check macros.
function void report_phase(uvm_phase phase);
// UVM callback: reports the last line of the test, TEST PASSED or TEST FAILED.
function void final_phase(uvm_phase phase);
// 1 when there was no error or fatal so far, no failed check beyond the expected ones and, if require_checks is set, at least one check was executed.
function bit has_passed();
// The last line of the test: "TEST PASSED" or "TEST FAILED" with the counts behind the verdict.
function string result_text();
```

From `src/uvm/base/hexk_tb_top_inc.svh`:

```systemverilog
// Installs the report server of the library with the settings of the +hexk_report_* plusargs; returns 1.
function automatic bit hexk_tb_install_report_server();
```
<!-- HEXK_GEN:END api -->

`build_phase`, `start_of_simulation_phase`, `report_phase` and `final_phase` are UVM
callbacks. `hexk_tb_install_report_server` and `hexk_tb_report_server_installed` are
declared in the module that includes `hexk_tb_top_inc.svh`; user code does not use them.

## 4. Behaviour and invariants

`hexk_base_test`, in `build_phase`, in this order:

1. `do_type_overrides()`, the hook for factory overrides (guide rule TST-2), before anything
   is created.
2. If `install_report_server` is 1 and no `hexk_report_server` is installed, one is
   installed with a new `hexk_report_cfg` (compact style) and the `+hexk_report_*` plusargs.
   A server installed by the testbench top is left alone; with `install_report_server` 0 so
   is any other report server.
3. The knobs: `perf_mode` (bit, default 0; `hexk_delay` honours it), `coverage` (bit,
   default 1; `` `hexk_cg_new `` honours it) and `hexk_require_checks` (bit, default the
   value of the member `require_checks`), each only if it is not defined yet. Then `define_knobs()`, the hook for the knobs of the block or of
   the test.
4. `objections` (`hexk_objection_aggregator`), `watchdog` (`hexk_watchdog`, connected to the
   aggregator) and `eot_registry` (`hexk_eot_registry::get()`).
5. `knobs.lock()`. From here on knobs can be read. `require_checks` takes the value of its
   knob.
6. `modify_cfg()`, the hook for changes to the cfg of the block (guide rule CFG-10). The
   base test has no cfg of its own: a block base test creates its cfg in `new()`, changes it
   in `modify_cfg()`, and randomizes it in its `build_phase` after `super.build_phase()`.

A block base test overrides `build_phase` only to add to it, and calls
`super.build_phase(phase)` first. The members `knobs`, `objections`, `eot_registry` and
`watchdog` are set after that call; the limits of the watchdog can be set then.

Later phases:

- `start_of_simulation_phase` calls `set_propagate_mode(0)` on the objection of `run_phase`
  and of the twelve phases of the UVM run-time schedule (guide rule OBJ-5), unless
  `stop_objection_propagation` is 0. Phases of a user-defined domain are not touched.
- `report_phase` reports the table of `hexk_check_stats` with `HEXK_TEST_CHECKS`.
- `final_phase` reports the result. When there is no error and no fatal, `require_checks`
  is 1 and no check was counted in `hexk_check_stats`, it first reports the error
  `HEXK_TEST_NO_CHECKS` (guide rule TST-6: no errors alone is not a pass). When there is no
  error and no fatal but a check failed that the test did not expect, because a catcher
  demoted its message or its ID was switched off, it reports the error
  `HEXK_TEST_CHECK_FAILED`. Then it reports `HEXK_TEST_RESULT`:
  `TEST PASSED (<e> errors, <f> fatals, <c> checks executed)` or the same with
  `TEST FAILED`; `, <n> failed without an error` follows the counts when such checks exist.
- A test has passed when the report server has counted no error and no fatal,
  `hexk_check_stats::num_unexpected_failures()` is 0 and, if `require_checks` is 1,
  `hexk_check_stats::num_checks()` is above 0. The check macros count there, every
  comparison of a `hexk_scoreboard` counts there, and any other checker of the testbench can
  count there with `hexk_check_stats::record_pass(id)` and `record_fail(id)`. A negative test
  that makes checks fail on purpose declares them with
  `hexk_check_stats::expect_failures(id, count)`. `has_passed()` and `result_text()` give the
  verdict and the line at the moment they are called.
- The counts are those of the whole simulation. Messages that a report catcher demoted are
  not errors. The result line itself is an info, so that it does not change the counts.

`hexk_tb_top_inc.svh`:

- Written once in the body of the testbench top module:
  `` `include "base/hexk_tb_top_inc.svh" ``, after the interfaces and the DUT.
- It declares a variable whose initialiser installs the report server, with a new
  `hexk_report_cfg` and the `+hexk_report_*` plusargs. Initialisers run before all `initial`
  blocks, so every message of the simulation has the layout of the library.
- It contains the `initial` block that calls `run_test()` without an argument; the test is
  selected with `+UVM_TESTNAME` (guide rule TST-4).
- If the macro `HEXK_TB_PRE_RUN_TEST` is defined, as the name of a task or function of the
  module without arguments, it is called in that `initial` block before `run_test()`. This
  is the place for `` `hexk_vif_set ``. Define it before the include or with `+define+`.
- The file has an include guard: it can be included in one module of a compilation unit.

## 5. Configuration

| Member of `hexk_base_test` | Default | Meaning |
|---|---|---|
| `require_checks` | 1 | A test passes only if at least one check was counted. Set it in `new()` of a derived test; the knob below overrides it. |
| `install_report_server` | 1 | `build_phase` installs `hexk_report_server` unless it is installed already; 0 keeps whatever report server is installed. Set it in `new()`. |
| `stop_objection_propagation` | 1 | `start_of_simulation_phase` stops the propagation of the phase objections; 0 leaves UVM's propagation. Set it in `new()`. |

| Plusarg | Meaning |
|---|---|
| `+perf_mode` | Knob defined by the base test: every `hexk_delay` returns 0. |
| `+coverage=0` | Knob defined by the base test: `` `hexk_cg_new `` creates no covergroup. |
| `+hexk_require_checks=0` | Knob defined by the base test: a test without executed checks may pass. |

| Define | Meaning |
|---|---|
| `HEXK_TB_PRE_RUN_TEST=<name>` | Task or function that `hexk_tb_top_inc.svh` calls before `run_test()`. |

The plusargs of the report server, the knobs and the watchdog apply as described in their
own documents. With `+define+HEXK_NO_CHECK_STATS` the check macros are not counted; clear
`require_checks` then.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_TEST_CHECKS` | info |  |
| `HEXK_TEST_CHECK_FAILED` | error |  |
| `HEXK_TEST_NO_CHECKS` | error |  |
| `HEXK_TEST_RESULT` | info |  |
<!-- HEXK_GEN:END emits -->

`HEXK_TEST_RESULT` has verbosity `UVM_NONE`, `HEXK_TEST_CHECKS` has `UVM_LOW`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_base_test/hexk_base_test_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_base_test_example.sv
//
// A whole small testbench on hexk_base_test and hexk_tb_top_inc.svh.
// The top module has no initial block: the include installs the report server, calls
// publish_interfaces(), which is named by HEXK_TB_PRE_RUN_TEST, and then run_test().
// The block base test extends hexk_base_test: it adds a knob in define_knobs(), fetches the
// interface and widens the watchdog limit. The test drives a few values and checks each
// one, so the last line of the log is TEST PASSED with the number of checks.
// Run it with +UVM_TESTNAME=hexk_example_smoke_test; try +num_items=0 to see a test that
// fails because it checked nothing, and +hexk_knobs_help for the knobs.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

interface hexk_example_dut_if (
    input logic clk
);
   logic [7:0] data_in;
   logic [7:0] data_out;
endinterface : hexk_example_dut_if

module hexk_base_test_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_base_test;

   // Base test of this block: knobs, interface and limits that all its tests share.
   class hexk_example_block_base_test extends hexk_base_test;
      virtual hexk_example_dut_if vif;

      `uvm_component_utils(hexk_example_block_base_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function void define_knobs();
         knobs.add_int("num_items", 4, "values to send through the DUT", 0, 1000);
      endfunction : define_knobs

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         `hexk_vif_get_or_fatal(hexk_example_dut_if, "dut_vif", vif)
         watchdog.global_timeout_ps = `hexk_ps(10us);
      endfunction : build_phase
   endclass : hexk_example_block_base_test

   // Sends values and checks that each comes out incremented.
   class hexk_example_smoke_test extends hexk_example_block_base_test;
      `uvm_component_utils(hexk_example_smoke_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      task run_phase(uvm_phase phase);
         int unsigned num_items = 32'(knobs.get_int("num_items"));
         phase.raise_objection(this, "stimulus");
         for (int unsigned i = 0; i < num_items; i++) begin
            vif.data_in = 8'(10 * i);
            @(posedge vif.clk);
            `hexk_check_eq(vif.data_out, 8'(10 * i + 1), "SMOKE_DATA")
         end
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_smoke_test

   bit clk;
   hexk_example_dut_if dut_if (.clk(clk));

   always #5ns clk = !clk;

   // The input is idle until the test drives it.
   initial dut_if.data_in = '0;

   // Stands for the DUT: the output is the input plus one.
   assign dut_if.data_out = dut_if.data_in + 8'd1;

   // Called by the include before run_test().
   function automatic void publish_interfaces();
      `hexk_vif_set(hexk_example_dut_if, "uvm_test_top", "dut_vif", dut_if)
   endfunction : publish_interfaces

   `define HEXK_TB_PRE_RUN_TEST publish_interfaces
   `include "base/hexk_tb_top_inc.svh"

endmodule : hexk_base_test_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Overriding `build_phase` without `super.build_phase(phase)`**, or calling it last. The
  knobs, the watchdog and the aggregator then do not exist when the block base test needs
  them.
- **Defining knobs in `build_phase` of a derived test after `super.build_phase()`.** The
  knobs are locked by then. Use `define_knobs()`.
- **Clearing `require_checks` in the block base test** "because some tests have no checks".
  Every such test then passes without proving anything (TST-6). Clear it in the one test
  that checks in another way, and say how in a comment.
- **Parsing the log for `UVM_ERROR` instead of the result line**, or the other way round.
  The line is a summary for people; a regression script should use both the line and the
  exit status of its flow.
- **An `initial` block with `run_test()` next to the include.** The test is then started
  twice.
- **`` `hexk_vif_set `` in an `initial` block of its own.** It races with `run_test()`. Put
  it into the function named by `HEXK_TB_PRE_RUN_TEST`.
- **Raising the watchdog timeout in the base test until the slowest test fits.** Set a
  moderate limit there and a longer one in the slow test.
- **A negative test that only demotes the errors of the checks it fails on purpose.** The
  failed checks still count, and the test fails with `HEXK_TEST_CHECK_FAILED`. Declare them
  with `hexk_check_stats::expect_failures(id, count)` as well.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests call the
phase functions themselves, with a report server already installed. `hexk_tb_top_inc.svh`
and the path on which the base test installs the report server are covered by the example
only, which `make examples` runs on Questa and VCS. Its runs with `+num_items=0` (the test
fails for lack of checks) and with `+hexk_require_checks=0` were done by hand on Questa
2024.1.
