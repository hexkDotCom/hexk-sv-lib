# hexk_plusarg

## 1. Summary

Command-line plusargs as static functions with a default value: presence test, integer,
string, bit, real and list.

## 2. When to use / when not to use

Use it to read run-time options in code that has no UVM: testbench top modules, interfaces,
BFMs, Verilator testbenches, and inside the library itself. It replaces the usual
`if ($value$plusargs(...))` blocks with one call per option, with a default, exact name
matching and checked number formats.

In a UVM testbench, test-wide switches belong in `hexk_knobs`, which builds on this
class and adds registration, a help table and reporting through UVM. Do not use plusargs for
per-component configuration; that belongs in configuration objects (guide rules CFG-1 to
CFG-10).

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_plusarg.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_plusarg.sv`:

```systemverilog
// True when +name or +name=<value> is on the command line.
static function bit has(string name);
// Reads +name=<integer> and reports nothing: VALID with the value, NOT_GIVEN, or INVALID for +name or a value that is not an integer; value is 0 unless VALID.
static function status_e try_get_int(string name, output longint value);
// Reads +name (1) or +name=<0, 1, true, false, yes, no, on, off or integer> and reports nothing; value is 0 unless VALID.
static function status_e try_get_bit(string name, output bit value);
// Reads +name=<real number> and reports nothing; value is 0.0 unless VALID.
static function status_e try_get_real(string name, output real value);
// Value of +name=<integer>; default_value when the plusarg is absent, or, with $error, is not an integer.
static function longint get_int(string name, longint default_value);
// Value of +name=<text>; default_value when the plusarg is absent or has no value.
static function string get_str(string name, string default_value);
// 1 for +name, the value for +name=<0, 1, true, false, yes, no, on, off or integer>; else default_value, with $error for a value that is none of these.
static function bit get_bit(string name, bit default_value);
// Value of +name=<real number>; default_value when the plusarg is absent, or, with $error, is not a number.
static function real get_real(string name, real default_value);
// Fills values (cleared first) with the sep-separated fields of +name=<a,b,c>; empty when there is no value.
static function void get_list(string name, ref string values[$], input byte sep = ",");
```
<!-- HEXK_GEN:END api -->

`name` is the plusarg without its plus sign: `hexk_plusarg::get_int("depth", 16)` reads
`+depth=<n>`.

## 4. Behaviour and invariants

- Names match exactly. `+depth_max=8` is not `+depth`; `has("dep")` is false for `+depth`.
- A plusarg has one of three forms: absent, bare (`+name`) or with a value (`+name=<text>`).
  `+name=` is the value form with an empty value.
- The functions read the command line on every call and keep no state.

What each function returns:

| Function | absent | `+name` | `+name=<text>` |
|---|---|---|---|
| `has` | 0 | 1 | 1 |
| `get_int` | default | default, with `$error` | the integer; default with `$error` if not an integer |
| `get_str` | default | default | the text, which may be empty |
| `get_bit` | default | 1 | see below; default with `$error` if not a bit value |
| `get_real` | default | default, with `$error` | the number; default with `$error` if not a number |
| `get_list` | empty | empty | the fields; empty for an empty value |

`try_get_int`, `try_get_bit` and `try_get_real` read the same values as `get_int`, `get_bit`
and `get_real` but report nothing. They return a `hexk_plusarg::status_e`:
`HEXK_PLUSARG_NOT_GIVEN` for an absent plusarg, `HEXK_PLUSARG_VALID` with the value in their
output argument, or `HEXK_PLUSARG_INVALID` where the `get` function would report a `$error`;
the output is 0 unless the status is `HEXK_PLUSARG_VALID`. They are for callers that report
through UVM, such as `hexk_knobs`, or that decide themselves what a wrong value means.

Number and bit formats:

- Integers: decimal (`42`, `-17`), `0x` hexadecimal, `0b` binary, and Verilog literals with
  base `'h`, `'d`, `'o` or `'b` and an optional size that is ignored (`'hFF`, `8'd200`).
  Letters are case-insensitive, underscores are ignored, and a sign may come first. A plain
  decimal number is a number and must fit `longint`: -9223372036854775808 to
  9223372036854775807; `9223372036854775808` is malformed, not a negative number. The other
  forms, `'d` included, are bit patterns of up to 64 bits: `0xFFFF_FFFF_FFFF_FFFF` is
  accepted and reads as -1.
- `get_bit`: any integer (0 is false, everything else true) or one of `true`, `yes`, `on`,
  `false`, `no`, `off`, case-insensitive.
- Reals: digits with an optional sign, fraction and exponent (`2.5`, `-17`, `1e-3`).
- `get_list` keeps empty fields: `+name=a,,b` gives three fields.

Limit of the language: `$value$plusargs` reports only the first plusarg that starts with a
given text. The bare form `+name` is therefore not seen when a longer plusarg starting with
the same text (`+name_more`) comes before it on the command line. The value form
`+name=<text>` is always found.

## 5. Configuration

None. The class reads whatever plusargs the caller names; it defines none of its own.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`$error` text for a malformed value starts with `hexk_plusarg::<function>:` and names the
plusarg, the text found and the default that is used. It has no UVM message ID because the
core layer does not use UVM. On Verilator a `$error` stops the simulation unless
`+verilator+error+limit+<n>` raises the limit.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_plusarg/hexk_plusarg_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_plusarg_example.sv
//
// Minimal use of hexk_plusarg: read an integer, a string, a flag and a list from the
// command line, each with a default. Run it with, for example,
// +fifo_depth=0x40 +mode=fast +waves +tests=smoke,reset. Needs only src/core/hexk_core.f.

module hexk_plusarg_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_plusarg;

   localparam longint DEFAULT_DEPTH = 16;

   longint depth;
   string  mode;
   bit     waves;
   string  tests [$];

   initial begin
      depth = hexk_plusarg::get_int("fifo_depth", DEFAULT_DEPTH);
      mode  = hexk_plusarg::get_str("mode", "normal");
      waves = hexk_plusarg::get_bit("waves", 0);
      hexk_plusarg::get_list("tests", tests);
      $info("depth %0d, mode %s, waves %0b, %0d tests selected", depth, mode, waves, tests.size());
   end

endmodule : hexk_plusarg_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Including the plus sign or the equals sign in the name.** `get_int("+depth=", 16)` looks
  for `++depth==`. Pass `"depth"`.
- **`$test$plusargs("depth")` for a flag.** It is also true for `+depth_max=8`, because the
  system function matches prefixes. `hexk_plusarg::has("depth")` matches the whole name.
- **Relying on the bare form after a longer plusarg.** `+cov_dir=out +cov` may not see
  `+cov`. Write `+cov=1`, or put the short flag first.
- **Verilog literals on a shell command line without quoting.** The shell removes the quote
  of `+mask='hFF`. Quote the argument (`"+mask='hFF"`) or use `+mask=0xFF`.
- **Calling a getter in a loop or per transaction.** Every call scans the command line. Read
  the value once into a variable or a configuration object.
- **Using the default as an error indicator.** A malformed value is reported with `$error`
  and the default is returned; do not also test for the default.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
