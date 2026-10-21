# hexk_check_macros

## 1. Summary

Check macros: one line states what must hold, and a failure reports what was expected,
what was observed and where, with a static message ID given by the caller.

## 2. When to use / when not to use

Use them for every procedural check in testbench classes, and in modules and interfaces
that import `uvm_pkg`: data comparisons in scoreboards and models, protocol sanity checks in
monitors, argument checks. They give uniform messages (guide rule MSG-8), static IDs
(MSG-2) and proof that checking took place (TST-6). Use the `or_fatal` macros for every
`randomize()` and for every `$cast` whose failure is a bug (LNG-10, LNG-20).

Do not use them for temporal protocol rules; those are SVA in the interface. Do not use them
in static methods of classes derived from `uvm_report_object`: they do not compile there,
because they report through the calling object; write the `if` and use
`` `hexk_static_error ``. Do not use the `_fatal` variants for a check that could let the
test continue.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_check_macros.svh`
- `src/uvm/report/hexk_check_stats.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_check_macros.svh`:

```systemverilog
// Error unless COND holds; MSG is the whole message.
`define hexk_check(COND, ID, MSG)
// Fatal unless COND holds; MSG is the whole message.
`define hexk_check_fatal(COND, ID, MSG)
// Error unless ACT == EXP, with EXP brought to the width of ACT.
`define hexk_check_eq(ACT, EXP, ID, MSG = "")
// Fatal unless ACT == EXP, with EXP brought to the width of ACT.
`define hexk_check_eq_fatal(ACT, EXP, ID, MSG = "")
// Error unless ACT != EXP.
`define hexk_check_ne(ACT, EXP, ID, MSG = "")
// Fatal unless ACT != EXP.
`define hexk_check_ne_fatal(ACT, EXP, ID, MSG = "")
// Error unless ACT < EXP as numbers.
`define hexk_check_lt(ACT, EXP, ID, MSG = "")
// Fatal unless ACT < EXP as numbers.
`define hexk_check_lt_fatal(ACT, EXP, ID, MSG = "")
// Error unless ACT <= EXP as numbers.
`define hexk_check_le(ACT, EXP, ID, MSG = "")
// Fatal unless ACT <= EXP as numbers.
`define hexk_check_le_fatal(ACT, EXP, ID, MSG = "")
// Error unless ACT > EXP as numbers.
`define hexk_check_gt(ACT, EXP, ID, MSG = "")
// Fatal unless ACT > EXP as numbers.
`define hexk_check_gt_fatal(ACT, EXP, ID, MSG = "")
// Error unless ACT >= EXP as numbers.
`define hexk_check_ge(ACT, EXP, ID, MSG = "")
// Fatal unless ACT >= EXP as numbers.
`define hexk_check_ge_fatal(ACT, EXP, ID, MSG = "")
// Error unless ACT === EXP; X and Z bits must match too.
`define hexk_check_case_eq(ACT, EXP, ID, MSG = "")
// Fatal unless ACT === EXP; X and Z bits must match too.
`define hexk_check_case_eq_fatal(ACT, EXP, ID, MSG = "")
// Error unless the strings ACT and EXP are equal.
`define hexk_check_streq(ACT, EXP, ID, MSG = "")
// Fatal unless the strings ACT and EXP are equal.
`define hexk_check_streq_fatal(ACT, EXP, ID, MSG = "")
// Error unless the queues ACT_Q and EXP_Q have the same size and elements; reports the first difference.
`define hexk_check_q_eq(ACT_Q, EXP_Q, ID, MSG = "")
// Fatal unless the queues ACT_Q and EXP_Q have the same size and elements; reports the first difference.
`define hexk_check_q_eq_fatal(ACT_Q, EXP_Q, ID, MSG = "")
// Error unless EXP.compare(ACT) holds (the expected object decides); prints both objects with sprint().
`define hexk_check_obj_eq(ACT, EXP, ID, MSG = "")
// Fatal unless EXP.compare(ACT) holds (the expected object decides); prints both objects with sprint().
`define hexk_check_obj_eq_fatal(ACT, EXP, ID, MSG = "")
// Error unless LO <= VAL <= HI as numbers.
`define hexk_check_in_range(VAL, LO, HI, ID, MSG = "")
// Fatal unless LO <= VAL <= HI as numbers.
`define hexk_check_in_range_fatal(VAL, LO, HI, ID, MSG = "")
// Error unless VAL is inside SET, a list in braces such as {1, 2, [8:15]}.
`define hexk_check_inside(VAL, SET, ID, MSG = "")
// Fatal unless VAL is inside SET, a list in braces such as {1, 2, [8:15]}.
`define hexk_check_inside_fatal(VAL, SET, ID, MSG = "")
// Error if VAL has a bit set that is not set in MASK.
`define hexk_check_mask(VAL, MASK, ID, MSG = "")
// Fatal if VAL has a bit set that is not set in MASK.
`define hexk_check_mask_fatal(VAL, MASK, ID, MSG = "")
// Error unless VAL is a multiple of ALIGN.
`define hexk_check_aligned(VAL, ALIGN, ID, MSG = "")
// Fatal unless VAL is a multiple of ALIGN.
`define hexk_check_aligned_fatal(VAL, ALIGN, ID, MSG = "")
// Fatal if OBJ.randomize() fails.
`define hexk_randomize_or_fatal(OBJ, ID)
// Fatal if OBJ.randomize() with the given constraints fails; CONSTRAINTS is written without braces, and every variable of the calling scope in it is written with local:: (guide LNG-15).
`define hexk_randomize_with_or_fatal(OBJ, ID, CONSTRAINTS)
// Fatal if std::randomize(VAR) fails.
`define hexk_std_randomize_or_fatal(VAR, ID)
// Fatal if std::randomize(VAR) with the given constraints fails; CONSTRAINTS is written without braces.
`define hexk_std_randomize_with_or_fatal(VAR, ID, CONSTRAINTS)
// Fatal if SRC cannot be cast to DST. A null SRC casts and leaves DST null: check DST when null is an error.
`define hexk_cast_or_fatal(DST, SRC, ID)
```

The file also defines building blocks of these, marked "Internal" in the source; they may change, do not call them.

From `src/uvm/report/hexk_check_stats.sv`:

```systemverilog
// Signed number wide enough for an operand of HEXK_CHECK_MAX_WIDTH bits: a signed operand is sign-extended into it, others zero-extended.
typedef logic signed [HEXK_CHECK_MAX_WIDTH:0] hexk_check_num_t;
// Unsigned vector of HEXK_CHECK_MAX_WIDTH bits: a bit pattern as the functions of hexk_check_stats take it.
typedef logic [HEXK_CHECK_MAX_WIDTH-1:0] hexk_check_bits_t;
// Copy of an operand of a check of bits whose first operand has at most HEXK_CHECK_WORD_WIDTH bits.
typedef logic [HEXK_CHECK_WORD_WIDTH:1] hexk_check_word_t;
// Copy of an operand of a check of bits whose first operand is wider than HEXK_CHECK_WORD_WIDTH bits.
typedef logic [HEXK_CHECK_MAX_WIDTH:1] hexk_check_wide_t;
// Signed number for the operands of an order or range check of which none has more than HEXK_CHECK_WORD_WIDTH bits: the usual case, which then costs little.
typedef logic signed [HEXK_CHECK_WORD_WIDTH:0] hexk_check_word_num_t;
// The order that an order check asks for between its two operands.
typedef enum bit [1:0] { HEXK_CHECK_LT, HEXK_CHECK_LE, HEXK_CHECK_GT, HEXK_CHECK_GE } hexk_check_order_e;
// Counts one passed check with this ID.
static function void record_pass(string id);
// Counts one failed check with this ID.
static function void record_fail(string id);
// Number of passed checks with this ID, or of all checks when id is "".
static function int unsigned num_passed(string id = "");
// Number of failed checks with this ID, or of all checks when id is "".
static function int unsigned num_failed(string id = "");
// Number of checks executed, passed or failed.
static function int unsigned num_checks();
// Says that up to count more failed checks with this ID are expected, for a negative test.
static function void expect_failures(string id, int unsigned count = 1);
// Number of failed checks beyond those that expect_failures() allowed, over all IDs.
static function int unsigned num_unexpected_failures();
// Table of passed and failed checks per ID, with a total line; for the end of a test.
static function string summary();
// Start of the message of a failed check: the user's text and a colon, or nothing.
static function string prefix(string msg);
// Text of an object in the message of a failed object check; a null handle prints as "null".
static function string object_text(uvm_object obj);
// A bit pattern of width bits as hexadecimal text.
static function string bits_text(hexk_check_bits_t value, int unsigned width);
// A number as hexadecimal text; a negative one in two's complement of width bits, or of more when it needs them.
static function string num_text(hexk_check_num_t value, int unsigned width);
// 1 when an operand of width bits fits the vectors of the checks, so that a check compares all of it.
static function bit fits(int unsigned width);
// 1 when value, a number by its own signedness, fits width bits as an unsigned or as a signed number: every bit from width up is 0, or every bit from width - 1 up is 1. A bit that is X or Z there does not fit.
static function bit value_fits(hexk_check_num_t value, int unsigned width);
// value_fits for the numbers of the checks whose operands have at most HEXK_CHECK_WORD_WIDTH bits.
static function bit value_fits_word(hexk_check_word_num_t value, int unsigned width);
// Message of a check whose second operand, what, does not fit the width bits of its first operand, first.
static function string unfit_text(string msg, string what, hexk_check_num_t value, string first, int unsigned width);
// Message of a check on an operand that is too wide to be compared; what names the operand.
static function string too_wide_text(string msg, string what, int unsigned width);
// is_ordered for operands of at most HEXK_CHECK_WORD_WIDTH bits.
static function bit is_ordered_word(hexk_check_word_num_t act, hexk_check_order_e order, hexk_check_word_num_t exp);
// is_in_range for operands of at most HEXK_CHECK_WORD_WIDTH bits.
static function bit is_in_range_word(hexk_check_word_num_t val, hexk_check_word_num_t lo, hexk_check_word_num_t hi);
// 1 when the two numbers are in the given order; 0 also when one of them has an X or Z bit.
static function bit is_ordered(hexk_check_num_t act, hexk_check_order_e order, hexk_check_num_t exp);
// 1 when val is within lo to hi, both included; 0 also when one of the three has an X or Z bit.
static function bit is_in_range(hexk_check_num_t val, hexk_check_num_t lo, hexk_check_num_t hi);
// Message of a failed order check; width is the width of the first operand, widest that of the wider of the two, order the order that the check asked for.
static function string order_text(string msg, hexk_check_num_t act, hexk_check_num_t exp, int unsigned width, int unsigned widest, hexk_check_order_e order);
// The operator of an order as SystemVerilog writes it.
static function string order_operator(hexk_check_order_e order);
// Message of a failed check that compares bits; width is the width of the first operand, op the operator as text.
static function string compare_text(string msg, hexk_check_bits_t act, hexk_check_bits_t exp, int unsigned width, string op);
// Message of a failed set check; width is the width of the value.
static function string set_text(string msg, hexk_check_bits_t val, int unsigned width);
// Message of a failed mask check; width is the width of the value.
static function string mask_text(string msg, hexk_check_bits_t val, hexk_check_bits_t mask, int unsigned width);
// Message of a failed alignment check; width is the width of the value.
static function string aligned_text(string msg, hexk_check_bits_t val, hexk_check_bits_t align, int unsigned width);
// Message of a failed range check; width is the width of the value, with_lo that of the wider of value and lower limit, widest that of the widest of all three.
static function string range_text(string msg, hexk_check_num_t val, hexk_check_num_t lo, hexk_check_num_t hi, int unsigned width, int unsigned with_lo, int unsigned widest);
// Forgets all counts; for unit tests.
static function void reset_for_test();
```
<!-- HEXK_GEN:END api -->

`ID` is a string, `MSG` an optional string that starts the message.

## 4. Behaviour and invariants

- Each macro is one complete `begin ... end` statement, like the `` `uvm_* `` macros: it is
  safe after `if` without `begin`, and no semicolon follows it.
