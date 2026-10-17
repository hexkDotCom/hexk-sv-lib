# hexk_mem_model

## 1. Summary

A sparse memory for reference models and scoreboards: words are written and read at byte
addresses, with byte enables, and only the bytes that were written take space.

## 2. When to use / when not to use

Use it as the model of a RAM, a ROM, a flash or the memory behind a bus in a scoreboard or
a predictor: what the DUT is expected to hold, to compare with what it returns. Use it where
unaligned accesses, partial writes and byte accesses must all see the same content, and where
a read of something that was never written should be noticed. One model has one word width
(`DATA_WIDTH`); an access of another width goes through the byte functions.

Do not use it as the memory of the DUT; it is a class and has no ports. Do not use it for
registers with fields and access policies; that is what `uvm_reg` is for. Do not use it where
the content is small and dense and a plain array says the same.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/mem/hexk_mem_model.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/mem/hexk_mem_model.sv`:

```systemverilog
// What a read of a byte that was never written does.
typedef enum bit [2:0] { HEXK_MEM_UNINIT_ERROR, HEXK_MEM_UNINIT_RANDOM, HEXK_MEM_UNINIT_ZERO, HEXK_MEM_UNINIT_PATTERN, HEXK_MEM_UNINIT_X } hexk_mem_uninit_e;
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates an empty memory; the seed of the random policy is derived from the name.
function new(string name = "hexk_mem_model");
// UVM hook of copy() and clone(): a snapshot of the bytes, the settings, the range and the counter of reads of bytes that were never written; afterwards the two memories are independent.
function void do_copy(uvm_object rhs);
// Limits the legal addresses to lo..hi; an access outside is an error and is not carried out.
function void set_range(addr_t lo, addr_t hi);
// Writes the bytes of a word whose byte enable is set; addr is the address of the first byte of the word.
function void write(addr_t addr, data_t data, strobe_t byte_en = '1);
// Reads a word; bytes that were never written follow uninit_policy.
function data_t read(addr_t addr);
// Writes one byte.
function void write_byte(addr_t byte_addr, logic [7:0] data);
// Reads one byte; a byte that was never written follows uninit_policy.
function logic [7:0] read_byte(addr_t byte_addr);
// 1 when every byte of the word at addr was written; 0 for a word that does not fit below the top address.
function bit is_written(addr_t addr);
// Number of bytes that were written.
function int unsigned num_written();
// Number of reads so far that touched a byte that was never written.
function int unsigned num_uninit_reads();
// Forgets every written byte and the count of uninitialised reads.
function void clear();
// Loads a file in the format of $readmemh with words of DATA_WIDTH bits; word n goes to base + n * WORD_BYTES.
function void load_hex(string file, addr_t base = 0);
// Writes the written words to a file in the format of $readmemh; a byte that was never written, and a byte of the last word that would be beyond the top address, is "xx".
function void dump_hex(string file);
// What the memory holds, on one line.
function string convert2string();
// hexk_checkable: reports what the memory holds at the end of the test; a derived class adds its checks.
virtual function void eot_check();
```
<!-- HEXK_GEN:END api -->

The types `addr_t`, `data_t` and `strobe_t` are `logic [ADDR_WIDTH-1:0]`,
`logic [DATA_WIDTH-1:0]` and `logic [DATA_WIDTH/8-1:0]`: four-state, so that an address or a
byte enable with an X or Z bit, as a monitor may see it, is noticed instead of becoming 0.

## 4. Behaviour and invariants

- An address is the address of a byte. A word is `DATA_WIDTH` bits, which must be a multiple
  of 8; `write(addr, ...)` and `read(addr)` take the address of the first byte of the word,
  aligned or not. The storage is one byte per address, so words, bytes and words at other
  alignments see the same content.
- `byte_en[n]` enables bits `8*n+7..8*n` of the data; the default writes all bytes.
- With `big_endian` 0 the least significant byte of a word has the lowest address, with 1 the
  most significant. The setting is read at every access.
- The data is four-state: an X or Z bit that is written is read back, by `read()` and by
  `read_byte()` alike. A byte that was never written reads as X through both under the
  policies that return X. A caller that assigns the result of `read_byte()` to a two-state
  variable gets 0 for such a bit, as in every assignment.
- A read that touches a byte that was never written follows `uninit_policy` for that byte and
  counts once in `num_uninit_reads()`, whatever the policy:

  | Policy | The byte reads as | Message |
  |---|---|---|
  | `HEXK_MEM_UNINIT_ERROR` (default) | X | error `HEXK_MEM_UNINIT`, one per read |
  | `HEXK_MEM_UNINIT_RANDOM` | a value that depends on `seed` and the address only | none |
  | `HEXK_MEM_UNINIT_ZERO` | 0 | none |
  | `HEXK_MEM_UNINIT_PATTERN` | `uninit_pattern` | none |
  | `HEXK_MEM_UNINIT_X` | X | none |

  A read does not store anything: the byte stays unwritten.
- An address with an X or Z bit, given to any function, and a byte enable of `write` with one,
  are the error `HEXK_MEM_UNKNOWN`: the access is not carried out, a read returns X, and
  `is_written` returns 0. Verilator has no X or Z, so there an address is always known.
- `is_written(addr)` is 1 when every byte of the word at `addr` was written. It is a query,
  not an access: the range of `set_range()` does not apply to it.
  `num_written()` counts bytes, not words.
- `set_range(lo, hi)` makes every access that is not completely within `lo..hi` the error
  `HEXK_MEM_RANGE`; such a write changes nothing and such a read returns X. Without a range
  every address is legal.
- A word never goes on at address 0: a `write` or a `read` whose last byte would be beyond
  the top address of `ADDR_WIDTH` bits is the error `HEXK_MEM_RANGE` too, with or without a
  range, and is not carried out. `is_written` is 0 for such a word.
- `load_hex(file, base)` reads the format of `$readmemh` with words of `DATA_WIDTH` bits:
  hexadecimal words separated by white space, `_` inside a word, `x` and `z` digits, `//` and
  `/* */` comments, and `@<hex>` to set the index of the next word. Lines may end with LF or
  with CR LF. Word `n` is written to `base + n * DATA_WIDTH/8` with `write()`, so
  `big_endian` and the range apply. A word with fewer digits is extended with zeros, or with
  X or Z when that is its first digit, as `$readmemh` does: `x` is a word of x digits, `xa`
  ends in `a`, `1x` is `0000001x`. A byte whose two digits are both x (`xx`, as `dump_hex`
  writes a byte that was never written) is not written: it keeps what it held. Z digits are
  written. A block comment ends a word like white space: `11/*gap*/22` is two words. A
  token that is not such a word, or that has too many digits, is the error `HEXK_MEM_FILE`
  with file and line; its place stays unwritten and the rest of the file is loaded.
- A word of a file whose first byte is below the top address and whose last byte would be
  beyond it (a word size that is not a power of two does not divide the address space) is
  written byte by byte up to the top address. Its bytes beyond the top must be `xx`; a real byte there is the
  error `HEXK_MEM_FILE` and is not loaded, the bytes below the top are.
- A word of a file whose first byte would be beyond the address space of `ADDR_WIDTH` bits
  is not loaded and never wraps to a low address, with or without a range. It is the error
  `HEXK_MEM_FILE`, reported for the first such word after the start of the file or after an
  `@<hex>`. An `@<hex>` that does not fit `ADDR_WIDTH` bits is not an address.
- `dump_hex(file)` writes every word that has a written byte, in rising order of address,
  with words aligned to `DATA_WIDTH/8` from address 0, and an `@<word index>` line where the
  index jumps. A byte that was never written is `xx`, and so is a byte of the last word that
  would be beyond the top address; no byte wraps to a low address. `load_hex()` of such a file
  with base 0 gives the same memory: the same bytes written, with the same values. The
  exceptions are unknown bits: a written byte that is all X is dumped as `xx` too and loads
  back as not written, and a hexadecimal digit with some but not all of its four bits X or Z
  is dumped as `X` or `Z`, as `%h` writes it, and loads back with all four bits X or Z.
- `clear()` forgets the content and the count of uninitialised reads; the range and the
  settings stay.
- `copy()` and `clone()` take a snapshot: the bytes, `big_endian`, `uninit_policy`,
  `uninit_pattern`, `seed`, the range and the count of uninitialised reads. The two memories
  are independent afterwards. A copy from an object of another class is the fatal
  `HEXK_COPY_TYPE` and changes nothing.
- `get_type_name()` is `hexk_mem_model`, without the parameters.
- `eot_check()` prints `convert2string()` as the info `HEXK_MEM_SUMMARY`. It is there so that
  a memory can be registered with `hexk_eot_registry`; a derived class adds checks, for
  example that no read touched an unwritten byte.
- `DATA_WIDTH` that is not a multiple of 8, and an address space of `ADDR_WIDTH` bits that
  cannot hold one word (`2**ADDR_WIDTH` below `DATA_WIDTH/8` bytes), are the error
  `HEXK_MEM_WIDTH` when the object is created. Such a memory refuses every access: a write
  changes nothing, a read returns X, `is_written` is 0. Address spans are computed in a type
  wider than an address, so a word that ends exactly at the top address is legal.

## 5. Configuration

| Member | Default | Meaning |
|---|---|---|
| `uninit_policy` | `HEXK_MEM_UNINIT_ERROR` | What a read of a byte that was never written does. |
| `uninit_pattern` | `8'hA5` | The byte of policy `HEXK_MEM_UNINIT_PATTERN`. |
| `big_endian` | 0 | 1: the most significant byte of a word has the lowest address. |
| `seed` | from the name of the object and the seed of the simulation | Seed of policy `HEXK_MEM_UNINIT_RANDOM`. |

| Parameter | Default | Meaning |
|---|---|---|
| `ADDR_WIDTH` | 64 | Width of a byte address. |
| `DATA_WIDTH` | 32 | Width of a word, a multiple of 8. |

There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | fatal |  |
| `HEXK_MEM_FILE` | error |  |
| `HEXK_MEM_RANGE` | error |  |
| `HEXK_MEM_SUMMARY` | info |  |
| `HEXK_MEM_UNINIT` | error |  |
| `HEXK_MEM_UNKNOWN` | error |  |
| `HEXK_MEM_WIDTH` | error |  |
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_mem_model/hexk_mem_model_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_mem_model_example.sv
//
// Minimal use of hexk_mem_model: the reference model of a RAM with 32-bit words and byte
// enables behind a bus with 16-bit addresses. The example writes a word, changes two of its
// bytes with a byte enable, reads the word and one of its bytes, reads a word that was never
// written, which is an error under the default policy, and copies the memory into a second
// one through a file in the format of $readmemh.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_mem_model_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_mem_model;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_ZERO;
   `include "uvm_macros.svh"

   typedef hexk_mem_model#(
       .ADDR_WIDTH(16),
       .DATA_WIDTH(32)
   ) hexk_example_ram_t;

   localparam string IMAGE_FILE = "hexk_mem_model_example.hex";

   hexk_example_ram_t ram;
   hexk_example_ram_t copy;

   // Prints the word at an address of a memory.
   function automatic void show(hexk_example_ram_t mem, bit [15:0] addr);
      `uvm_info("EXAMPLE", $sformatf("%s[0x%04h] = 0x%08h", mem.get_name(), addr, mem.read(addr)), UVM_NONE)
   endfunction : show

   initial begin
      ram = hexk_example_ram_t::type_id::create("ram");
      ram.set_range(16'h1000, 16'h1FFF);

      // A full word, then a write of the two middle bytes only.
      ram.write(16'h1000, 32'h1122_3344);
      ram.write(16'h1000, 32'hFFAA_BBFF, 4'b0110);
      show(ram, 16'h1000);
      // The memory is little endian by default: the byte at the address of the word is its lowest byte.
      `uvm_info("EXAMPLE", $sformatf("byte at 0x1001 = 0x%02h", ram.read_byte(16'h1001)), UVM_NONE)

      // A word that was never written: an error by default, zero under another policy.
      show(ram, 16'h1010);
      ram.uninit_policy = HEXK_MEM_UNINIT_ZERO;
      show(ram, 16'h1010);

      // An access outside the range is an error and is not carried out.
      ram.write(16'h2000, 32'h0000_0001);

      // The content goes to a file and from there into a second memory.
      ram.dump_hex(IMAGE_FILE);
      copy = hexk_example_ram_t::type_id::create("copy");
      copy.load_hex(IMAGE_FILE);
      show(copy, 16'h1000);

      // What a memory reports at the end of a test when it is registered with hexk_eot_registry.
      ram.eot_check();
   end

endmodule : hexk_mem_model_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Word addresses.** `write(3, data)` writes the bytes 3 to 6 of a 32-bit memory, not word
  3. Multiply a word index by the number of bytes of a word.
- **A policy other than the default to silence errors.** A read of something that was never
  written is usually a bug in the test or the DUT. Choose zero, pattern or random where the
  real memory has such content after power-up, and say so next to the setting.
- **Changing `big_endian` between a write and a read.** The bytes stay where they are and the
  word reads back swapped. Set it once after the object is created.
- **One memory object for two address spaces.** Two regions that the DUT decodes separately
  are two objects, each with its own range.
- **`dump_hex()` of an unaligned image, then `$readmemh` with another word size.** The file
  holds words of `DATA_WIDTH` bits at word indexes; a reader with another word size sees
  other addresses.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. On Verilator, which has
two-state variables, the two tests with X digits are left out of the build.
