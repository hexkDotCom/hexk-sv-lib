// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_check_stats.sv
//
// Counters of the checks executed by the `hexk_check_* macros, per message ID.
// The macros call record_pass or record_fail for every check, so that at the end of a test
// there is positive proof that checking happened (guide rule TST-6): num_checks() is the
// number of checks executed, and summary() is a table per ID. Nothing has to be created or
// registered; the class is abstract and all members are static.
// A negative test that fails checks on purpose declares them with expect_failures(id, count);
// num_unexpected_failures() counts the failed checks beyond those, and hexk_base_test fails a
// test that has any, also when the messages of the checks were demoted or switched off.
// Compile with +define+HEXK_NO_CHECK_STATS to remove the counting from the macros.
// The file also holds what the macros need to compare numbers: the type hexk_check_num_t, a
// signed vector one bit wider than hexk_bits_t that holds any operand as the number it
// stands for, and the functions that compare such numbers and build the messages. They are
// functions and not part of the macros so that a check adds little code where it is used.
//
//! @module    hexk_check_macros
//! @since     0.7.0
//! @stability experimental
//! @serves    TST-6
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CHECK_STATS_SV
`define HEXK_CHECK_STATS_SV

// Largest number of bits of an operand that a check compares: HEXK_MAX_WIDTH, and at least 64.
localparam int unsigned HEXK_CHECK_MAX_WIDTH =
    (hexk_core_pkg::hexk_math::MAX_WIDTH > 64) ? hexk_core_pkg::hexk_math::MAX_WIDTH : 64;

// Signed number wide enough for an operand of HEXK_CHECK_MAX_WIDTH bits: a signed operand is sign-extended into it,
// others zero-extended.
typedef logic signed [HEXK_CHECK_MAX_WIDTH:0] hexk_check_num_t;

// Unsigned vector of HEXK_CHECK_MAX_WIDTH bits: a bit pattern as the functions of hexk_check_stats take it.
typedef logic [HEXK_CHECK_MAX_WIDTH-1:0] hexk_check_bits_t;

// Number of bits up to which a check that compares bits copies its operands into hexk_check_word_t.
localparam int unsigned HEXK_CHECK_WORD_WIDTH = 64;

// The two types below are those of the copies that a check of bits makes of its operands. Their ranges start
// at 1 on purpose: an operand is cast to the type of its copy, and a linter (slang, -Wuseless-cast) reports a
// cast to the type that the operand already has. No operand has these types, because $unsigned() and a size
// cast return a range that ends at 0.

// Copy of an operand of a check of bits whose first operand has at most HEXK_CHECK_WORD_WIDTH bits.
typedef logic [HEXK_CHECK_WORD_WIDTH:1] hexk_check_word_t;

// Copy of an operand of a check of bits whose first operand is wider than HEXK_CHECK_WORD_WIDTH bits.
typedef logic [HEXK_CHECK_MAX_WIDTH:1] hexk_check_wide_t;

// Signed number for the operands of an order or range check of which none has more than HEXK_CHECK_WORD_WIDTH
// bits: the usual case, which then costs little.
typedef logic signed [HEXK_CHECK_WORD_WIDTH:0] hexk_check_word_num_t;

// The order that an order check asks for between its two operands.
typedef enum {
   HEXK_CHECK_LT,
   HEXK_CHECK_LE,
   HEXK_CHECK_GT,
   HEXK_CHECK_GE
} hexk_check_order_e;

virtual class hexk_check_stats;

   // Number of passed checks per message ID.
   static int unsigned pass_count[string];

   // Number of failed checks per message ID.
   static int unsigned fail_count[string];

   // Number of failed checks per message ID that a test expects; see expect_failures().
   static int unsigned expected_fail_count[string];

   // Counts one passed check with this ID.
   static function void record_pass(string id);
      if (!pass_count.exists(id)) begin
         pass_count[id] = 0;
      end
      pass_count[id]++;
   endfunction : record_pass

   // Counts one failed check with this ID.
   static function void record_fail(string id);
      if (!fail_count.exists(id)) begin
         fail_count[id] = 0;
      end
      fail_count[id]++;
   endfunction : record_fail

   // Number of passed checks with this ID, or of all checks when id is "".
   static function int unsigned num_passed(string id = "");
      return count_of(pass_count, id);
   endfunction : num_passed

   // Number of failed checks with this ID, or of all checks when id is "".
   static function int unsigned num_failed(string id = "");
      return count_of(fail_count, id);
   endfunction : num_failed

   // Number of checks executed, passed or failed.
   static function int unsigned num_checks();
      return num_passed() + num_failed();
   endfunction : num_checks

   // Says that up to count more failed checks with this ID are expected, for a negative test.
   static function void expect_failures(string id, int unsigned count = 1);
      if (!expected_fail_count.exists(id)) begin
         expected_fail_count[id] = 0;
      end
      expected_fail_count[id] += count;
   endfunction : expect_failures

   // Number of failed checks beyond those that expect_failures() allowed, over all IDs.
   static function int unsigned num_unexpected_failures();
      int unsigned total;
      int unsigned allowed;
      foreach (fail_count[id]) begin
         allowed = expected_fail_count.exists(id) ? expected_fail_count[id] : 0;
         if (fail_count[id] > allowed) begin
            total += fail_count[id] - allowed;
         end
      end
      return total;
   endfunction : num_unexpected_failures

   // Table of passed and failed checks per ID, with a total line; for the end of a test.
   static function string summary();
      string lines[$];
      string ids  [$];
      foreach (pass_count[id]) begin
         ids.push_back(id);
      end
      foreach (fail_count[id]) begin
         if (!pass_count.exists(id)) begin
            ids.push_back(id);
         end
      end
      hexk_str::natural_sort(ids);
      lines.push_back($sformatf("Checks executed: %0d passed, %0d failed", num_passed(), num_failed()));
      foreach (ids[i]) begin
         lines.push_back($sformatf("  %7d passed %7d failed  %s", num_passed(ids[i]), num_failed(ids[i]), ids[i]));
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : summary

   // Start of the message of a failed check: the user's text and a colon, or nothing.
   static function string prefix(string msg);
      return (msg.len() == 0) ? "" : {msg, ": "};
   endfunction : prefix

   // Text of an object in the message of a failed object check; a null handle prints as "null".
   static function string object_text(uvm_object obj);
      return (obj == null) ? "null" : obj.sprint();
   endfunction : object_text

   // A bit pattern of width bits as hexadecimal text.
   static function string bits_text(hexk_check_bits_t value, int unsigned width);
      int unsigned       shown = (width == 0) ? 1 : width;
      string             digits;
      logic        [3:0] nibble;
      if (!$isunknown(value)) begin
         return $sformatf("0x%0h", value);
      end
      // The simulators differ in how %h prints a wide value with unknown bits: print each digit of width bits.
      for (int unsigned low = 0; low < shown && low < HEXK_CHECK_MAX_WIDTH; low += 4) begin
         nibble = 4'b0000;
         for (int unsigned k = 0; k < 4; k++) begin
            if (low + k < shown && low + k < HEXK_CHECK_MAX_WIDTH) begin
               nibble[k] = value[low+k];
            end
         end
         digits = {$sformatf("%h", nibble), digits};
      end
      return {"0x", digits};
   endfunction : bits_text

   // A number as hexadecimal text; a negative one in two's complement of width bits, or of more when it needs them.
   static function string num_text(hexk_check_num_t value, int unsigned width);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      int unsigned     shown = (width == 0) ? 1 : width;
      int unsigned     limit = $bits(hexk_check_num_t) - 1;
      hexk_check_num_t lowest;
      hexk_check_num_t pattern = value;
      if ($isunknown(value)) begin
         return bits_text(hexk_check_bits_t'(value), shown);
      end
      if (value >= 0) begin
         return $sformatf("0x%0h", value);
      end
      // A negative number is shown in two's complement of width bits, or of as many more as it needs.
      forever begin
         lowest = -(hexk_check_num_t'(1) <<< (shown - 1));
         if (shown >= limit || value >= lowest) begin
            break;
         end
         shown += 4;
      end
      for (int unsigned i = shown; i <= limit; i++) begin
         pattern[i] = 1'b0;
      end
      return $sformatf("0x%0h", pattern);
   endfunction : num_text

   // 1 when an operand of width bits fits the vectors of the checks, so that a check compares all of it.
   static function bit fits(int unsigned width);
      return width <= HEXK_CHECK_MAX_WIDTH;
   endfunction : fits

   // Message of a check on an operand that is too wide to be compared; what names the operand.
   static function string too_wide_text(string msg, string what, int unsigned width);
      string head = {prefix(msg), what};
      return $sformatf(
          "%s has %0d bits and a check compares at most %0d: not compared", head, width, HEXK_CHECK_MAX_WIDTH
      );
   endfunction : too_wide_text

   // is_ordered for operands of at most HEXK_CHECK_WORD_WIDTH bits.
   static function bit is_ordered_word(hexk_check_word_num_t act, hexk_check_order_e order, hexk_check_word_num_t exp);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      case (order)
         HEXK_CHECK_LT: return (act < exp) === 1'b1;
         HEXK_CHECK_LE: return (act <= exp) === 1'b1;
         HEXK_CHECK_GT: return (act > exp) === 1'b1;
         default:       return (act >= exp) === 1'b1;
      endcase
   endfunction : is_ordered_word

   // is_in_range for operands of at most HEXK_CHECK_WORD_WIDTH bits.
   static function bit is_in_range_word(hexk_check_word_num_t val, hexk_check_word_num_t lo, hexk_check_word_num_t hi);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      return (val >= lo && val <= hi) === 1'b1;
   endfunction : is_in_range_word

   // 1 when the two numbers are in the given order; 0 also when one of them has an X or Z bit.
   static function bit is_ordered(hexk_check_num_t act, hexk_check_order_e order, hexk_check_num_t exp);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      case (order)
         HEXK_CHECK_LT: return (act < exp) === 1'b1;
         HEXK_CHECK_LE: return (act <= exp) === 1'b1;
         HEXK_CHECK_GT: return (act > exp) === 1'b1;
         default:       return (act >= exp) === 1'b1;
      endcase
   endfunction : is_ordered

   // 1 when val is within lo to hi, both included; 0 also when one of the three has an X or Z bit.
   static function bit is_in_range(hexk_check_num_t val, hexk_check_num_t lo, hexk_check_num_t hi);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      return (val >= lo && val <= hi) === 1'b1;
   endfunction : is_in_range

   // Message of a failed order check; width is the width of the first operand, widest that of the wider of
   // the two, order the order that the check asked for.
   static function string order_text(string msg, hexk_check_num_t act, hexk_check_num_t exp, int unsigned width,
                                     int unsigned widest, hexk_check_order_e order);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      if (!fits(width)) begin
         return too_wide_text(msg, "act", width);
      end
      if (!fits(widest)) begin
         return too_wide_text(msg, "exp", widest);
      end
      return $sformatf(
          "%sact=%s exp=%s (expected act %s exp)",
          prefix(
              msg
          ),
          num_text(
              act, width
          ),
          num_text(
              exp, width
          ),
          order_operator(
              order
          )
      );
   endfunction : order_text

   // The operator of an order as SystemVerilog writes it.
   static function string order_operator(hexk_check_order_e order);
      case (order)
         HEXK_CHECK_LT: return "<";
         HEXK_CHECK_LE: return "<=";
         HEXK_CHECK_GT: return ">";
         default:       return ">=";
      endcase
   endfunction : order_operator

   // Message of a failed check that compares bits; width is the width of the first operand, op the operator as text.
   static function string compare_text(string msg, hexk_check_bits_t act, hexk_check_bits_t exp, int unsigned width,
                                       string op);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      if (!fits(width)) begin
         return too_wide_text(msg, "act", width);
      end
      return $sformatf(
          "%sact=%s exp=%s (expected act %s exp)", prefix(msg), bits_text(act, width), bits_text(exp, width), op
      );
   endfunction : compare_text

   // Message of a failed set check; width is the width of the value.
   static function string set_text(string msg, hexk_check_bits_t val, int unsigned width);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      if (!fits(width)) begin
         return too_wide_text(msg, "val", width);
      end
      return $sformatf("%sval=%s is not in the set", prefix(msg), bits_text(val, width));
   endfunction : set_text

   // Message of a failed mask check; width is the width of the value.
   static function string mask_text(string msg, hexk_check_bits_t val, hexk_check_bits_t mask, int unsigned width);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      if (!fits(width)) begin
         return too_wide_text(msg, "val", width);
      end
      return $sformatf(
          "%sval=%s has bits outside mask=%s: %s",
          prefix(
              msg
          ),
          bits_text(
              val, width
          ),
          bits_text(
              mask, width
          ),
          bits_text(
              val & ~mask, width
          )
      );
   endfunction : mask_text

   // Message of a failed alignment check; width is the width of the value.
   static function string aligned_text(string msg, hexk_check_bits_t val, hexk_check_bits_t align, int unsigned width);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      if (!fits(width)) begin
         return too_wide_text(msg, "val", width);
      end
      return $sformatf("%sval=%s is not aligned to %s", prefix(msg), bits_text(val, width), bits_text(align, width));
   endfunction : aligned_text

   // Message of a failed range check; width is the width of the value, with_lo that of the wider of value and
   // lower limit, widest that of the widest of all three.
   static function string range_text(string msg, hexk_check_num_t val, hexk_check_num_t lo, hexk_check_num_t hi,
                                     int unsigned width, int unsigned with_lo, int unsigned widest);
      // Called from every check: one copy of the code instead of one per call.
      // verilator no_inline_task
      if (!fits(width)) begin
         return too_wide_text(msg, "val", width);
      end
      if (!fits(with_lo)) begin
         return too_wide_text(msg, "lo", with_lo);
      end
      if (!fits(widest)) begin
         return too_wide_text(msg, "hi", widest);
      end
      return $sformatf(
          "%sval=%s is not in %s to %s", prefix(msg), num_text(val, width), num_text(lo, width), num_text(hi, width)
      );
   endfunction : range_text

   // Forgets all counts; for unit tests.
   static function void reset_for_test();
      pass_count.delete();
      fail_count.delete();
      expected_fail_count.delete();
   endfunction : reset_for_test

   // One count, or the sum of all counts when id is "".
   local static function int unsigned count_of(ref int unsigned counts[string], input string id);
      int unsigned total;
      if (id.len() != 0) begin
         return counts.exists(id) ? counts[id] : 0;
      end
      foreach (counts[key]) begin
         total += counts[key];
      end
      return total;
   endfunction : count_of

endclass : hexk_check_stats

`endif  // HEXK_CHECK_STATS_SV