- A failed check reports a UVM error (the `_fatal` twin a UVM fatal) with the caller's ID,
  with file and line of the macro call, through the reporter of the calling scope: the
  component or sequence in a class, the root reporter in a module or interface. The check
  itself does not stop the caller; execution continues after it.
- Operands are evaluated exactly once, into temporaries, also when the check fails. The
  exception is `hexk_check_q_eq`, which reads its two operands in place, several times.
- Operands are integral values: vectors, integers, enums, packed structs. A check compares
  operands of up to `HEXK_MAX_WIDTH` bits, and of up to 64 bits when `HEXK_MAX_WIDTH` is set
  below 64, so that every integer type can be checked whatever the setting. A check whose
  first operand is wider fails, with a message that names the two widths: it does not
  compare a part of the value. In an order check and in `hexk_check_in_range` the same holds
  for the other operands, which are numbers of their own: a wider `EXP`, `LO` or `HI` fails
  the check with a message that names it (`exp has 1101 bits and a check compares at most
  1024: not compared`). In the checks of bits the second operand must fit the width of the
  first (see below), and one wider than a check compares fails in the same way (`exp has 1101
  bits ...`, `mask has ...`, `align has ...`), whatever its value. `hexk_check_q_eq` has no such limit, because it reads its operands in
  place.
