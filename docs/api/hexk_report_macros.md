# hexk_report_macros

## 1. Summary

Report macros for the places where the `` `uvm_* `` report macros do not work or do not fit:
static methods of UVM classes, modules and interfaces, and classes derived from
`uvm_report_catcher`.

## 2. When to use / when not to use

Use them in:

- a static method of a class derived from `uvm_report_object` (components, sequences),
  where `` `uvm_error `` does not compile because it calls a non-static method;
- modules and interfaces (BFMs, protocol checkers, the testbench top) whose messages should
  go through UVM reporting instead of `$error`, so that they are counted, filtered and
  catchable like every other message;
- a class derived from `uvm_report_catcher` that reports outside its `catch()` method, where
  the `` `uvm_* `` macros bind to the catcher's own report methods.

Do not use them anywhere else. In every other class the `` `uvm_* `` macros are right
(guide rule MSG-1): they report through the component, so the message carries its
hierarchical name and obeys its verbosity and action settings. Using these macros in
static methods, modules and interfaces is a deliberate deviation from MSG-1.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_report_macros.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_report_macros.svh`:

```systemverilog
// Reports an info with the given verbosity through the root reporter of UVM.
`define hexk_static_info(ID, MSG, VERBOSITY)
// Reports a warning through the root reporter of UVM.
`define hexk_static_warning(ID, MSG)
// Reports an error through the root reporter of UVM.
`define hexk_static_error(ID, MSG)
// Reports a fatal through the root reporter of UVM; the simulation ends unless a catcher demotes it.
`define hexk_static_fatal(ID, MSG)
```
<!-- HEXK_GEN:END api -->

`ID` and `MSG` are string expressions, `VERBOSITY` is a UVM verbosity such as
`uvm_pkg::UVM_LOW`.

## 4. Behaviour and invariants

- Each macro is one complete `begin ... end` statement, like the `` `uvm_* `` macros: it is
  safe after `if` without `begin`, and no semicolon follows it.
- The message goes through the root reporter of UVM. It is filtered by the global verbosity
  and by the severity and ID settings made on `uvm_root`, passed to the report catchers, and
  counted by the report server. Its context is the root reporter, not a component.
- File and line of the macro call are attached.
- `MSG` is evaluated only when the message is enabled, so an expensive `$sformatf` costs
  nothing for a filtered info.
- Warnings, errors and fatals use verbosity `UVM_NONE`: they are not filtered by verbosity.
- The macros name everything in `uvm_pkg` with its full name. The calling scope does not have
  to import `uvm_pkg`, but UVM must be compiled and `uvm_macros.svh` included, which
  `hexk_macros.svh` does.

## 5. Configuration

None.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

The macros report with the ID given by the caller.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_report_macros/hexk_report_macros_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_macros_example.sv
//
// Minimal use of the static report macros in a module: an info and an error that go through
// UVM reporting, so they obey the verbosity, are counted and can be caught, without the
// module importing uvm_pkg. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_report_macros_example;
   timeunit 1ns / 1ps;

   localparam int unsigned FIFO_DEPTH = 8;

   int unsigned level = FIFO_DEPTH + 1;

   initial begin
      `hexk_static_info("EXAMPLE_FIFO", $sformatf("depth is %0d", FIFO_DEPTH), uvm_pkg::UVM_LOW)
      if (level > FIFO_DEPTH) begin
         `hexk_static_error("EXAMPLE_FIFO_OVERFLOW", $sformatf("level %0d is above the depth %0d", level, FIFO_DEPTH))
      end
   end

endmodule : hexk_report_macros_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Using them in ordinary class methods.** The message loses the component's name and
  ignores its verbosity. Use `` `uvm_info `` and friends there.
- **`get_name()` or `get_full_name()` as the ID.** IDs are static, functional names (guide
  rule MSG-2), also here.
- **A semicolon after the macro before `else`.** `if (c) `hexk_static_error(...); else ...`
  does not compile, exactly as with `` `uvm_error ``.
- **`$display` or `$error` in an interface next to UVM code.** Those messages are invisible
  to the report server and to catchers. Use the static macros so one mechanism sees
  everything.
- **Expecting per-instance control.** All static reports share the root reporter; they cannot
  be silenced per interface instance. Put the instance name in the message text if needed.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
