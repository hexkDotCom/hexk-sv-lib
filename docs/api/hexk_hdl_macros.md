# hexk_hdl_macros

## 1. Summary

Read, deposit, force and release of a signal by its HDL path as text, with the return code
checked and a message that names the path and carries the caller's ID.

## 2. When to use / when not to use

Use the macros where a testbench must reach a signal that has no port and no interface: a
backdoor look at a counter or a state register, a deposit that puts a memory or a register
into a state that would take long to reach, a force of a strap or of an input of a block
that is not connected yet. `uvm_hdl_read()` and its relatives return 0 when the path is wrong
or the simulator gives no access, and a call that ignores that returns without having done
anything; the macros make that an error. Use `` `hexk_hdl_check_path_or_fatal `` once per
path at the start of a test, so that a renamed signal ends the test at time 0.

Do not use them where an interface or a `bind` can carry the signal: a path as text is not
checked by the compiler and breaks silently when the design is restructured. Do not use
them for registers that a `uvm_reg` model describes; its backdoor does the same with the
paths kept in one place. Do not use them in code that must run on a simulator without
programming-interface access, such as Verilator.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_hdl_macros.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_hdl_macros.svh`:

```systemverilog
// Reads the signal at PATH into the variable VALUE; reports an error with ID when it cannot be read.
`define hexk_hdl_read(PATH, VALUE, ID)
// Sets the signal at PATH to VALUE until its driver or a later deposit changes it; error with ID on failure.
`define hexk_hdl_deposit(PATH, VALUE, ID)
// Holds the signal at PATH at VALUE against its drivers until it is released; error with ID on failure.
`define hexk_hdl_force(PATH, VALUE, ID)
// Ends a force of the signal at PATH; reports an error with ID when that fails.
`define hexk_hdl_release(PATH, ID)
// Reports a fatal with ID when PATH does not exist or the simulator gives no access to it.
`define hexk_hdl_check_path_or_fatal(PATH, ID)
```

The file also defines building blocks of these, marked "Internal" in the source; they may change, do not call them.
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- Each macro is one complete statement; write no semicolon after it. It can be used in a
  class, a module, an interface or a package function: the message goes through the reporter
  of the calling scope. No time passes in a macro.
- `PATH` is a string expression with the full hierarchical path, evaluated once. `ID` is the
  message ID of the caller.
- `` `hexk_hdl_read(PATH, VALUE, ID) ``: `VALUE` is an integral variable. On success it gets
  the value of the signal, cut or extended with zeros to its width; X and Z bits are kept
  when the variable is four-state. On failure `VALUE` is left as it was and an error with
  `ID` is reported.
- `` `hexk_hdl_deposit(PATH, VALUE, ID) `` sets the signal as an assignment would: the next
  assignment or driver update changes it again. `` `hexk_hdl_force(PATH, VALUE, ID) `` holds
  it against all drivers until `` `hexk_hdl_release(PATH, ID) ``. After the release a net
  returns to what its drivers say; a variable keeps the forced value until its next
  assignment. `VALUE` is an integral expression, evaluated once.
- A value has at most `UVM_HDL_MAX_WIDTH` bits (1024 unless UVM is compiled with another
  value); wider signals cannot be reached this way.
- A failure is an error with `ID` and the text
  `cannot <read|deposit ...|force ...|release> HDL path '<path>'; check the path and that the simulator gives access to it`.
  Execution continues after the macro. The simulator or UVM usually reports the same failure
  with a message of its own before that (on Questa an error `vsim-16132`, with the DPI code
  of UVM an error `UVM/DPI/HDL_SET` or `UVM/DPI/HDL_GET`).
- `` `hexk_hdl_check_path_or_fatal(PATH, ID) `` reports a fatal with `ID` when the path cannot
  be reached, and nothing else. It does not tell a wrong path from missing access; the
  simulator cannot either.