- An operand can be a variable, a member of an object (`item.data`), a signal of a virtual
  interface (`vif.ready`), a call of a method or of a function of a module or a package,
  with or without side effects, or an expression of these. A name with a hierarchical path
  through module instances (`top.dut.sig`) is not portable as the first operand; copy it
  into a variable. On Verilator 5.046, the `VAL` of `hexk_check_inside` cannot be a call of a
  method of the calling class (the macro needs a size cast of its width, which Verilator
  evaluates without the object); copy the value into a variable there. The other checks take
  such a call on every simulator.
- The macros copy their operands into variables of a fixed type and use the widths of the
  operands in expressions only. No declaration depends on an operand, which is what lets
  every kind of operand compile on VCS, Questa and Verilator. The copies are small in the
  usual case and have the full check width otherwise: a check of bits takes 64 bits when
  its first operand has no more, an order check and `hexk_check_in_range` take 65 signed
  bits when none of their operands has more than 64. Measured on VCS X-2025.06 with ten
  million passing checks on 32-bit operands (2026-10-14): 0.19 us for an order check and
  0.20 us for a range check; with copies of the full width they took 0.30 and 0.38 us.
- The macros declare variables whose names start with `hexk_check_` in a block of their
  own. A variable of the caller with such a name cannot be an operand: the macro would read
  its own variable. Names with the prefix of the library belong to the library.
