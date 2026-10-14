# hexk_uvm_compat

## 1. Summary

UVM version detection for the UVM layer of hexk-sv-lib.

## 2. When to use / when not to use

The library uses it internally wherever UVM 1.2 and IEEE 1800.2 differ. Use the two defines in
your own code when one source has to compile against both UVM versions.

Do not use it to support UVM 1.1d or older: those versions are outside the compatibility
targets and neither define is set for them.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_uvm_compat.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_uvm_compat.svh`:

```systemverilog
// Defined when compiling against Accellera UVM 1.2.
`define HEXK_UVM_VERSION_1_2
// Defined when compiling against an IEEE 1800.2 reference implementation (2017 or 2020).
`define HEXK_UVM_VERSION_IEEE
// Default of the argument of uvm_report_server::report_summarize: UVM 1.2 declares 0, the IEEE implementations UVM_STDOUT. An override repeats it, so that a call without an argument means the same through a handle of either class (VCS warns about a different default).
`define HEXK_UVM_SUMMARY_FILE
// Defined when UVM matches globs instead of regular expressions: with UVM_REGEX_NO_DPI, and with UVM_NO_DPI, which stands for it inside UVM. UVM passes neither on to a file that is compiled on its own, so the define that was given to the compilation is looked at here.
`define HEXK_UVM_REGEX_NO_DPI
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- With a supported UVM exactly one of the two defines is set.
- The header includes `uvm_macros.svh` itself, so it works wherever it is included first.
- Detection reads UVM's own version macros: `UVM_VERSION_1_2` selects UVM 1.2; otherwise a
  defined `UVM_VERSION` selects IEEE 1800.2.
- Where the two UVM versions differ in something the library uses, the difference is
  settled here: `HEXK_UVM_SUMMARY_FILE` is the default argument of `report_summarize`, and
  `HEXK_UVM_REGEX_NO_DPI` says that `uvm_re_match` takes globs instead of regular
  expressions.

## 5. Configuration

None. UVM's own compile-time switches (for example `UVM_NO_DPI`) are not changed.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
No example file yet.
<!-- HEXK_GEN:END example -->

```systemverilog
`include "hexk_uvm_compat.svh"

`ifdef HEXK_UVM_VERSION_IEEE
   // code written against the IEEE 1800.2 API
`else
   // code written against the UVM 1.2 API
`endif
```

## 8. Anti-patterns

- **Testing `UVM_VERSION_1_2` or `UVM_VERSION` directly.** The meaning of UVM's macros changes
  between releases. Test `HEXK_UVM_VERSION_1_2` and `HEXK_UVM_VERSION_IEEE`.
- **Assuming one of the defines is always set.** With an unsupported UVM neither is. An
  `` `else `` branch is therefore also taken by an unsupported UVM; test the second define
  explicitly where that matters.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
