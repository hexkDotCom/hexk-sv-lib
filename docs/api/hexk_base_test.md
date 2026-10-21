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
// Creates the test and its warning audit, so that allow_warning() works from the constructor on; everything else happens in build_phase.
function new(string name, uvm_component parent);
// UVM callback: sets up report server, catcher, warning audit, knobs, aggregator, registry and watchdog, and calls the hooks.
function void build_phase(uvm_phase phase);
// UVM callback: stops the objections of the run-time phases from propagating up the hierarchy, unless stop_objection_propagation is 0.
function void start_of_simulation_phase(uvm_phase phase);
// UVM callback: runs the stimulus of create_stimulus(), randomized, on stimulus_sequencer() under one objection, and returns when it has ended; it returns at once without a stimulus. It is meant to be extended: a derived test with a main_phase of its own calls super.main_phase() first, so that its own code runs after the stimulus (CMP-4).
task main_phase(uvm_phase phase);
// UVM callback: checks the expectations of the report catchers that nobody checked (guide MSG-9). The phase runs bottom-up, so the check phases of the env, where scoreboards report their leftovers, came first.
function void check_phase(uvm_phase phase);
// UVM callback: reports the warnings that the test did not allow and the statistics of the check macros.
function void report_phase(uvm_phase phase);
// UVM callback: reports the last line of the test, TEST PASSED or TEST FAILED.
function void final_phase(uvm_phase phase);
// Allows the warnings whose ID matches id_regex (as hexk_regex takes it; "^ID$" for one ID) with fail_on_warnings.
function void allow_warning(string id_regex);
// Hook: factory overrides of the test; called first in build_phase, before anything is created.
virtual function void do_type_overrides();
// Hook: knobs of the block or of the test; called in build_phase before the knobs are locked.
virtual function void define_knobs();
// Hook: creates the cfg of the block, through the factory, and returns it (null: no cfg); called after the factory overrides and the knobs, so that an override of a derived test reaches the cfg. build_phase randomizes it.
virtual function uvm_object create_cfg();
// Hook: changes to the cfg of the block before it is randomized, when knobs can be read. A test pins a rand knob with rand_mode(0) and an assignment, or switches a constraint with constraint_mode(): a plain assignment to a rand knob is overwritten by the randomization (guide CFG-10).
virtual function void modify_cfg();
// Hook: changes to the cfg of the block after it was randomized, the last step of build_phase: plain assignments, which no constraint checks, so only for values that no constraint relates to others.
virtual function void modify_randomized_cfg();
// Hook: the stimulus of the test, created when main_phase starts (the env exists then); main_phase randomizes it and starts it on stimulus_sequencer() under one objection. null, the default, starts nothing.
virtual function uvm_sequence_base create_stimulus();
// Hook: the sequencer that the stimulus starts on; null, the default, for a virtual sequence without a virtual sequencer.
virtual function uvm_sequencer_base stimulus_sequencer();
// 1 when there was no error or fatal so far, no failed check beyond the expected ones and, if require_checks is set, at least one check was executed.
function bit has_passed();
// The last line of the test: "TEST PASSED" or "TEST FAILED" with the counts behind the verdict.
function string result_text();
// How the simulation of the test ended: 1 with the verdict when a hexk_base_test was built, else 0. ABORTED when the simulation ended before final_phase of the test, as after a fatal or a $finish; otherwise PASSED or FAILED as in the last line, by has_passed().
static function bit get_verdict(output verdict_e verdict);
// Prints the banner of the verdict with $display, after the last message: the verdict in block letters, then "SIMULATION PASSED", "SIMULATION FAILED" or "SIMULATION FAILED - ABORTED" with the counts of the last line. In colour, with a face picked at random, when the report server colours its messages (+hexk_report_color). The final block of hexk_tb_top_inc.svh calls it; it prints nothing when no hexk_base_test was built.
static function void report_banner();
// The banner of report_banner(): the verdict in block letters, then the line with counts, which are the counts of the last line. With color, the letters are blocks in green or red, and face picks one of the faces of the verdict (modulo their number) for the line before; without it, the letters are made of '#' and no face and no escape code is printed.
static function string banner_text(verdict_e verdict, string counts, bit color, int unsigned face = 0);
```

From `src/uvm/base/hexk_tb_top_inc.svh`:

```systemverilog
// Installs the report server of the library with the settings of the +hexk_report_* plusargs; returns 1.
function automatic bit hexk_tb_install_report_server();
```
<!-- HEXK_GEN:END api -->

`build_phase`, `start_of_simulation_phase`, `main_phase`, `check_phase`, `report_phase` and
`final_phase` are UVM callbacks. `hexk_tb_install_report_server` and `hexk_tb_report_server_installed` are
declared in the module that includes `hexk_tb_top_inc.svh`; user code does not use them.

## 4. Behaviour and invariants

`hexk_base_test`, in `build_phase`, in this order:

1. `do_type_overrides()`, the hook for factory overrides (guide rule TST-2), before anything
   is created.
2. If `install_report_server` is 1 and no `hexk_report_server` is installed, one is
   installed with a new `hexk_report_cfg` (compact style) and the `+hexk_report_*` plusargs.
   A server installed by the testbench top is left alone; with `install_report_server` 0 so
   is any other report server. Then `catcher`, a global `hexk_report_catcher` of the test, is
   created, and `warnings`, the `hexk_warning_audit` of the test (created in `new()`), is added
   to the installed `hexk_report_server` as a listener.
3. The knobs: `perf_mode` (bit, default 0; `hexk_delay` honours it), `coverage` (bit,
   default 1; `` `hexk_cg_new `` honours it), `hexk_require_checks` (bit, default the
   value of the member `require_checks`) and `hexk_fail_on_warnings` (bit, default the value
   of the member `fail_on_warnings`), each only if it is not defined yet. Then `define_knobs()`, the hook for the knobs of the block or of
   the test.
