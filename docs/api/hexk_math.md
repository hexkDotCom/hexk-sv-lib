# hexk_math

## 1. Summary

Bit and integer helpers as static functions: clamp, powers of two, alignment, range
overlap, population count, parity, bit and byte reversal, sign extension and masks.

## 2. When to use / when not to use

Use it for the small calculations every testbench repeats: aligning addresses and lengths,
sizing counters, checking that address ranges do not collide, parity and population counts
in checkers and coverage, reading a register field as a signed number. It has no UVM
dependency and also works in modules, interfaces and on Verilator.

Do not use it in constraints: the functions are procedural. Do not use the bit-vector helpers
on vectors wider than `HEXK_MAX_WIDTH` (1024 by default). Do not use it in synthesizable code;
it is a class.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_math.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_math.sv`:

```systemverilog
// Returns v limited to the range lo to hi (inclusive).
static function longint clamp(longint v, longint lo, longint hi);
// Returns the unsigned v limited to the range lo to hi (inclusive).
static function longint unsigned clamp_u(longint unsigned v, longint unsigned lo, longint unsigned hi);
// True when v is a power of two; 0 is not.
static function bit is_pow2(longint unsigned v);
// Smallest n with 2**n >= v; 0 for v of 0 or 1.
static function int unsigned log2_ceil(longint unsigned v);
// Largest multiple of align that is not above v; align may be any value except 0.
static function longint unsigned align_down(longint unsigned v, longint unsigned align);
// Smallest multiple of align that is not below v; align may be any value except 0. When that multiple does not fit 64 bits, an $error is issued and v is returned.
static function longint unsigned align_up(longint unsigned v, longint unsigned align);
// True when v is a multiple of align; align may be any value except 0.
static function bit is_aligned(longint unsigned v, longint unsigned align);
// True when the inclusive ranges a_lo..a_hi and b_lo..b_hi share a value; a range with lo > hi is empty.
static function bit ranges_overlap(longint unsigned a_lo, longint unsigned a_hi, longint unsigned b_lo, longint unsigned b_hi);
// Number of bits of v that are 1; X and Z bits are not counted.
static function int unsigned popcount(hexk_bits_t v);
// Parity bit for v: makes the number of ones even, or odd when odd is set; X and Z bits count as 0.
static function bit parity(hexk_bits_t v, bit odd = 0);
// Bits width-1..0 of v in reverse order; the bits above are 0.
static function hexk_bits_t reverse_bits(hexk_bits_t v, int unsigned width);
// The low num_bytes bytes of v in reverse byte order; the bits above are 0.
static function hexk_bits_t swap_bytes(hexk_bits_t v, int unsigned num_bytes);
// Reads bits width-1..0 of v as a two's-complement number; width is 1 to 64.
static function longint sign_extend(longint unsigned v, int unsigned width);
// Vector with the low width bits set.
static function hexk_bits_t mask(int unsigned width);
```
<!-- HEXK_GEN:END api -->

Class constants: `hexk_math::MAX_WIDTH` (the value of `HEXK_MAX_WIDTH`), `hexk_math::INT_WIDTH`
(64) and `hexk_math::BYTE_WIDTH` (8).

## 4. Behaviour and invariants

- Every function is pure: the result depends only on the arguments.
- Integer helpers work on 64-bit values. `clamp` and `sign_extend` are signed, everything else
  is unsigned.
- Bit-vector helpers (`popcount`, `parity`, `reverse_bits`, `swap_bytes`, `mask`) take and
  return `hexk_core_pkg::hexk_bits_t`, a vector of `HEXK_MAX_WIDTH` bits. A narrower argument
  is zero-extended; result bits above the requested width are 0.
- X and Z: `popcount` and `parity` count only bits that are 1. `reverse_bits` and
  `swap_bytes` move X and Z bits like any other bit.
- `align_down`, `align_up` and `is_aligned` accept any non-zero alignment, not only powers of
  two.
- `log2_ceil(0)` and `log2_ceil(1)` are 0, like `$clog2`.
- `ranges_overlap` takes inclusive limits. A range whose `lo` is above its `hi` is empty and
  overlaps nothing; that is not an error.
- `parity` returns the bit to append: with it, the number of ones is even (`odd` = 0) or odd
  (`odd` = 1).

Illegal arguments are reported with `$error`, and the function returns a defined value:

| Call | Reported when | Returns |
|---|---|---|
| `clamp`, `clamp_u` | `lo` > `hi` | `lo` |
| `align_down`, `align_up` | `align` is 0 | `v` |
| `align_up` | the next multiple of `align` does not fit 64 bits | `v` |
| `is_aligned` | `align` is 0 | 0 |
| `sign_extend` | `width` is 0 or above 64 | `v` unchanged |
| `reverse_bits`, `mask` | `width` above `HEXK_MAX_WIDTH` | the result for `HEXK_MAX_WIDTH` |
| `swap_bytes` | `num_bytes` * 8 above `HEXK_MAX_WIDTH` | the result for `HEXK_MAX_WIDTH` / 8 bytes |

On Verilator a `$error` stops the simulation unless `+verilator+error+limit+<n>` raises the
limit.

## 5. Configuration

| Compile-time switch | Effect |
|---|---|
| `+define+HEXK_MAX_WIDTH=<n>` | width of the vectors of the bit-vector helpers; default 1024 |

All files of one simulation must be compiled with the same value.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`$error` text for illegal arguments starts with `hexk_math::<function>:`. It has no UVM
message ID because the core layer does not use UVM.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_math/hexk_math_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_math_example.sv
//
// Minimal use of hexk_math: alignment, counter sizing, population count and parity, sign
// extension of a register field, and an address-range overlap test. Values narrower than
// the bit-vector helpers' argument are cast with hexk_bits_t'(), which every tool accepts.
// Needs only src/core/hexk_core.f.

module hexk_math_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_math;
   import hexk_core_pkg::hexk_bits_t;

   localparam longint unsigned PAGE_SIZE = 4096;
   localparam int unsigned FIELD_WIDTH = 12;

   longint unsigned raw = 64'hA5F;

   initial begin
      $info("0x1234 rounded up to a page: 0x%0h", hexk_math::align_up(64'h1234, PAGE_SIZE));
      $info("a counter for 1000 values needs %0d bits", hexk_math::log2_ceil(1000));
      $info("0x%0h has %0d ones", raw, hexk_math::popcount(hexk_bits_t'(raw)));
      $info("even-parity bit of 0x%0h: %0b", raw, hexk_math::parity(hexk_bits_t'(raw)));
      $info("0x%0h as a signed %0d-bit field: %0d", raw, FIELD_WIDTH, hexk_math::sign_extend(raw, FIELD_WIDTH));
      $info("buffers overlap: %0b", hexk_math::ranges_overlap(64'h1000, 64'h1FFF, 64'h1800, 64'h27FF));
   end

endmodule : hexk_math_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Passing a narrow vector straight to a bit-vector helper.**
  `hexk_math::popcount(my_byte)` is correct SystemVerilog and most tools extend the value
  silently, but Verilator reports a `WIDTHEXPAND` warning for every argument narrower than
  `HEXK_MAX_WIDTH`. Write the extension as a cast, `hexk_math::popcount(hexk_bits_t'(my_byte))`,
  as the example does; `hexk_bits_t` comes from `hexk_core_pkg`. Unsized literals (`'hFF`)
  need no cast.
- **Forgetting the width argument's meaning.** `reverse_bits(v, 8)` reverses bits 7..0 and
  clears everything above; it does not reverse the whole vector.
- **Using `mask` for a 64-bit integer mask.** `mask` returns a `HEXK_MAX_WIDTH`-bit vector.
  Assigning it to a 64-bit variable truncates, with a warning in strict tools. Assign it to
  a full-width variable and take the slice you need.
- **Calling `is_pow2` to validate an alignment for `align_up`.** Not needed: any non-zero
  alignment works.
- **Expecting an exception for illegal arguments.** The functions report with `$error` and
  return the value from the table above; check your arguments if the value matters.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