- **Equality checks** (`_eq`, `_ne`, `_case_eq`) compare bits. `EXP` is first the number it
  stands for in its own type, and it must fit the width of `ACT` as an unsigned or as a signed
  number: against an 8-bit `ACT`, 255, `8'hFF`, -1, -128 and `'1` fit, 256 and -129 do not.
  An `EXP` that does not fit fails the check, whatever the operator, with
  `exp=0x100 does not fit the 8 bits of act, as an unsigned or a signed number: not compared`:
  the check cannot compare what was meant, and a cut value would compare something else. An
  `EXP` that fits is brought to the width of `ACT`, extended by its own signedness if it is
  narrower. A signed and an unsigned operand with the same bits are equal. An `EXP` that is no
  wider than `ACT` always fits, also a signed one whose top bit is X or Z. An X or Z bit of a
  wider `EXP` above the width of `ACT` does not fit.
- **Order checks** (`_lt`, `_le`, `_gt`, `_ge`, `_in_range`) compare numbers. Each operand
  counts as the number it stands for in its own type: a signed operand can be negative, an
  unsigned one cannot, and the widths do not matter. So an unsigned 200 is greater than -1,
  where the plain SystemVerilog expression `8'd200 > -1` is false.
- An operand that is an expression is evaluated in the width of the comparison (at least 65
  bits), as in an assignment to a variable of that width: `a + 1` of an `int a` that holds
  the largest `int` is 2147483648, not the wrapped -2147483648. To check a value that wraps
  at its own width, assign it to a variable of that width first and give the variable.
- `hexk_check_inside` tests `VAL` as `inside` itself does: a signed `VAL` as a signed number,
  so that `-3` is inside `{[-5:-1]}`, an unsigned one as an unsigned number of its own width,
  so that `8'd200` is not inside `{[-5:-1]}`. The message prints `VAL` in its own width.
  Whether `VAL` is signed is found at compile time; the macro picks one of four copies (signed
  or not, up to 64 bits or wider), and only that one runs.
- `hexk_check_mask` and `hexk_check_aligned` take `VAL` as an unsigned vector of its own
  width; `MASK` and `ALIGN` must fit that width as `EXP` must in an equality check, and fail
  the check otherwise (`align=0x104 does not fit the 8 bits of val, ...`).
