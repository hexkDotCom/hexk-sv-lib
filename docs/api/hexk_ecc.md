# hexk_ecc

## 1. Summary

Extended Hamming code (SECDED: single error correction, double error detection) for data
words of 4 to 128 bits: encode, decode with syndrome and corrected data, and error injection.

## 2. When to use / when not to use

Use it in drivers, monitors, scoreboards and reference models when the DUT protects words
with an extended Hamming code: to compute the check bits of data that is loaded through a
back door, to predict the syndrome and the corrected data the DUT must report, and to make
code words with one or two flipped bits for error tests.

Do not use it to predict the check bits of a DUT that uses another SECDED code. Hsiao
codes, codes with their own column order, and codes with inverted check bits (odd parity)
have the same widths but other check bits; compare section 4 with the specification of the
DUT first. For inverted check bits, XOR the result of `check_bits` with the mask of the
inverted bits. Do not use it for codes that correct more than one bit (BCH, Reed-Solomon)
or for data wider than 128 bits. It is not synthesizable.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_ecc.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_ecc.sv`:

```systemverilog
// Creates the code for data words of data_width bits (4 to 128) in the given layout.
function new(int unsigned data_width, layout_e layout = HEXK_ECC_INTERLEAVED);
// Number of data bits.
function int unsigned get_data_width();
// Number of check bits, the overall parity bit included.
function int unsigned get_check_width();
// Number of bits of a code word: data width plus check width.
function int unsigned get_code_width();
// Layout given to new().
function layout_e get_layout();
// Returns the code word of data; every bit of it is X when a data bit is X or Z.
function hexk_bits_t encode(hexk_bits_t data);
// Returns only the check bits of data: bit 0 is check bit 0, the top bit is the overall parity. Every check bit is X when a data bit is X or Z.
function hexk_bits_t check_bits(hexk_bits_t data);
// Checks code: returns what was found, the data (corrected when possible) and the syndrome. A code word with an X or Z bit is uncorrectable: nothing can be said about it. Its data is all X, its syndrome 0.
function status_e decode(hexk_bits_t code, output hexk_bits_t data, output int unsigned syndrome);
// Index of the code word bit that a syndrome points at, or -1 when it points at no single bit.
function int error_index(int unsigned syndrome);
// Returns code with the bit at index flipped.
function hexk_bits_t flip(hexk_bits_t code, int unsigned index);
// Returns code with num_errors different, randomly chosen bits flipped.
function hexk_bits_t inject(hexk_bits_t code, int unsigned num_errors = 1);
```
<!-- HEXK_GEN:END api -->

The layout is `hexk_ecc::HEXK_ECC_INTERLEAVED` (default) or `hexk_ecc::HEXK_ECC_APPENDED`, of
type `hexk_ecc::layout_e` (`enum bit`). `decode` returns `hexk_ecc::HEXK_ECC_NO_ERROR`,
`hexk_ecc::HEXK_ECC_CORRECTED` or `hexk_ecc::HEXK_ECC_UNCORRECTABLE`, of type
`hexk_ecc::status_e` (`enum bit [1:0]`). Both enums have the width of their values, so a
variable of the type that is only printed by name lints clean with Verilator `-Wall`. Class constants: `hexk_ecc::MIN_DATA_WIDTH` (4),
`hexk_ecc::MAX_DATA_WIDTH` (128) and `hexk_ecc::VECTOR_WIDTH` (the value of `HEXK_MAX_WIDTH`).

Widths for common data widths (`r` Hamming check bits plus one overall parity bit):

| data bits | check bits (`r` + 1) | code word bits |
|---|---|---|
| 4 | 4 | 8 |
| 8 | 5 | 13 |
| 16 | 6 | 22 |
| 32 | 7 | 39 |
| 64 | 8 | 72 |
| 128 | 9 | 137 |

`r` is the smallest number with 2^r >= data bits + r + 1.

## 4. Behaviour and invariants

**The code.** The bits of a code word have positions 0 to `n` - 1, with `n` = code width.

- Position 0 holds the overall parity bit `P`.
- Positions 1, 2, 4, 8, ... (the powers of two) hold the check bits `C0`, `C1`, `C2`, ...
- The other positions, 3, 5, 6, 7, 9, ..., hold the data bits in ascending order: data bit 0
  at position 3, data bit 1 at position 5, data bit 2 at position 6, and so on.
- Check bit `Ci` is the XOR of the data bits at all positions whose number has bit `i` set.
- `P` is the XOR of all other bits of the code word.

All parities are even: every check equation and the whole code word have an even number of
ones, and data 0 gives the code word 0.

**Layouts.** Both layouts hold the same bits in a different order.

| Layout | Bit order of the code word |
|---|---|
| `HEXK_ECC_INTERLEAVED` | bit index = position: bit 0 is `P`, bits 1, 2, 4, 8, ... are check bits, data bits in between |
| `HEXK_ECC_APPENDED` | `{P, C[r-1:0], data}`: the data unchanged in bits `k`-1 to 0 (`k` = data width), check bit `Ci` in bit `k` + `i`, `P` in the top bit |

`check_bits` returns `{P, C[r-1:0]}` in both layouts. In the appended layout it is the upper
part of the code word: `encode(data)` equals `{check_bits(data), data}`.

Example, data width 8, data `'hA5`: the check bits are `C` = `4'b0011` and `P` = 0. The code
word is `13'h144E` interleaved and `13'h03A5` appended.

Example, data width 4, data `4'b1101`: the interleaved code word is `8'b1100_1100`. Bits 7
to 1 are the code word of the textbook Hamming(7,4) code, bit 0 is the added parity bit.

**encode, check_bits.** Use bits `k`-1 to 0 of `data`. Higher bits are ignored without a
report, also when they are X or Z. When one of the bits that are used is X or Z, the check
bits cannot be known: `encode` then returns X in all `n` bits of the code word and
`check_bits` in all `r` + 1 check bits.

**decode.** Uses bits `n`-1 to 0 of `code`; higher bits are ignored, also when they are X or
Z. When one of the bits that are used is X or Z, nothing can be said about the code word:
`decode` returns `HEXK_ECC_UNCORRECTABLE`, X in all `k` bits of `data` and syndrome 0. A
model that took such a bit as 0 could call a word error-free that the design never drove.

`syndrome` has `r` + 1 bits. Bits `r`-1 to 0 are the Hamming syndrome `S`: the XOR of the
positions of all bits that are 1, which is also the received check bits XOR the check bits
recomputed from the received data. Bit `r` is `Q`, the parity of the whole received word.
A code word without errors has syndrome 0.

| `Q` | `S` | Return value | `data` |
|---|---|---|---|
| 0 | 0 | `HEXK_ECC_NO_ERROR` | the data bits of `code` |
| 1 | 0 | `HEXK_ECC_CORRECTED` | the data bits of `code` (the flipped bit is `P`) |
| 1 | a position below `n` | `HEXK_ECC_CORRECTED` | the data bits of `code` with the bit at position `S` flipped back (no change when `S` is the position of a check bit) |
| 1 | `n` or above | `HEXK_ECC_UNCORRECTABLE` | the data bits of `code`, unchanged |
| 0 | not 0 | `HEXK_ECC_UNCORRECTABLE` | the data bits of `code`, unchanged |

One flipped bit is always corrected, two flipped bits are always reported as uncorrectable.
Three or more flipped bits are beyond the code: the result can be any of the three values,
and `HEXK_ECC_CORRECTED` then comes with wrong data.

**error_index.** Translates a syndrome into the index of the flipped bit in the layout of the
object: for a syndrome with `Q` set and `S` below `n`, the index of the bit at position `S`
(in the interleaved layout that is `S` itself). It returns -1 for every other syndrome,
syndrome 0 included.

**flip, inject.** `flip` inverts one bit of `code`. `inject` inverts `num_errors` different
bits among bits `n`-1 to 0, chosen with `$urandom_range`; `code ^ inject(code, 2)` shows
which. An X or Z bit that is flipped becomes 1. Other bits are returned as they are.

**Illegal arguments** are reported with `$error`:

| Call | Reported when | What happens |
|---|---|---|
| `new` | `data_width` below 4 or above 128 | the nearest legal width is used |
| `new` | the code word does not fit `HEXK_MAX_WIDTH` bits | the largest data width that fits is used |
| `flip` | `index` is `n` or above | returns `code` unchanged |
| `inject` | `num_errors` above `n` | all `n` bits are flipped |

## 5. Configuration

| Compile-time switch | Effect |
|---|---|
| `+define+HEXK_MAX_WIDTH=<n>` | width of `hexk_bits_t`, the type of data and code words; default 1024. It must be at least the code width (137 for 128 data bits). |

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`$error` text starts with `hexk_ecc::<function>:`. It has no UVM message ID because the core
layer does not use UVM. On Verilator a `$error` stops the simulation unless
`+verilator+error+limit+<n>` raises the limit.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_ecc/hexk_ecc_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ecc_example.sv
//
// Minimal use of hexk_ecc: the code word of a 32-bit memory word with the check bits above
// the data, then the same word read back with one flipped bit (corrected, and the syndrome
// tells which bit) and with two flipped bits (reported, not corrected).
// Needs only src/core/hexk_core.f.

module hexk_ecc_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_ecc;
   import hexk_core_pkg::hexk_bits_t;

   localparam int unsigned DATA_WIDTH  = 32;
   localparam int unsigned CODE_WIDTH  = 39;
   localparam int unsigned FLIPPED_BIT = 5;

   hexk_ecc                            ecc;
   logic              [DATA_WIDTH-1:0] word;
   logic              [CODE_WIDTH-1:0] stored;
   hexk_bits_t                         damaged;
   hexk_bits_t                         read_data;
   int unsigned                        syndrome;
   hexk_ecc::status_e                  status;

   initial begin
      ecc    = new(DATA_WIDTH, hexk_ecc::HEXK_ECC_APPENDED);
      word   = 32'hDEAD_BEEF;
      stored = CODE_WIDTH'(ecc.encode(hexk_bits_t'(word)));
      $info("%0d data bits and %0d check bits: 0x%0h is stored as 0x%0h", ecc.get_data_width(), ecc.get_check_width(),
            word, stored);

      // One flipped bit: decode corrects the data, and the syndrome points at the bit.
      damaged = ecc.flip(hexk_bits_t'(stored), FLIPPED_BIT);
      status  = ecc.decode(damaged, read_data, syndrome);
      $info("bit %0d flipped: %s, data 0x%0h, syndrome 0x%0h points at bit %0d", FLIPPED_BIT, status.name(), read_data,
            syndrome, ecc.error_index(syndrome));

      // Two flipped bits, chosen at random: decode reports them and leaves the data as read.
      damaged = ecc.inject(hexk_bits_t'(stored), 2);
      status  = ecc.decode(damaged, read_data, syndrome);
      if (status == hexk_ecc::HEXK_ECC_UNCORRECTABLE) begin
         $info("two bits flipped: not corrected, data as read 0x%0h, syndrome 0x%0h", read_data, syndrome);
      end
   end

endmodule : hexk_ecc_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Assuming the DUT uses this code because the widths match.** A (72,64) or (39,32) SECDED
  code can be Hamming or Hsiao, with any column order and either parity. Compare one code
  word of the DUT with `encode` before building a scoreboard on it.
- **Mixing the layouts.** An object decodes only the layout it was created with. A code word
  of the other layout decodes to nonsense, usually as uncorrectable.
- **Reading the syndrome as a bit index in the appended layout.** The low bits of the
  syndrome are a position, which is the bit index only in the interleaved layout. Use
  `error_index(syndrome)`.
- **Trusting `HEXK_ECC_CORRECTED` after injecting three or more errors.** The code cannot
  tell three flipped bits from one; the data is then wrong. Inject one or two.
- **Passing a narrow vector straight to `encode` or `decode`.** Verilator reports
  `WIDTHEXPAND` for arguments narrower than `HEXK_MAX_WIDTH`. Write the extension as a cast:
  `ecc.encode(hexk_bits_t'(word))`, with `hexk_bits_t` from `hexk_core_pkg`, and cut the
  result with a size cast, `39'(ecc.encode(...))`.
- **Calling a function in the argument list of `new` on Verilator.** Verilator 5.046 passes 0
  for an argument of `new()` that is a call of a function of a module, so
  `new(32, pick_layout())` gives the interleaved layout. Put the value in a variable first.
- **Expecting `inject` to repeat without a fixed seed.** It draws from `$urandom_range`, so
  it follows the seed of the calling thread. For bits of your own choice use `flip`.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
