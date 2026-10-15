# hexk_enum_util

## 1. Summary

Enum utilities as static functions of a class parameterized with the enum type: name
lookup in both directions, membership test, list of all members, common name prefix,
name-to-value map and a printable list of names.

## 2. When to use / when not to use

Use it whenever an enum meets text or an unchecked number: reading a mode from a plusarg or a
file, checking that a value sampled from the DUT is a legal member, printing the legal names
in a help or error message, iterating over all members.

Do not use it for types that are not enums; it does not compile. Do not use it to print a
value you already hold: `value.name()` is enough. For reading an enum from a plusarg in a UVM
testbench, use `hexk_enum_knob` of `hexk_knobs`.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_enum_util.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_enum_util.sv`:

```systemverilog
// Default of the type parameter of hexk_enum_util: a placeholder that keeps the class legal when a tool elaborates it without an override. Always give your own enum type.
typedef enum bit {HEXK_ENUM_UTIL_NONE} hexk_enum_util_none_e;
// Name of value, or "" when value is not a member of E.
static function string name(E value);
// Sets value to the member called enum_name and returns 1; else returns 0 and the first member.
static function bit try_from_name(string enum_name, output E value, input bit ignore_case = 0);
// Member called enum_name; an unknown name is reported with $error and gives the first member.
static function E from_name(string enum_name);
// True when a member of E has this value. A member that does not fit 64 bits is never found: for such an enum use name(value) != "".
static function bit is_member(longint value);
// Number of members of E.
static function int num();
// Fills values (cleared first) with every member of E, in declaration order.
static function void all(ref E values[$]);
// Longest text that every member name starts with and that ends in "_", for example "MY_MODE_".
static function string common_prefix();
// Fills map (cleared first) with name-to-value pairs; strip_prefix removes common_prefix() from the names.
static function void to_map(ref E map[string], input bit strip_prefix = 0);
// All member names in declaration order, joined with sep; for help and error messages.
static function string to_list_str(string sep = ", ");
```
<!-- HEXK_GEN:END api -->

All functions are static. Give the enum type as the class parameter:
`hexk_enum_util #(my_mode_e)::from_name("MY_MODE_FAST")`. A `typedef` per enum keeps calls
short: `typedef hexk_enum_util #(my_mode_e) my_mode_util;`.

## 4. Behaviour and invariants

- Every function is pure and derives everything from the type `E`; there is no state.
- Members are visited in declaration order (`first()` to `last()`), so `all` and `to_list_str`
  list them in that order.
- `name` returns `""` for a value that is not a member; it never returns the name of another
  member.
- `try_from_name` always sets `value`: to the member found, or to the first member when the
  name is unknown. It reports nothing. Names are compared exactly unless `ignore_case` is set.
- `from_name` reports an unknown name with `$error`, lists the legal names in the message,
  and returns the first member.
- `is_member` takes a 64-bit value: enum values are converted to `longint` with the
  signedness of the enum base type. A member of an enum wider than 64 bits whose value does
  not fit 64 bits is never found; for such an enum test `name(value) != ""`, which compares
  values of the enum type. Verilator 5.046 has no enum methods above 64 bits at all.
- `common_prefix` is the longest text that every member name starts with, cut back to its
  last underscore; `""` when the names share no text ending in an underscore. For an enum
  with one member it is that name up to and including its last underscore.
- `to_map` clears the map first. With `strip_prefix` the keys are the names without
  `common_prefix()`. The values of the map have the enum type, so the result of a lookup is
  assigned to a variable of that type without a cast.
- `hexk_enum_util_none_e` is only the default of the type parameter. It exists because some
  tools elaborate a parameterized class with its defaults; it has no other use.

## 5. Configuration

None.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`from_name` calls `$error` with text starting `hexk_enum_util::from_name:`. It has no UVM
message ID because the core layer does not use UVM. On Verilator a `$error` stops the
simulation unless `+verilator+error+limit+<n>` raises the limit.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_enum_util/hexk_enum_util_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_enum_util_example.sv
//
// Minimal use of hexk_enum_util: turn text into an enum value without a case statement,
// print the legal names, and get short names by stripping the common prefix.
// Needs only src/core/hexk_core.f.

module hexk_enum_util_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_enum_util;

   // Operating modes of an imaginary DUT.
   typedef enum {
      HEXK_EXAMPLE_MODE_IDLE,
      HEXK_EXAMPLE_MODE_FAST,
      HEXK_EXAMPLE_MODE_SLOW
   } hexk_example_mode_e;

   // One typedef per enum keeps the calls short.
   typedef hexk_enum_util#(hexk_example_mode_e) hexk_example_mode_util;

   hexk_example_mode_e mode;
   hexk_example_mode_e values[string];

   initial begin
      if (!hexk_example_mode_util::try_from_name("hexk_example_mode_fast", mode, 1)) begin
         $error("not a mode; legal names: %s", hexk_example_mode_util::to_list_str());
      end
      $info("mode %s, one of %0d", hexk_example_mode_util::name(mode), hexk_example_mode_util::num());

      hexk_example_mode_util::to_map(values, 1);
      $info("without '%s': FAST=%0d SLOW=%0d", hexk_example_mode_util::common_prefix(), values["FAST"], values["SLOW"]);
   end

endmodule : hexk_enum_util_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Using the class without a type parameter** (`hexk_enum_util::name(x)`). That selects the
  placeholder enum and does not match your type. Always write `hexk_enum_util #(my_enum_e)`.
- **Ignoring the result of `try_from_name`.** `value` holds the first member when the name is
  unknown, which looks like a legal answer. Test the returned bit, or use `from_name`.
- **Writing a `case` over names to convert text.** It goes stale when a member is added.
  `try_from_name` follows the type.
- **`$cast` to validate a number.** `$cast(mode, number)` works, but the failure is silent in
  function-call form. `is_member(number)` states the intent and has no side effect.
- **Using `from_name` for optional input.** It reports every unknown name as an error. For
  input that may legitimately be something else, use `try_from_name`.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