- `MSG` and the rest of the message are built only when the check fails.
- Messages:

  | Macro | Message after the optional `MSG: ` |
  |---|---|
  | `hexk_check` | `MSG` alone |
  | `hexk_check_eq`, `_ne`, `_lt`, `_le`, `_gt`, `_ge`, `_case_eq` | `act=0x4 exp=0x5 (expected act == exp)`, with the operator of the macro |
  | `hexk_check_eq`, `_ne`, `_case_eq`, `_mask`, `_aligned` with a second operand that does not fit | `exp=0x100 does not fit the 8 bits of act, as an unsigned or a signed number: not compared` (`mask=` or `align=` and `val` for the last two) |

  The equality checks print both values in the width of `ACT`. The order checks print a
  number that is not negative without leading zeros, and a negative number in two's
  complement of the width of `ACT`, or of as many more bits as it needs: -1 next to an 8-bit
  `ACT` is `0xff`, -1000 is `0xc18`.

  | Macro | Message after the optional `MSG: ` |
  |---|---|
  | `hexk_check_streq` | `act="abc" exp="abd"` |
  | `hexk_check_q_eq` | `size act=3 exp=4`, or `first difference at index 2: act=0xff exp=0x12` |
  | `hexk_check_obj_eq` | `objects differ`, then both objects printed with `sprint()` |
  | `hexk_check_in_range` | `val=0x9 is not in 0x1 to 0x8` |
  | `hexk_check_inside` | `val=0x3 is not in the set` |
  | `hexk_check_mask` | `val=0x81a5 has bits outside mask=0xff: 0x8100` |
  | `hexk_check_aligned` | `val=0x12 is not aligned to 0x8` |

- `hexk_check_eq` uses `==`: an X or Z bit in either operand makes the check fail.
  `hexk_check_case_eq` uses `===` and accepts matching X and Z bits.
- An order check on a value with an X or Z bit fails.
- `hexk_check_q_eq` works on queues, dynamic arrays and fixed-size arrays; sizes are compared
  first, then the elements with `==`: an X or Z bit in an element is a difference, as in
  `hexk_check_eq`. The elements are compared by position, the first with the first: two
  arrays may have different index ranges (`[0:1]` and `[1:2]`, or `[1:0]`), and an array can
  be compared with a queue. The index in the message is that of `ACT_Q`. The index of an
  array may start below 0. Its operands are names of arrays, also members of an object, not
  function calls.
- `hexk_check_obj_eq` treats two null handles as equal and a null and a non-null handle as
  different; otherwise the result is `EXP.compare(ACT)`, as in `hexk_scoreboard`: the expected
  object decides, for instance with the tolerance of a `hexk_value_wrapper`.
- `hexk_cast_or_fatal` passes a null `SRC`: a cast of null succeeds and leaves `DST` null.
  Where the result must exist, such as the result of `clone()` or `create_object()`, check
  `DST` for null after the macro.
- `hexk_check_aligned` fails for an alignment of 0.
- Every check calls `hexk_check_stats::record_pass` or `record_fail` with its ID.
  `hexk_check_stats::num_checks()` is the number of checks executed so far and `summary()` a
  table per ID. The `or_fatal` macros are not counted.
- A test that makes checks fail on purpose says so in code, usually with `expect_check(id,
  count)` of `hexk_report_catcher`, which also expects their messages:
  `hexk_check_stats::expect_failures(id, count)` allows `count` more failed checks of that ID
  (calls add up). `num_unexpected_failures()` is the number of failed checks beyond the
  allowance, over all IDs; fewer failures than allowed are not counted against the test.
  `hexk_base_test` fails a test with an unexpected failure even when the message of the
  check was demoted or switched off (see its contract). `reset_for_test()` also forgets the
  allowances. `HEXK_NO_CHECK_STATS` removes the counting from the check macros only: the
  scoreboard, `hexk_csr_util` and direct calls of `record_pass()` and `record_fail()` still count.
- The `or_fatal` macros report a fatal with the text `randomization failed: <object>`,
  `randomization with constraints failed: <object>` or `cast failed: <source> to <target>`.

## 5. Configuration

| Compile-time switch | Effect |
|---|---|
| `+define+HEXK_NO_CHECK_STATS` | the checks do not call `hexk_check_stats` |

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

