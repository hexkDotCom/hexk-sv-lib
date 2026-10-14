# hexk_uvm_pkg

## 1. Summary

UVM utility package of hexk-sv-lib: checks, reporting, end of test, knobs, delays,
scoreboard and memory model.

## 2. When to use / when not to use

Use it in UVM testbenches, next to `uvm_pkg`.

Do not use it in code that must run without UVM (Verilator testbenches, synthesizable or
bound RTL helpers); that code uses `hexk_core_pkg`.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_uvm_pkg.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
No public symbols yet.
<!-- HEXK_GEN:END api -->

The package holds the classes of the UVM layer. Each module has its own contract document;
`llms.txt` lists them.

## 4. Behaviour and invariants

- Supports UVM 1.2 and IEEE 1800.2-2017/2020; differences are isolated in
  `hexk_uvm_compat.svh`.
- Imports from `hexk_core_pkg` are explicit and are not re-exported.
- The package declares `timeunit 1ps; timeprecision 1ps;`. Every time that crosses its API is
  a `longint unsigned` number of picoseconds with a name that ends in `_ps`, so it means the
  same whatever the time unit of the caller is (`docs/integration.md`, "Times"). The
  simulation then has a precision of 1 ps or finer.
- Classes report with the `` `uvm_* `` macros and a static message ID that starts with
  `HEXK_`.

## 5. Configuration

| Integration | Value |
|---|---|
| Filelist | `-f $HEXK_SV_LIB_HOME/src/uvm/hexk_uvm.f` (includes the core filelist) |
| FuseSoC | `hexkdotcom:hexk:uvm` |

UVM itself comes from the tool flow and is compiled before the filelist.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
No example file yet.
<!-- HEXK_GEN:END example -->

```systemverilog
`include "hexk_macros.svh"

package my_env_pkg;
   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import hexk_uvm_pkg::*;
endpackage : my_env_pkg
```

## 8. Anti-patterns

- **Compiling it before UVM.** The package imports `uvm_pkg`; put the UVM switch or UVM
  sources of your tool ahead of the filelist.
- **Forgetting `hexk_macros.svh`.** Importing the package does not bring the macros; include
  the header in every file that uses one.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