4. `objections` (`hexk_objection_aggregator`), `watchdog` (`hexk_watchdog`, connected to the
   aggregator) and `eot_registry` (`hexk_eot_registry::get()`).
5. `knobs.lock()`. From here on knobs can be read. `require_checks` and `fail_on_warnings`
   take the values of their knobs; `fail_on_warnings` without an installed
   `hexk_report_server` is the error `HEXK_TEST_WARNING`.
6. `create_cfg()`, the hook in which a block base test creates its cfg with
   `type_id::create()` and returns it; the base test keeps it in `block_cfg`. It comes after
   `do_type_overrides()`, so a factory override of the cfg class, or of an object it creates,
   set by a derived test reaches the cfg; knobs can be read. A cfg created in `new()` would
   miss the overrides of derived tests.
7. `modify_cfg()`, the hook for changes to the cfg before it is randomized (guide rule
   CFG-10). A test pins a `rand` knob with `rand_mode(0)` and an assignment, or switches a
   constraint with `constraint_mode()`; a plain assignment to a `rand` knob is overwritten by
   the randomization.
8. The randomization of `block_cfg`, unless it is null; a failure is the fatal
   `HEXK_TEST_RAND`.
9. `modify_randomized_cfg()`, the hook for plain assignments after the randomization. No
   constraint checks them, so they suit values that no constraint relates to others.

The block base test fetches its interfaces and builds its env in its own `build_phase` after
`super.build_phase()`, with the randomized cfg.

`main_phase` calls `create_stimulus()`, the hook in which a test returns its stimulus (the env
exists by then). Without a stimulus (null, the default) it returns at once. Otherwise it raises
one objection, randomizes the stimulus (a failure is the fatal `HEXK_TEST_RAND`), starts it on
`stimulus_sequencer()` (null by default: a virtual sequence without a virtual sequencer, guide
rule SEQ-5), and drops the objection when the stimulus has ended. A derived test with a
`main_phase` of its own calls `super.main_phase()` first, so that the stimulus runs before its
own code (guide rule CMP-4: the phase returns and is meant to be extended).

A block base test overrides `build_phase` only to add to it, and calls
`super.build_phase(phase)` first. The members `knobs`, `objections`, `eot_registry`,
`watchdog` and `catcher` are set after that call; the limits of the watchdog can be set then.
A negative test expects the errors of one component with a catcher of
`hexk_report_catcher::add_to(component)`, and messages whose reporter does not matter with
`catcher` (`expect_check()`, `expect_msg()`); `check_phase` checks every such catcher that the
test did not check itself.

Warnings: `allow_warning(id_regex)` allows the warnings whose ID matches the expression
(`hexk_regex`; `"^ID$"` for one ID); it works from `new()` on. The audit sees what the report
server issues after the report catchers, so a warning that a catcher demoted is not counted.
With `fail_on_warnings` 1, `report_phase` reports every warning that was not allowed in one
error `HEXK_TEST_WARNING` (the number, and the first 20 as "ID: message"), and the test fails.
Warnings issued after the report phase of the test are not looked at.