The macros report with the ID given by the caller.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_check_macros/hexk_check_macros_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_check_macros_example.sv
//
// Minimal use of the check macros: four checks with static message IDs on an address, a
// length, a status register and a data queue, and the table of executed checks at the end.
// All four pass here; a failing one would report a UVM error that names the values.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_check_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_check_stats;

   localparam int unsigned WORD_BYTES = 4;
   localparam int unsigned MAX_LENGTH = 64;
   localparam logic [7:0] STATUS_BITS = 8'h0F;

   logic         [31:0] addr = 32'h0000_1004;
   logic         [ 7:0] status = 8'h03;
   int unsigned         length = 12;
   byte unsigned        observed             [$];
   byte unsigned        expected             [$];

   initial begin
      observed = '{8'h10, 8'h11, 8'h12};
      expected = '{8'h10, 8'h11, 8'h12};

      `hexk_check_aligned(addr, WORD_BYTES, "EXAMPLE_ADDR", "write address")
      `hexk_check_in_range(length, 1, MAX_LENGTH, "EXAMPLE_LENGTH")
      `hexk_check_mask(status, STATUS_BITS, "EXAMPLE_STATUS", "reserved status bits")
      `hexk_check_q_eq(observed, expected, "EXAMPLE_DATA")

      $info("\n%s", hexk_check_stats::summary());
   end

endmodule : hexk_check_macros_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **A literal as first operand** (`` `hexk_check_eq(5, count, "ID") ``). An equality check
  then compares in the 32 bits of the literal, and strict lint complains about the width of
  a constant. Write the value under test first.
- **A second operand whose value does not fit the first in an equality check.** The check
  fails and says so; an expected value that cannot be represented is a mistake of the test.
  If a cut is meant, write it: `` `hexk_check_eq(byte_value, 8'(model_value), ...) ``.
- **An order check to compare bit patterns.** `` `hexk_check_lt(int_value, 32'hFFFF_FFFF, ...) ``
  compares the number in the `int`, which may be negative, with 4294967295. Declare values
  that are bit patterns as unsigned.
- **A real number as operand.** It is rounded to an integer. Use `` `hexk_check `` with the
  comparison written out.
- **A function call as operand of `hexk_check_q_eq`.** The operands are read several times;
  store the result in a queue first.
- **`get_name()` or a formatted string as ID.** IDs are static (MSG-2); the counts in
  `hexk_check_stats` and catcher rules depend on it. Put variable text in `MSG`.
- **A variable of your own named like a local of the macros.** A check copies its operands
  into local variables named `hexk_check_act`, `hexk_check_exp`, `hexk_check_val`,
  `hexk_check_lo`, `hexk_check_hi` and so on, and evaluates the operands after those are
  declared. An operand that is a variable of the same name reads the uninitialized local
  instead, and nothing reports it. Names that start with `hexk_` belong to the library: do
  not give them to your own variables.
- **A semicolon after the macro before `else`.** It ends the `if`, as with `` `uvm_error ``.
- **An `if` around a check that only reports.** `if (a != b) `uvm_error(...)` is what the
  macro replaces: the macro also counts the passing case.
- **Constraints with braces** in `` `hexk_randomize_with_or_fatal(obj, "ID", {x < 3;}) ``. Write
  them without the outer braces: `x < 3;`.
- **A variable of the calling scope without `local::`** in the constraints of
  `` `hexk_randomize_with_or_fatal ``. When the object has a member of the same name, the
  constraint uses the member: write `num_items == local::num_words;`. Verilator 5.046 rejects
  `local::` when the object is of a specialized parameterized class; there, give the variable a
  name that the object has no member of.
- **A string literal inside an operand of an `or_fatal` macro**, such as
  `` `hexk_cast_or_fatal(item, wrapper.create_object("item"), "ID") ``. These macros put their
  operands into the message as text, and Verilator rejects a quote inside it. Assign the
  value to a variable first and give the variable.
- **`assert(obj.randomize())`.** An assertion can be switched off, and then nothing is
  randomized (LNG-10). Use `` `hexk_randomize_or_fatal ``.
- **`hexk_check_eq` on values that may hold X** when X must match. Use `hexk_check_case_eq`.
- **A negative test that hides failing checks** by demoting their messages with a catcher
  alone. The failed checks still count; declare them with `expect_check()` of the catcher.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. On Verilator, which has
two-state variables, the three tests of the behaviour with X bits are left out of the
build.
The randomize wrappers run there with the z3 solver.

The macros use no `type()`: taking the type of the first operand does not compile on Questa
for a member of an object or a signal of a virtual interface, and is not legal SystemVerilog
for them. The order checks compare numbers instead of converting the second operand to the
type of the first.
