# hexk_crc

## 1. Summary

Cyclic redundancy check of 1 to 64 bits, described by the usual six parameters: width,
polynomial, initial value, input reflection, output reflection and final XOR.

## 2. When to use / when not to use

Use it to generate or check the CRC of packets, frames and memory images in drivers,
monitors, scoreboards and reference models, for standard CRCs (presets) and for
project-specific ones (six parameters from the specification or a CRC catalogue).

Do not use it as a model of a parallel CRC circuit with a non-byte data width unless you
feed the bits in the order the circuit sees them (`update_bits`). Do not use it for CRCs
wider than 64 bits. It is bit-serial: fine for testbench traffic, not for gigabytes.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_crc.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_crc.sv`:

```systemverilog
// Creates a CRC from its parameters; width is 1 to 64, poly is given without the top term.
function new(int unsigned width, longint unsigned poly, longint unsigned init = 0, bit refin = 0, bit refout = 0, longint unsigned xorout = 0);
// CRC-8 (SMBus): poly 'h07, init 0, not reflected, no final XOR.
static function hexk_crc crc8();
// CRC-16/CCITT-FALSE: poly 'h1021, init 'hFFFF, not reflected, no final XOR.
static function hexk_crc crc16_ccitt();
// CRC-16/ARC (IBM): poly 'h8005, init 0, reflected, no final XOR.
static function hexk_crc crc16_ibm();
// CRC-32 (Ethernet): poly 'h04C11DB7, init and final XOR 'hFFFFFFFF, reflected.
static function hexk_crc crc32();
// CRC-32C (Castagnoli): poly 'h1EDC6F41, init and final XOR 'hFFFFFFFF, reflected.
static function hexk_crc crc32c();
// CRC-64/ECMA-182: poly 'h42F0E1EBA9EA3693, init 0, not reflected, no final XOR.
static function hexk_crc crc64_ecma();
// Starts a new message: the state returns to the initial value.
function void reset();
// Feeds one byte: most significant bit first, or least significant bit first when refin is set.
function void update_byte(byte unsigned data);
// Feeds the bytes of data in order.
function void update_bytes(const ref byte unsigned data[$]);
// Feeds num_bits bits of data in serial order, bit 0 first, whatever refin is.
function void update_bits(hexk_bits_t data, int unsigned num_bits);
// Returns the CRC of the data fed since the last reset; the state is not changed.
function longint unsigned get();
// CRC of data with the given model, from a fresh start; the model keeps the final state.
static function longint unsigned compute(hexk_crc model, const ref byte unsigned data[$]);
```
<!-- HEXK_GEN:END api -->

Presets, with the CRC of the ASCII text `123456789` (the catalogue "check" value):

| Preset | width | poly | init | refin | refout | xorout | check |
|---|---|---|---|---|---|---|---|
| `crc8()` | 8 | `07` | `00` | 0 | 0 | `00` | `f4` |
| `crc16_ccitt()` | 16 | `1021` | `ffff` | 0 | 0 | `0000` | `29b1` |
| `crc16_ibm()` | 16 | `8005` | `0000` | 1 | 1 | `0000` | `bb3d` |
| `crc32()` | 32 | `04c11db7` | `ffffffff` | 1 | 1 | `ffffffff` | `cbf43926` |
| `crc32c()` | 32 | `1edc6f41` | `ffffffff` | 1 | 1 | `ffffffff` | `e3069283` |
| `crc64_ecma()` | 64 | `42f0e1eba9ea3693` | 0 | 0 | 0 | 0 | `6c40df5f0b497347` |

`crc16_ccitt()` is the variant catalogues call CRC-16/CCITT-FALSE (init `ffff`, not
reflected). The reflected variant with init 0 (CRC-16/KERMIT) is
`new(16, 'h1021, 0, 1, 1)`.

## 4. Behaviour and invariants

- An object holds the model parameters and the running state. Each preset call returns a new
  object.
- `poly` is the polynomial without its top term, most significant coefficient in the highest
  bit, as catalogues print it. `init` and `xorout` are in the same, unreflected, notation.
- `update_byte` feeds a byte most significant bit first, or least significant bit first when
  `refin` is set. `update_bytes` feeds the queue from index 0.
- `update_bits` feeds bit 0 of the vector first, then bit 1, and so on: the order of a serial
  line. For a model with `refin` set this equals `update_byte` on the same bytes. For a model
  without `refin` it does not: reverse the bits of each byte, or use `update_byte`. X and Z
  bits count as 0.
- `get` returns the CRC of everything fed since `reset` (or construction), with output
  reflection and final XOR applied. It does not change the state: feeding can continue.
- The CRC of an empty message is `init` (reflected when `refout` is set) XOR `xorout`.
- `compute` resets the model, feeds the data and returns `get()`; the model keeps that state.

Illegal arguments are reported with `$error`:

| Call | Reported when | What happens |
|---|---|---|
| `new` | `width` is 0 or above 64 | the width is 64 |
| `update_bits` | `num_bits` above `HEXK_MAX_WIDTH` | `HEXK_MAX_WIDTH` bits are fed |
| `compute` | `model` is null | returns 0 |

Bits of `poly`, `init` and `xorout` above the width are ignored without a report.

## 5. Configuration

| Compile-time switch | Effect |
|---|---|
| `+define+HEXK_MAX_WIDTH=<n>` | width of the `data` vector of `update_bits`; default 1024 |

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`$error` text starts with `hexk_crc::<function>:`. It has no UVM message ID because the core
layer does not use UVM. On Verilator a `$error` stops the simulation unless
`+verilator+error+limit+<n>` raises the limit.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_crc/hexk_crc_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_crc_example.sv
//
// Minimal use of hexk_crc: the CRC of a complete message with a preset, a running CRC that
// is read while data still arrives, and a custom model from catalogue parameters.
// Needs only src/core/hexk_core.f.

module hexk_crc_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_crc;

   byte unsigned payload   [$];
   hexk_crc      frame_crc;
   hexk_crc      token_crc;

   initial begin
      payload   = '{8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39};

      frame_crc = hexk_crc::crc32();
      $info("CRC-32 of the whole payload: 0x%0h", hexk_crc::compute(frame_crc, payload));

      frame_crc.reset();
      foreach (payload[i]) begin
         frame_crc.update_byte(payload[i]);
      end
      $info("the same, fed byte by byte: 0x%0h", frame_crc.get());

      // CRC-5/USB from its catalogue parameters: width, poly, init, refin, refout, xorout.
      token_crc = new(5, 64'h05, 64'h1F, 1, 1, 64'h1F);
      $info("CRC-5/USB of the payload: 0x%0h", hexk_crc::compute(token_crc, payload));
   end

endmodule : hexk_crc_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Sharing one object between two streams.** The state is in the object. Take one object
  per stream (`hexk_crc::crc32()` returns a new one each time).
- **Forgetting `reset()` between messages** when feeding with the `update_*` functions. Only
  `compute` resets by itself.
- **Passing the polynomial with its top bit** (`'h104C11DB7` for CRC-32) or in reflected
  notation (`'hEDB88320`). Give the catalogue form, `'h04C11DB7`, and set `refin`/`refout`.
- **Using `update_bits` for whole bytes of an unreflected CRC.** The bit order differs from
  `update_byte`; see section 4.
- **Passing a narrow vector straight to `update_bits`.** Verilator reports `WIDTHEXPAND` for
  arguments narrower than `HEXK_MAX_WIDTH`. Write the extension as a cast:
  `crc.update_bits(hexk_bits_t'(word), 32)`, with `hexk_bits_t` from `hexk_core_pkg`.
- **Guessing which "CRC-16" a specification means.** There are many. Take the six parameters
  from the specification and confirm with the check value of `123456789`.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
