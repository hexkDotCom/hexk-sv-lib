# hexk_value_wrapper

## 1. Summary

A packed value inside a `uvm_object`, so that it can travel through analysis ports, FIFOs and
scoreboards, with an optional tolerance for comparing approximate data.

## 2. When to use / when not to use

Use it where the thing to pass or compare is a plain value and not a transaction: samples of
an ADC or DAC, the output words of a filter, a status word, a count. Declaring a class with
one field, a `compare` and a `convert2string` for each such value is what this class saves.
Use the tolerance where a model predicts a value only approximately.

Do not use it for a transaction with several fields; write an item class, so that fields
have names in messages. Do not use it for values that are not packed, such as strings,
reals or dynamic arrays. Do not use the tolerance to hide a model that is wrong by a
constant; fix the model.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/data/hexk_value_wrapper.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/data/hexk_value_wrapper.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates a wrapper; the value is that of an uninitialised T.
function new(string name = "hexk_value_wrapper");
// Creates a wrapper through the factory that holds the given value and tolerance.
static function hexk_value_wrapper#(T) wrap(T wrapped_value, longint unsigned wrapped_tolerance = 0);
// The value in hexadecimal.
function string convert2string();
// UVM hook of compare(): identical bits, or numbers within the tolerance of this object, the expected side when a scoreboard calls expected.compare(actual): a.compare(b) and b.compare(a) differ when the tolerances do. A mismatch is told to the comparer as a difference of the field value.
function bit do_compare(uvm_object rhs, uvm_comparer comparer);
// UVM hook of print() and sprint(): value in hexadecimal and tolerance.
function void do_print(uvm_printer printer);
// UVM hook of copy() and clone(): copies value and tolerance.
function void do_copy(uvm_object rhs);
```
<!-- HEXK_GEN:END api -->

`do_compare`, `do_copy` and `do_print` are the UVM hooks behind `compare()`, `copy()`,
`clone()`, `print()` and `sprint()`.

## 4. Behaviour and invariants

- `T` is a packed type: a vector, an integer type, an enum or a packed struct. The default
  is `logic [63:0]`. A comparison with a tolerance takes values of up to `HEXK_MAX_WIDTH`
  bits (at least 64). For a wider `T` it is the error `HEXK_VALUE_WRAPPER_WIDTH` and the
  two values count as different; without a tolerance any width is compared.
- `wrap(value, tolerance)` creates a wrapper in one call, through the factory, so a type
  override of the wrapper applies to it.
- `a.compare(b)` with `a.tolerance` 0 is true when the bits are identical (`===`): X and Z
  bits must match.
- With `a.tolerance` above 0 it is true when the two values, each taken as the number it
  stands for in `T`, differ by at most the tolerance. A signed `T` can be negative; an
  unsigned value does not wrap around, so 0 and the largest value are far apart. A value
  with an X or Z bit is then different from everything.
- The tolerance that counts is that of the object whose `compare()` is called. In
  `hexk_scoreboard` that is the expected item. The comparison is therefore not symmetric:
  `a.compare(b)` and `b.compare(a)` differ when the two tolerances do.
- A difference is recorded in the comparer as one of the field `value`
  (`compare_field`), so the default `compare_items()` of `hexk_scoreboard` names it.
- `compare()` with an object of another class, also a wrapper of another `T`, is false.
- `convert2string()` is the value in hexadecimal, `0x<digits>`. `print()` and `sprint()`
  show `value` in hexadecimal and `tolerance`; `get_type_name()` is `hexk_value_wrapper`,
  without the parameter.
- `copy()` and `clone()` copy value and tolerance.

## 5. Configuration

| Member | Default | Meaning |
|---|---|---|
| `value` | uninitialised `T` | The wrapped value. |
| `tolerance` | 0 | Largest difference that `compare()` of this object accepts; 0 asks for identical bits. |

There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | fatal |  |
| `HEXK_VALUE_WRAPPER_WIDTH` | error |  |
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_value_wrapper/hexk_value_wrapper_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_value_wrapper_example.sv
//
// Minimal use of hexk_value_wrapper: samples of an ADC, which are plain 12-bit numbers, are
// wrapped into objects so that they can go through an analysis port. The model predicts
// each sample only to within two counts, so the expected wrapper carries a tolerance of 2
// and compare() accepts the first sample and rejects the second.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_value_wrapper_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_value_wrapper;
   `include "uvm_macros.svh"

   typedef logic [11:0] hexk_example_sample_t;
   typedef hexk_value_wrapper#(hexk_example_sample_t) hexk_example_sample_item_t;

   localparam longint unsigned TOLERANCE = 2;

   // Compares a predicted sample with a measured one, as a scoreboard would.
   function automatic void check_sample(hexk_example_sample_t predicted, hexk_example_sample_t measured);
      hexk_example_sample_item_t expected = hexk_example_sample_item_t::wrap(predicted, TOLERANCE);
      hexk_example_sample_item_t actual = hexk_example_sample_item_t::wrap(measured);
      if (expected.compare(actual)) begin
         `uvm_info("EXAMPLE", $sformatf("%s is within %0d of %s", actual.convert2string(), TOLERANCE,
                                        expected.convert2string()), UVM_NONE)
      end else begin
         `uvm_error("EXAMPLE", $sformatf(
                    "%s is not within %0d of %s", actual.convert2string(), TOLERANCE, expected.convert2string()))
      end
   endfunction : check_sample

   initial begin
      check_sample(12'd1000, 12'd1002);
      check_sample(12'd1000, 12'd1003);
   end

endmodule : hexk_value_wrapper_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **The tolerance on the actual item.** `expected.compare(actual)` uses the tolerance of
  `expected`. Set it where the prediction is made.
- **A tolerance as a type parameter in a class of your own.** Two tolerances then need two
  port types. This class keeps it a member for that reason.
- **A wrapper per field of a transaction.** The fields then travel separately and a mismatch
  names none of them. Use an item class.
- **A wide tolerance to make a test pass.** State where the tolerance comes from, the
  resolution of the model or the specification, next to the number.
- **Changing `value` after the wrapper was written to a port.** The receivers hold the same
  object. Create a wrapper per value.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. On Verilator, which has
two-state variables, the two tests with X bits are left out of the build.
