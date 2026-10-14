# hexk_core_pkg

## 1. Summary

Pure-SystemVerilog utility package of hexk-sv-lib, with no UVM dependency.

## 2. When to use / when not to use

Use it in any SystemVerilog code, including modules, interfaces and Verilator testbenches,
for string, enum, math, CRC, LFSR, random-stream and plusarg helpers.

Do not expect UVM reporting from it: it cannot know whether UVM is present. Code that wants
UVM messages uses `hexk_uvm_pkg`, which builds on this package.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_core_pkg.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_core_pkg.sv`:

```systemverilog
// Width in bits of the vectors of the width-generic helpers (hexk_math, hexk_crc, hexk_ecc).
`define HEXK_MAX_WIDTH
// Vector of HEXK_MAX_WIDTH bits, the argument type of the width-generic helpers; cast with hexk_bits_t'(x).
typedef logic [`HEXK_MAX_WIDTH-1:0] hexk_bits_t;
```
<!-- HEXK_GEN:END api -->

The package holds one class per module. Each class has its own contract document; `llms.txt`
lists them.

`hexk_bits_t` is the argument type of the width-generic helpers of `hexk_math`, `hexk_crc` and `hexk_ecc`.
Cast a narrower value to it at the call, `hexk_math::popcount(hexk_bits_t'(my_byte))`: every
tool accepts the cast, and strict linters (Verilator) warn without it.

## 4. Behaviour and invariants

- No reference to `uvm_pkg` and no `` `uvm_* `` macro anywhere under `src/core/`; Gate 1
  enforces it.
- Problems are reported through return values and `$error`.
- The package holds no global mutable state.

## 5. Configuration

| Integration | Value |
|---|---|
| Filelist | `-f $HEXK_SV_LIB_HOME/src/core/hexk_core.f` |
| FuseSoC | `hexkdotcom:hexk:core` |
| `+define+HEXK_MAX_WIDTH=<n>` | width in bits of the vectors of the width-generic helpers (`hexk_math`, `hexk_crc`, `hexk_ecc`); default 1024 |

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
No example file yet.
<!-- HEXK_GEN:END example -->

`examples/hexk_version/hexk_version_example.sv` compiles against this filelist alone.

## 8. Anti-patterns

- **Wildcard-importing it into your own package** (`import hexk_core_pkg::*;` inside
  `package my_pkg`). It hides where names come from (guide rule FIL-5). Import the classes you
  use by name.
- **Expecting `hexk_uvm_pkg` to re-export it.** It does not; import both packages where both
  are used.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