Later phases:

- `start_of_simulation_phase` calls `set_propagate_mode(0)` on the objection of `run_phase`
  and of the twelve phases of the UVM run-time schedule (guide rule OBJ-5), unless
  `stop_objection_propagation` is 0. Phases of a user-defined domain are not touched.
  Without propagation, the `raised`, `dropped` and `all_dropped` callbacks and the objection
  counts of the components above the one that objects see nothing; a testbench that relies on
  them sets `stop_objection_propagation` to 0.
- `check_phase` calls `hexk_report_catcher::check_unchecked()`, which checks the
  expectations of every catcher of `add_to` or `add_global` that the test did not check
  itself; the phase runs bottom-up, so the check phases of the env come first.
- `report_phase` reports the table of `hexk_check_stats` with `HEXK_TEST_CHECKS`.
- `final_phase` reports the result. When there is no error and no fatal, `require_checks`
  is 1 and no check was counted in `hexk_check_stats`, it first reports the error
  `HEXK_TEST_NO_CHECKS` (guide rule TST-6: no errors alone is not a pass). When there is no
  error and no fatal but a check failed that the test did not expect, because a catcher
  demoted its message or its ID was switched off, it reports the error
  `HEXK_TEST_CHECK_FAILED`. Then it reports `HEXK_TEST_RESULT`:
  `TEST PASSED (<e> errors, <f> fatals, <c> checks executed)` or the same with
  `TEST FAILED`; `, <n> failed without an error` follows the counts when there is no error
  and no fatal and such checks exist.
- A test has passed when the report server has counted no error and no fatal,
  `hexk_check_stats::num_unexpected_failures()` is 0 and, if `require_checks` is 1,
  `hexk_check_stats::num_checks()` is above 0. The check macros count there, every
  comparison of a `hexk_scoreboard` counts there, and any other checker of the testbench can
  count there with `hexk_check_stats::record_pass(id)` and `record_fail(id)`. A negative test
  that makes checks fail on purpose declares them with `expect_check(id, count)` of its
  `hexk_report_catcher`, which expects their messages and allows the failures
  (`hexk_check_stats::expect_failures(id, count)`). `has_passed()` and `result_text()` give the
  verdict and the line at the moment they are called.
- The counts are those of the whole simulation. Messages that a report catcher demoted are
  not errors. The result line itself is an info, so that it does not change the counts.
- The verdict counts UVM reports and checks only. A `$error` or `$fatal` of a module, an
  interface, an assertion or the core package, and an error of the simulator, are not among
  them, so a regression also checks the log: `scripts/hexk_check_run.py` does
  ([docs/regression.md](../regression.md), guide rule TST-6).

The banner:

- `get_verdict(verdict)` (static) says how the simulation of the test ended: it returns 0 when
  no `hexk_base_test` was built, else 1 with `HEXK_TEST_ABORTED` when the simulation ended
  before `final_phase` of the test ran (a fatal, a `$finish` of the testbench, the end of the
  simulation time of the run script), else `HEXK_TEST_PASSED` or `HEXK_TEST_FAILED` by
  `has_passed()`, as in the last line. The test is the one whose `build_phase` ran last.
- `report_banner()` (static) prints, with `$display`, the verdict in block letters five lines
  high and then `SIMULATION PASSED`, `SIMULATION FAILED` or `SIMULATION FAILED - ABORTED`
  with the counts of the last line in parentheses. When the installed `hexk_report_server`
  colours its messages (`+hexk_report_color=1`), the letters are UTF-8 blocks in bold green
  (passed) or red, and a face picked at random for the verdict precedes the line; otherwise
  the letters are `#` and nothing but ASCII is printed. It prints nothing when no
  `hexk_base_test` was built. The face comes from `$urandom` of the calling process, so the
  same seed gives the same face.
- `banner_text(verdict, counts, color, face)` (static) gives that text without printing it;
  `face` picks one of the faces of the verdict, modulo their number.

`hexk_tb_top_inc.svh`:

