# hexk_sim_compat

## 1. Summary

Simulator differences behind three macros, so that no other file tests simulator defines.

## 2. When to use / when not to use

Use `HEXK_SIM_NAME` for banners and log headers, and `HEXK_STACKTRACE` to print the call stack
at a point of failure. Library modules use the same macros. `HEXK_SIM_NO_PIN_MODEL` is for
code that needs nets with several drivers, drive strengths or `force`, as `hexk_pins_if` does.

Do not write `` `ifdef VCS `` (or any other simulator define) in your own files: if a new
simulator difference needs hiding, it belongs in this header. The macros are compile-time
only; they cannot tell you what a simulator supports at run time.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_sim_compat.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_sim_compat.svh`:

```systemverilog
// Simulator name as a string literal: "vcs", "questa", "xcelium", "verilator" or "unknown".
`define HEXK_SIM_NAME
// Defined where the simulator cannot model a net with several drivers, drive strengths and force.
`define HEXK_SIM_NO_PIN_MODEL
// Statement that prints the call stack; a statement without effect where unsupported or disabled.
`define HEXK_STACKTRACE
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- `HEXK_STACKTRACE` is a statement without its semicolon. Write `` `HEXK_STACKTRACE; `` in
  procedural code. Where no stack trace is available it is `$write("")`, a statement
  without effect, so the semicolon is never an empty statement that strict tools reject.
- Built-in choice of task:

  | Simulator define | `HEXK_SIM_NAME` | `HEXK_STACKTRACE` |
  |---|---|---|
  | `VCS` | `"vcs"` | `$stack` |
  | `QUESTA` | `"questa"` | `$stacktrace` |
  | `XCELIUM` | `"xcelium"` | `$stacktrace` |
  | `VERILATOR` | `"verilator"` | no effect |
  | none of them | `"unknown"` | no effect |

- `HEXK_SIM_NO_PIN_MODEL` is defined for `VERILATOR` and for no other simulator. Verilator
  5.046 rejects a drive strength on one bit of a net and a `force` on a net with a tristate
  driver, and does not resolve several drivers of a pin (probed on 2026-10-13). Test it
  with `` `ifdef `` around the code that needs such nets.
- A `HEXK_STACKTRACE` defined on the command line wins over the built-in choice.
  `HEXK_NO_STACKTRACE` wins over both.
- The mappings for Questa (`$stacktrace`) and VCS (`$stack`) were seen to print the call
  stack on Questa 2024.1 and VCS X-2025.06. The Xcelium mapping has not been run.

## 5. Configuration

| Compile-time switch | Effect |
|---|---|
| `+define+HEXK_NO_STACKTRACE` | `HEXK_STACKTRACE` has no effect |
| `+define+HEXK_STACKTRACE=<system task>` | use this task instead of the built-in choice |

No plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
No example file yet.
<!-- HEXK_GEN:END example -->

`examples/hexk_version/hexk_version_example.sv` prints `HEXK_SIM_NAME`. A stack trace at a
point of failure looks like this:

```systemverilog
`include "hexk_sim_compat.svh"

if (!queue_is_empty) begin
   $error("items left in the queue at end of test");
   `HEXK_STACKTRACE;
end
```

## 8. Anti-patterns

- **`` `HEXK_STACKTRACE `` without the semicolon.** The macro is a statement without its
  semicolon on every tool. Always write `` `HEXK_STACKTRACE; ``.
- **Testing simulator defines in testbench code.** Use `HEXK_SIM_NAME`, or add the difference
  to this header so there is one place to maintain.
- **Using `HEXK_STACKTRACE` at module scope.** It is a procedural statement; put it inside an
  `initial`, `always`, task or function.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