- The macros do not count in `hexk_check_stats`: they are accesses, not checks.
- The simulation must give programming-interface access to the signals: read access for
  `` `hexk_hdl_read `` and the path check, write access for the others. On Questa 2024.1 that
  is `vsim -voptargs=-access=rw+<module>` (or `+acc`), on VCS X-2025.06 `-debug_access+r+w+f`;
  the unit tests and the example of the library use these. Other simulators have options of
  their own for the same thing; none of them has been run with these macros.
- When UVM is compiled with `UVM_HDL_NO_DPI`, as it must be for Verilator, UVM replaces its
  access functions by ones that report a fatal. A macro then ends the simulation with that
  fatal of UVM.

## 5. Configuration

There are no settings and no plusargs. The width limit is the UVM define `UVM_HDL_MAX_WIDTH`.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

The macros report with the ID that the caller passes.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_hdl_macros/hexk_hdl_macros_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_hdl_macros_example.sv
//
// Minimal use of the HDL access macros: a counter and a status net stand for a design, and
// the test reaches them by their paths as text. It checks a path before the first access,
// reads the counter, deposits a new count, forces the status net and releases it, and at the
// end reads a path with a typing error, which is reported with the path.
// Needs UVM with its DPI code, src/uvm/hexk_uvm.f, and a simulation that gives read and
// write access to the signals of this module, on Questa
// vsim -voptargs=-access=rw+hexk_hdl_macros_example. Without that access every macro reports.

module hexk_hdl_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   `include "hexk_macros.svh"

   // What stands for the design.
   bit          clk;
   bit    [7:0] count;
   wire         busy;

   // Path of this module; a testbench has the paths of its design in its configuration.
   string       scope = $sformatf("%m");

   logic  [7:0] count_seen;
   logic        busy_seen;

   assign busy = (count != 0);

   always #5ns clk = !clk;

   always @(posedge clk) begin
      count <= count + 8'd1;
   end

   // Reads both signals by path and prints them.
   task automatic show(string what);
      `hexk_hdl_read({scope, ".count"}, count_seen, "EXAMPLE_HDL")
      `hexk_hdl_read({scope, ".busy"}, busy_seen, "EXAMPLE_HDL")
      `uvm_info("EXAMPLE", $sformatf("%s: count=%0d busy=%0b", what, count_seen, busy_seen), UVM_NONE)
   endtask : show

   initial begin
      // A wrong path or missing access ends the test here, before any stimulus is spent.
      `hexk_hdl_check_path_or_fatal({scope, ".count"}, "EXAMPLE_HDL")

      #42ns;
      show("after four clocks");

      // The counter goes on from the deposited value.
      `hexk_hdl_deposit({scope, ".count"}, 8'd200, "EXAMPLE_HDL")
      #20ns;
      show("two clocks after a deposit of 200");

      // The net keeps the forced value whatever its driver says, until the release.
      `hexk_hdl_force({scope, ".busy"}, 1'b0, "EXAMPLE_HDL")
      #10ns;
      show("busy forced to 0");
      `hexk_hdl_release({scope, ".busy"}, "EXAMPLE_HDL")
      #10ns;
      show("busy released");

      // A typing error in a path is an error that names the path.
      `hexk_hdl_read({scope, ".cuont"}, count_seen, "EXAMPLE_HDL")
      $finish;
   end

endmodule : hexk_hdl_macros_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **A variable of your own named `hexk_hdl_path` or `hexk_hdl_value`.** The macros declare
  local variables of these names; an operand of the same name reads or writes the local
  instead, and nothing reports it. Names that start with `hexk_` belong to the library.
- **Paths typed at every use.** One typing error is one silent difference. Keep the paths of a
  block as constants or in its configuration object, and check each with
  `` `hexk_hdl_check_path_or_fatal `` at the start.
- **A force without a release.** The signal stays forced for the rest of the simulation, also
  in the next sequence. Release in the same task, also on the error path.
- **A deposit on a net with a driver.** The driver wins at its next update, or at once. Use a
  force, or deposit on the variable that drives the net.
- **A read in the middle of a time step to check a result.** What is read depends on the
  order of processes. Read after the clock edge at which the value is stable, as a monitor
  would.
- **Backdoor access as the only test of a feature.** A deposit that sets a state does not
  show that the design can reach it.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The seven tests of the
accesses run on Questa and VCS; on Verilator, where UVM is compiled without its HDL access, one
test checks that every macro reports.
