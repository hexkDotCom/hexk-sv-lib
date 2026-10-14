# hexk_lfsr

## 1. Summary

Linear feedback shift register of 1 to 64 bits, Galois or Fibonacci form.

## 2. When to use / when not to use

Use it when a testbench must produce or predict the exact sequence of a hardware LFSR
(scramblers, PRBS generators and checkers, BIST patterns), or needs cheap reproducible
pseudo-random data that does not depend on the simulator's random number generator.

Do not use it as a general random source for stimulus: use `rand` variables and constraints,
or `hexk_rand_stream`. Do not use it where statistical quality matters; consecutive states of
an LFSR are strongly correlated.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_lfsr.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_lfsr.sv`:

```systemverilog
// Creates a register of width bits (1 to 64) with the given taps, start state and form.
function new(int unsigned width, longint unsigned taps, longint unsigned seed = 1, kind_e kind = HEXK_LFSR_GALOIS);
// Creates a maximal-length register (period 2**width - 1) of 2 to 64 bits from the built-in tap table.
static function hexk_lfsr maximal(int unsigned width, longint unsigned seed = 1);
// Advances the register by one step and returns the new state.
function longint unsigned next();
// Returns the current state.
function longint unsigned get_state();
// Sets the state; bits above the width are ignored, and 0 is rejected because the register would stay 0.
function void set_state(longint unsigned state);
// Number of steps until the current state repeats, by brute force; for tests, width up to 24 only. With taps that new() reported, the state may never repeat: that is an $error and gives 0.
function longint unsigned period();
```
<!-- HEXK_GEN:END api -->

The form is `hexk_lfsr::HEXK_LFSR_GALOIS` (default) or `hexk_lfsr::HEXK_LFSR_FIBONACCI`, of
type `hexk_lfsr::kind_e`.

## 4. Behaviour and invariants

- `taps` is a bit mask of the feedback polynomial without its constant term: bit i stands for
  the term x^(i+1). Bit `width`-1, the top term, is therefore always set.
  Example: x^16 + x^12 + x^3 + x + 1 is `'h8805`.
- One step, Galois form: the state shifts right by one; when the bit shifted out was 1, the
  taps are XORed into the state.
- One step, Fibonacci form: the state shifts left by one; bit 0 becomes the XOR of the bits
  of the old state selected by the taps.
- Both forms have period 2^`width` - 1 when the polynomial is primitive, but they produce
  different sequences for the same taps and seed.
- `next` advances first and returns the new state. The first value returned is therefore not
  the seed.
- The state is never 0. A seed or `set_state` value that is 0 within the width is rejected.
- `maximal` uses a built-in table of primitive polynomials for widths 2 to 64, in Galois
  form. The table was computed for this library (trinomials where one exists, otherwise
  pentanomials) and checked for primitivity; the unit tests confirm the full period for
  widths 2 to 20 by counting.
- Sequences depend only on width, taps, form and seed: they are identical on every simulator
  and in every run.

Illegal arguments are reported with `$error`:

| Call | Reported when | What happens |
|---|---|---|
| `new` | `width` is 0 or above 64 | the width is 64 |
| `new` | bit `width`-1 of `taps` is not set | the register is built as given; it is not maximal |
| `new`, `maximal` | `seed` is 0 within the width | the state is 1 |
| `maximal` | `width` is below 2 or above 64 | the width is 2 or 64 |
| `set_state` | `state` is 0 within the width | the state is not changed |
| `period` | the width is above 24 | returns 0 |
| `period` | the state does not repeat within 2^`width` steps, which taps without bit `width`-1 can cause | returns 0 |

## 5. Configuration

None.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`$error` text starts with `hexk_lfsr::<function>:`. It has no UVM message ID because the core
layer does not use UVM. On Verilator a `$error` stops the simulation unless
`+verilator+error+limit+<n>` raises the limit.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_lfsr/hexk_lfsr_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_lfsr_example.sv
//
// Minimal use of hexk_lfsr: a maximal-length register from the built-in tap table, and a
// register with explicit taps and form that mirrors a hardware LFSR.
// Needs only src/core/hexk_core.f.

module hexk_lfsr_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_lfsr;

   localparam int unsigned PATTERN_WIDTH = 16;
   localparam longint unsigned PATTERN_SEED = 64'hACE1;

   hexk_lfsr pattern;
   hexk_lfsr scrambler;

   initial begin
      pattern = hexk_lfsr::maximal(PATTERN_WIDTH, PATTERN_SEED);
      repeat (3) begin
         $info("pattern word 0x%0h", pattern.next());
      end

      // x^7 + x^6 + 1 as taps: bit 6 for x^7, bit 5 for x^6. Fibonacci form, seed all ones.
      scrambler = new(7, 64'h60, 64'h7F, hexk_lfsr::HEXK_LFSR_FIBONACCI);
      $info("scrambler repeats after %0d steps", scrambler.period());
   end

endmodule : hexk_lfsr_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Expecting `maximal` to match a particular hardware LFSR.** It picks its own polynomial.
  To mirror hardware, pass the taps and form of that hardware to `new`, and compare a few
  states against the RTL.
- **Tap masks in another convention.** Some texts list tap positions, some give the mask
  with the constant term, some number the bits from the other end. Here bit i is x^(i+1).
  A wrong mask usually shows as a short `period()`.
- **Calling `period()` in a test.** It steps through the whole sequence (up to 16 million
  steps) and exists to validate taps, not for use during simulation.
- **Seeding with 0.** The register would stay 0 forever; the seed is replaced by 1 with an
  error. Map a possibly-zero seed yourself, for example `seed | 1`.
- **Taking fewer bits from the state and expecting them to be independent.** Consecutive
  states overlap in all but one bit. Step `width` times for a fresh word if that matters.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