- Written once in the body of the testbench top module:
  `` `include "base/hexk_tb_top_inc.svh" ``, after the interfaces and the DUT.
- It declares a variable whose initialiser installs the report server, with a new
  `hexk_report_cfg` and the `+hexk_report_*` plusargs. Initialisers run before all `initial`
  blocks, so every message of the simulation has the layout of the library.
- It contains the `initial` block that calls `run_test()`; the test is selected with
  `+UVM_TESTNAME` (guide rule TST-4). The include reads that plusarg itself and gives the name
  to `run_test()`, so that the test is also found where UVM is compiled with
  `UVM_CMDLINE_NO_DPI`, as on Verilator, and does not read the command line itself; elsewhere
  UVM's own reading wins and names the same test.
- It contains a `final` block that calls `hexk_base_test::report_banner()`, so the banner of
  the verdict is the last output of every simulation that ends, also after a fatal.
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
| `fail_on_warnings` | 0 | A warning that the test did not allow with `allow_warning()` fails the test. Set it in `new()`; the knob below overrides it. Off by default: UVM and its register layer warn about many harmless things, so turning it on is a choice of the project. |

| Plusarg | Meaning |
|---|---|
| `+perf_mode` | Knob defined by the base test: every `hexk_delay` returns 0. |
| `+coverage=0` | Knob defined by the base test: `` `hexk_cg_new `` creates no covergroup. |
| `+hexk_require_checks=0` | Knob defined by the base test: a test without executed checks may pass. |
| `+hexk_fail_on_warnings=1` | Knob defined by the base test: a warning that the test did not allow fails it. |

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
| `HEXK_TEST_RAND` | fatal |  |
| `HEXK_TEST_RESULT` | info |  |
| `HEXK_TEST_WARNING` | error |  |
<!-- HEXK_GEN:END emits -->

`HEXK_TEST_RESULT` has verbosity `UVM_NONE`, `HEXK_TEST_CHECKS` has `UVM_LOW`.
`HEXK_TEST_RAND`: the cfg of the block or the stimulus of the test could not be randomized.

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
// interface and widens the watchdog limit. The smoke test returns its stimulus from
// create_stimulus(): a sequence that sends a few values through the interface and checks each
// one; hexk_base_test randomizes and starts it in its main phase under one objection. The last
// line of the log is TEST PASSED with the number of checks.
// Run it with +UVM_TESTNAME=hexk_example_smoke_test; try +num_items=0 to see a test that
// fails because it checked nothing, and +hexk_knobs_help for the knobs.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

interface hexk_example_dut_if (
    input logic clk
);
   timeunit 1ns; timeprecision 1ps;
   logic [7:0] data_in;
   logic [7:0] data_out;

   // Puts value on the input and returns the output at the next rising edge of clk.
   task automatic apply(input logic [7:0] value, output logic [7:0] result);
      data_in = value;
      @(posedge clk);
      result = data_out;
   endtask : apply
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

   // Sends num_items values through the interface and checks that each comes out incremented.
   class hexk_example_smoke_seq extends uvm_sequence;
      // The interface, set by the test before the start, and the number of values, a knob of the sequence.
      virtual hexk_example_dut_if vif;
      rand int unsigned           num_items;

      // Without a value from the starter, a few values.
      constraint num_items_cstr {soft num_items inside {[1 : 8]};}

      `uvm_object_utils(hexk_example_smoke_seq)

      function new(string name = "hexk_example_smoke_seq");
         super.new(name);
      endfunction : new

      task body();
         logic [7:0] result;
         for (int unsigned i = 0; i < num_items; i++) begin
            vif.apply(8'(10 * i), result);
            `hexk_check_eq(result, 8'(10 * i + 1), "SMOKE_DATA")
         end
      endtask : body
   endclass : hexk_example_smoke_seq

   // Gives the smoke sequence as the stimulus of the main phase.
   class hexk_example_smoke_test extends hexk_example_block_base_test;
      `uvm_component_utils(hexk_example_smoke_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function uvm_sequence_base create_stimulus();
         hexk_example_smoke_seq seq = hexk_example_smoke_seq::type_id::create("seq");
         seq.vif       = vif;
         // hexk_base_test randomizes the stimulus: the knob of the test is pinned, not plainly assigned (CFG-10).
         seq.num_items = 32'(knobs.get_int("num_items"));
         seq.num_items.rand_mode(0);
         return seq;
      endfunction : create_stimulus
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
- **Overriding `final_phase` without calling `super.final_phase(phase)`.** The last line is
  then missing and the banner says ABORTED for a test that ended normally.
- **A negative test that only demotes the errors of the checks it fails on purpose.** The
  failed checks still count, and the test fails with `HEXK_TEST_CHECK_FAILED`. Declare them
  with `expect_check(id, count)` of the catcher, which does both.

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
