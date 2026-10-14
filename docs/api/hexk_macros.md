# hexk_macros

## 1. Summary

Umbrella header for every macro file of the UVM layer of hexk-sv-lib.

## 2. When to use / when not to use

Include it in every file that uses a library macro (checks, static reports, waits, HDL access,
utility macros). It is the only library header user code includes for macros.

Do not include it in code that must stay free of UVM: it pulls in `uvm_macros.svh`. Core-only
code includes `hexk_version.svh` and `hexk_sim_compat.svh` instead.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_macros.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
No public symbols yet.
<!-- HEXK_GEN:END api -->

The macros themselves are documented with their modules: `hexk_report_macros`,
`hexk_check_macros`, `hexk_wait_macros`, `hexk_rand_once`, `hexk_util_macros`,
`hexk_hdl_macros` and `hexk_coverage`.

## 4. Behaviour and invariants

- Include-guarded: including it more than once in a compilation unit is harmless.
- It includes `hexk_uvm_compat.svh`, which includes `uvm_macros.svh`. No separate include of
  `uvm_macros.svh` is needed after it.
- It only defines macros, so it is included outside the package or module, at the top of the
  file.

## 5. Configuration

None of its own; see the modules whose macros it includes.

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

- **Including a single macro file** such as `hexk_check_macros.svh` from user code. The split
  into files is internal and may change. Include `hexk_macros.svh`.
- **Relying on another file's include.** Tools that compile each file as its own compilation
  unit do not carry macros from one file to the next. Include the header in every file that
  uses a library macro.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
