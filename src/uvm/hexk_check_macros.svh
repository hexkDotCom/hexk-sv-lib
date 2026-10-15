// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_check_macros.svh
//
// Check macros: one line states what must hold, and a failure reports what was expected,
// what was observed and where, with a static message ID given by the caller.
// `hexk_check_eq(act, exp, "MY_ID") reports a UVM error; every check has a _fatal twin
// that reports a UVM fatal. The or_fatal macros wrap randomize() and $cast, whose failure
// is always a bug. Each macro is one complete statement like the `uvm_* macros: write no
// semicolon after it. Operands are evaluated once, the message is built only on failure,
// and every check is counted in hexk_check_stats.
// Equality checks compare bits: the second operand is brought to the width of the first, as
// in an assignment. Order checks (lt, le, gt, ge, in_range) compare numbers: each operand
// counts as the number it stands for in its own type, signed or unsigned. Operands are
// integral values of up to HEXK_MAX_WIDTH bits; a class member, a signal of a virtual
// interface and a function call are fine as operands, a literal as the first operand is not.
// Use them in classes that report through UVM and, with uvm_pkg imported, in modules and
// interfaces. They do not compile in static methods of UVM classes.
// The macros copy their operands into local variables whose names start with hexk_check_; an
// operand that is a variable of such a name reads the local instead, so do not use those names.
// Compile-time switch: HEXK_NO_CHECK_STATS removes the counting.
// Include this file through hexk_macros.svh.
//
//! @module    hexk_check_macros
//! @since     0.7.0
//! @stability experimental
//! @serves    MSG-2 MSG-8 LNG-10 LNG-20 TST-6
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CHECK_MACROS_SVH
`define HEXK_CHECK_MACROS_SVH

// Internal: counts a passed check.
`ifdef HEXK_NO_CHECK_STATS
`define hexk_check_passed(ID)
`else
`define hexk_check_passed(ID) hexk_uvm_pkg::hexk_check_stats::record_pass(ID);
`endif

// Internal: counts a failed check.
`ifdef HEXK_NO_CHECK_STATS
`define hexk_check_failed(ID)
`else
`define hexk_check_failed(ID) hexk_uvm_pkg::hexk_check_stats::record_fail(ID);
`endif

// Internal: reports a failed check with the given severity, through the reporter of the calling scope.
`define hexk_check_report(SEVERITY, ID, TEXT) \
   if (uvm_report_enabled(uvm_pkg::UVM_NONE, SEVERITY, ID) != 0) begin \
      uvm_report(SEVERITY, ID, TEXT, uvm_pkg::UVM_NONE, `uvm_file, `uvm_line, "", 1); \
   end

// Internal: checks a condition.
`define hexk_check_condition(COND, ID, MSG, SEVERITY) \
   begin \
      if (COND) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, MSG) \
      end \
   end

// The checks below copy their operands into variables of a fixed type and use the width of the
// first operand in expressions only. A declaration whose range or type depends on an operand
// restricts what the operand can be: VCS rejects $bits() of a call of a module function with a
// side effect there, Questa type() of a member of an object, VCS type() of a method call
// through a handle. The first operand is copied with its own bits and zeros above. The other
// operands are extended to the type of the copy by their own signedness and then cut to the
// width of the first operand, which gives what an assignment to a variable of that width gives.
// The copies have 64 bits when the first operand has no more, which is the usual case and
// costs little, and the full check width otherwise. The width is a constant, so a simulator
// keeps one of the two branches.
// For every operator inside an operand and for every item of a set, Verilator reports the
// extension to the width of the copy (WIDTHEXPAND). That says nothing about the code of the
// caller, so the macros switch the warning off around their own statements.

// Internal: 1 when the first operand of a check is copied into 64 bits.
`define hexk_check_is_word(VALUE) ($bits(VALUE) <= hexk_uvm_pkg::HEXK_CHECK_WORD_WIDTH)

// Internal: 1 when all bits of the first operand of a check are compared.
`define hexk_check_fits(VALUE) ($bits(VALUE) <= hexk_uvm_pkg::HEXK_CHECK_MAX_WIDTH)

// Internal: the width of the widest of two or three operands of a check that compares numbers. The sum is
// not evaluated. It is there because the first operand is a variable or a signal and the others are often
// constants: a linter (slang, -Wbits-of-integer-constant) reports $bits() of a constant.
`define hexk_check_width2(FIRST, SECOND) $bits((FIRST) + (SECOND))

// Internal: hexk_check_width2 for three operands.
`define hexk_check_width3(FIRST, SECOND, THIRD) $bits((FIRST) + (SECOND) + (THIRD))

// Internal: compares the bits of two values in copies of type TYPE; EXP is brought to the width of ACT.
`define hexk_check_compare_as(TYPE, ACT, OP, EXP, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_act = TYPE'($unsigned(ACT)); \
      var automatic TYPE hexk_check_exp = TYPE'($unsigned($bits(ACT)'(TYPE'(EXP)))); \
      if (`hexk_check_fits(ACT) && (hexk_check_act OP hexk_check_exp)) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::compare_text( \
            MSG, hexk_check_act, hexk_check_exp, $bits(ACT), `"OP`")) \
      end \
   end

// Internal: compares the bits of two values; EXP is brought to the width of ACT. Each value is evaluated once.
`define hexk_check_compare(ACT, OP, EXP, ID, MSG, SEVERITY) \
   begin \
      /* verilator lint_off WIDTHEXPAND */ \
      if (`hexk_check_is_word(ACT)) \
         `hexk_check_compare_as(hexk_uvm_pkg::hexk_check_word_t, ACT, OP, EXP, ID, MSG, SEVERITY) \
      else \
         `hexk_check_compare_as(hexk_uvm_pkg::hexk_check_wide_t, ACT, OP, EXP, ID, MSG, SEVERITY) \
      /* verilator lint_on WIDTHEXPAND */ \
   end

// Internal: compares two values as numbers in copies of type TYPE, each extended by its own signedness.
// The comparison and the message are functions, so that a check adds little code where it is used.
`define hexk_check_order_as(TYPE, IS_ORDERED, ACT, ORDER, EXP, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_act = TYPE'(ACT); \
      var automatic TYPE hexk_check_exp = TYPE'(EXP); \
      if (`hexk_check_width2(ACT, EXP) <= hexk_uvm_pkg::HEXK_CHECK_MAX_WIDTH && \
          hexk_uvm_pkg::hexk_check_stats::IS_ORDERED(hexk_check_act, hexk_uvm_pkg::ORDER, hexk_check_exp)) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::order_text( \
            MSG, hexk_check_act, hexk_check_exp, $bits(ACT), `hexk_check_width2(ACT, EXP), hexk_uvm_pkg::ORDER)) \
      end \
   end

// Internal: compares two values as numbers, each in its own type. Each value is evaluated once.
// The copies have one bit more than 64 when no operand is wider than that, and the full check width otherwise.
`define hexk_check_order(ACT, ORDER, EXP, ID, MSG, SEVERITY) \
   begin \
      /* verilator lint_off WIDTHEXPAND */ \
      if (`hexk_check_width2(ACT, EXP) <= hexk_uvm_pkg::HEXK_CHECK_WORD_WIDTH) \
         `hexk_check_order_as(hexk_uvm_pkg::hexk_check_word_num_t, is_ordered_word, \
                              ACT, ORDER, EXP, ID, MSG, SEVERITY) \
      else \
         `hexk_check_order_as(hexk_uvm_pkg::hexk_check_num_t, is_ordered, \
                              ACT, ORDER, EXP, ID, MSG, SEVERITY) \
      /* verilator lint_on WIDTHEXPAND */ \
   end

// Internal: compares two strings.
`define hexk_check_strings(ACT, EXP, ID, MSG, SEVERITY) \
   begin \
      automatic string hexk_check_act = ACT; \
      automatic string hexk_check_exp = EXP; \
      if (hexk_check_act == hexk_check_exp) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, $sformatf("%sact=\"%s\" exp=\"%s\"", \
            hexk_uvm_pkg::hexk_check_stats::prefix(MSG), hexk_check_act, hexk_check_exp)) \
      end \
   end

// Internal: the element of a queue or array at a position counted from its first element, whatever its bounds.
`define hexk_check_at(ARRAY, POS) ARRAY[$left(ARRAY) - (POS) * $increment(ARRAY)]

// Internal: compares two queues or arrays, size first, then element by element; both are read in place.
// The elements are compared by position: the first with the first, whatever the bounds of two arrays are.
// Two elements are equal when == says so: an X or Z bit in one of them is a difference, as in hexk_check_eq.
`define hexk_check_queues(ACT_Q, EXP_Q, ID, MSG, SEVERITY) \
   begin \
      automatic bit hexk_check_differs = 0; \
      automatic int hexk_check_index = 0; \
      automatic int hexk_check_pos = 0; \
      if ($size(ACT_Q) == $size(EXP_Q)) begin \
         foreach (ACT_Q[hexk_check_i]) begin \
            if ((ACT_Q[hexk_check_i] == `hexk_check_at(EXP_Q, hexk_check_pos)) !== 1'b1) begin \
               hexk_check_differs = 1; \
               hexk_check_index   = hexk_check_i; \
               break; \
            end \
            hexk_check_pos++; \
         end \
      end \
      if ($size(ACT_Q) != $size(EXP_Q)) begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, $sformatf("%ssize act=%0d exp=%0d", \
            hexk_uvm_pkg::hexk_check_stats::prefix(MSG), $size(ACT_Q), $size(EXP_Q))) \
      end else if (hexk_check_differs) begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, $sformatf("%sfirst difference at index %0d: act=0x%0h exp=0x%0h", \
            hexk_uvm_pkg::hexk_check_stats::prefix(MSG), hexk_check_index, \
            ACT_Q[hexk_check_index], `hexk_check_at(EXP_Q, hexk_check_pos))) \
      end else begin \
         `hexk_check_passed(ID) \
      end \
   end

// Internal: compares two objects with compare(); two null handles are equal.
`define hexk_check_objects(ACT, EXP, ID, MSG, SEVERITY) \
   begin \
      automatic uvm_pkg::uvm_object hexk_check_act = ACT; \
      automatic uvm_pkg::uvm_object hexk_check_exp = EXP; \
      automatic bit hexk_check_equal = (hexk_check_act == hexk_check_exp); \
      if (hexk_check_act != null && hexk_check_exp != null) begin \
         hexk_check_equal = hexk_check_act.compare(hexk_check_exp); \
      end \
      if (hexk_check_equal) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, $sformatf("%sobjects differ\nact: %s\nexp: %s", \
            hexk_uvm_pkg::hexk_check_stats::prefix(MSG), \
            hexk_uvm_pkg::hexk_check_stats::object_text(hexk_check_act), \
            hexk_uvm_pkg::hexk_check_stats::object_text(hexk_check_exp))) \
      end \
   end

// Internal: checks in copies of type TYPE that a value is within inclusive limits.
`define hexk_check_range_as(TYPE, IS_IN_RANGE, VAL, LO, HI, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_val = TYPE'(VAL); \
      var automatic TYPE hexk_check_lo = TYPE'(LO); \
      var automatic TYPE hexk_check_hi = TYPE'(HI); \
      if (`hexk_check_width3(VAL, LO, HI) <= hexk_uvm_pkg::HEXK_CHECK_MAX_WIDTH && \
          hexk_uvm_pkg::hexk_check_stats::IS_IN_RANGE(hexk_check_val, hexk_check_lo, hexk_check_hi)) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::range_text( \
            MSG, hexk_check_val, hexk_check_lo, hexk_check_hi, $bits(VAL), `hexk_check_width2(VAL, LO), \
            `hexk_check_width3(VAL, LO, HI))) \
      end \
   end

// Internal: checks that a value is within inclusive limits; the three values are compared as numbers.
`define hexk_check_range(VAL, LO, HI, ID, MSG, SEVERITY) \
   begin \
      /* verilator lint_off WIDTHEXPAND */ \
      if (`hexk_check_width3(VAL, LO, HI) <= hexk_uvm_pkg::HEXK_CHECK_WORD_WIDTH) \
         `hexk_check_range_as(hexk_uvm_pkg::hexk_check_word_num_t, is_in_range_word, VAL, LO, HI, ID, MSG, SEVERITY) \
      else \
         `hexk_check_range_as(hexk_uvm_pkg::hexk_check_num_t, is_in_range, VAL, LO, HI, ID, MSG, SEVERITY) \
      /* verilator lint_on WIDTHEXPAND */ \
   end

// Internal: checks in copies of type TYPE that a value is in a set. The copy is brought back to the
// width of VAL for the test: Verilator 5.046 does not compile 'inside' with a range when the value
// is wider than the limits of the range.
`define hexk_check_set_as(TYPE, VAL, SET, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_val = TYPE'($unsigned(VAL)); \
      if (`hexk_check_fits(VAL) && ($bits(VAL)'(hexk_check_val) inside SET)) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::set_text( \
            MSG, hexk_check_val, $bits(VAL))) \
      end \
   end

// Internal: 1 when VAL is a signed expression. A conditional is signed only when both of its operands are, and
// with the condition 0 only the -1 is evaluated, so VAL is not.
`define hexk_check_is_signed(VAL) ((1'b0 ? (VAL) : -1) < 0)

// Internal: checks in a signed copy of type TYPE that a signed value is in a set. The copy is brought back to the
// width of VAL and made signed again, which a size cast does not keep on Verilator 5.046. The test of the set is a
// variable of its own: Verilator 5.046 gets a signed 'inside' wrong as an operand of &&.
`define hexk_check_set_signed_as(TYPE, VAL, SET, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_val = TYPE'(VAL); \
      var automatic bit  hexk_check_in = $signed($bits(VAL)'(hexk_check_val)) inside SET; \
      if (`hexk_check_fits(VAL) && hexk_check_in) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::set_text( \
            MSG, $unsigned($bits(VAL)'(hexk_check_val)), $bits(VAL))) \
      end \
   end

// Internal: checks that a value is in a set, as a signed number when VAL is signed and as an unsigned number of
// its own width otherwise, as 'inside' itself does. The test of the signedness is constant by design (CMPCONST
// for an unsigned VAL), and the message cuts a VAL wider than a check compares, which it reports as too wide.
`define hexk_check_set(VAL, SET, ID, MSG, SEVERITY) \
   begin \
      /* verilator lint_off WIDTHEXPAND */ \
      /* verilator lint_off WIDTHTRUNC */ \
      /* verilator lint_off CMPCONST */ \
      if (`hexk_check_is_signed(VAL) && `hexk_check_is_word(VAL)) \
         `hexk_check_set_signed_as(hexk_uvm_pkg::hexk_check_word_num_t, VAL, SET, ID, MSG, SEVERITY) \
      else if (`hexk_check_is_signed(VAL)) \
         `hexk_check_set_signed_as(hexk_uvm_pkg::hexk_check_num_t, VAL, SET, ID, MSG, SEVERITY) \
      else if (`hexk_check_is_word(VAL)) \
         `hexk_check_set_as(hexk_uvm_pkg::hexk_check_word_t, VAL, SET, ID, MSG, SEVERITY) \
      else \
         `hexk_check_set_as(hexk_uvm_pkg::hexk_check_wide_t, VAL, SET, ID, MSG, SEVERITY) \
      /* verilator lint_on CMPCONST */ \
      /* verilator lint_on WIDTHTRUNC */ \
      /* verilator lint_on WIDTHEXPAND */ \
   end

// Internal: checks in copies of type TYPE that a value has no bit set outside a mask.
`define hexk_check_bits_as(TYPE, VAL, MASK, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_val = TYPE'($unsigned(VAL)); \
      var automatic TYPE hexk_check_mask = TYPE'($unsigned($bits(VAL)'(TYPE'(MASK)))); \
      if (`hexk_check_fits(VAL) && ((hexk_check_val & ~hexk_check_mask) == 0)) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::mask_text( \
            MSG, hexk_check_val, hexk_check_mask, $bits(VAL))) \
      end \
   end

// Internal: checks that a value has no bit set outside a mask; MASK is brought to the width of VAL.
`define hexk_check_bits(VAL, MASK, ID, MSG, SEVERITY) \
   begin \
      /* verilator lint_off WIDTHEXPAND */ \
      if (`hexk_check_is_word(VAL)) \
         `hexk_check_bits_as(hexk_uvm_pkg::hexk_check_word_t, VAL, MASK, ID, MSG, SEVERITY) \
      else \
         `hexk_check_bits_as(hexk_uvm_pkg::hexk_check_wide_t, VAL, MASK, ID, MSG, SEVERITY) \
      /* verilator lint_on WIDTHEXPAND */ \
   end

// Internal: checks in copies of type TYPE that a value is a multiple of an alignment.
`define hexk_check_multiple_as(TYPE, VAL, ALIGN, ID, MSG, SEVERITY) \
   begin \
      var automatic TYPE hexk_check_val = TYPE'($unsigned(VAL)); \
      var automatic TYPE hexk_check_align = TYPE'($unsigned($bits(VAL)'(TYPE'(ALIGN)))); \
      if (`hexk_check_fits(VAL) && hexk_check_align != 0 && (hexk_check_val % hexk_check_align) == 0) begin \
         `hexk_check_passed(ID) \
      end else begin \
         `hexk_check_failed(ID) \
         `hexk_check_report(SEVERITY, ID, hexk_uvm_pkg::hexk_check_stats::aligned_text( \
            MSG, hexk_check_val, hexk_check_align, $bits(VAL))) \
      end \
   end

// Internal: checks that a value is a multiple of an alignment; both count as unsigned numbers of the width of VAL.
`define hexk_check_multiple(VAL, ALIGN, ID, MSG, SEVERITY) \
   begin \
      /* verilator lint_off WIDTHEXPAND */ \
      if (`hexk_check_is_word(VAL)) \
         `hexk_check_multiple_as(hexk_uvm_pkg::hexk_check_word_t, VAL, ALIGN, ID, MSG, SEVERITY) \
      else \
         `hexk_check_multiple_as(hexk_uvm_pkg::hexk_check_wide_t, VAL, ALIGN, ID, MSG, SEVERITY) \
      /* verilator lint_on WIDTHEXPAND */ \
   end

// Error unless COND holds; MSG is the whole message.
`define hexk_check(COND, ID, MSG) `hexk_check_condition(COND, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless COND holds; MSG is the whole message.
`define hexk_check_fatal(COND, ID, MSG) `hexk_check_condition(COND, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT == EXP, with EXP brought to the width of ACT.
`define hexk_check_eq(ACT, EXP, ID, MSG = "") `hexk_check_compare(ACT, ==, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT == EXP, with EXP brought to the width of ACT.
`define hexk_check_eq_fatal(ACT, EXP, ID, MSG = "") `hexk_check_compare(ACT, ==, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT != EXP.
`define hexk_check_ne(ACT, EXP, ID, MSG = "") `hexk_check_compare(ACT, !=, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT != EXP.
`define hexk_check_ne_fatal(ACT, EXP, ID, MSG = "") `hexk_check_compare(ACT, !=, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT < EXP as numbers.
`define hexk_check_lt(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_LT, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT < EXP as numbers.
`define hexk_check_lt_fatal(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_LT, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT <= EXP as numbers.
`define hexk_check_le(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_LE, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT <= EXP as numbers.
`define hexk_check_le_fatal(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_LE, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT > EXP as numbers.
`define hexk_check_gt(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_GT, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT > EXP as numbers.
`define hexk_check_gt_fatal(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_GT, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT >= EXP as numbers.
`define hexk_check_ge(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_GE, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT >= EXP as numbers.
`define hexk_check_ge_fatal(ACT, EXP, ID, MSG = "") \
   `hexk_check_order(ACT, HEXK_CHECK_GE, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT === EXP; X and Z bits must match too.
`define hexk_check_case_eq(ACT, EXP, ID, MSG = "") `hexk_check_compare(ACT, ===, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT === EXP; X and Z bits must match too.
`define hexk_check_case_eq_fatal(ACT, EXP, ID, MSG = "") \
   `hexk_check_compare(ACT, ===, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless the strings ACT and EXP are equal.
`define hexk_check_streq(ACT, EXP, ID, MSG = "") `hexk_check_strings(ACT, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless the strings ACT and EXP are equal.
`define hexk_check_streq_fatal(ACT, EXP, ID, MSG = "") `hexk_check_strings(ACT, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless the queues ACT_Q and EXP_Q have the same size and elements; reports the first difference.
`define hexk_check_q_eq(ACT_Q, EXP_Q, ID, MSG = "") `hexk_check_queues(ACT_Q, EXP_Q, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless the queues ACT_Q and EXP_Q have the same size and elements; reports the first difference.
`define hexk_check_q_eq_fatal(ACT_Q, EXP_Q, ID, MSG = "") \
   `hexk_check_queues(ACT_Q, EXP_Q, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless ACT.compare(EXP) holds; prints both objects with sprint().
`define hexk_check_obj_eq(ACT, EXP, ID, MSG = "") `hexk_check_objects(ACT, EXP, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless ACT.compare(EXP) holds; prints both objects with sprint().
`define hexk_check_obj_eq_fatal(ACT, EXP, ID, MSG = "") `hexk_check_objects(ACT, EXP, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless LO <= VAL <= HI as numbers.
`define hexk_check_in_range(VAL, LO, HI, ID, MSG = "") `hexk_check_range(VAL, LO, HI, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless LO <= VAL <= HI as numbers.
`define hexk_check_in_range_fatal(VAL, LO, HI, ID, MSG = "") \
   `hexk_check_range(VAL, LO, HI, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless VAL is inside SET, a list in braces such as {1, 2, [8:15]}.
`define hexk_check_inside(VAL, SET, ID, MSG = "") `hexk_check_set(VAL, SET, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless VAL is inside SET, a list in braces such as {1, 2, [8:15]}.
`define hexk_check_inside_fatal(VAL, SET, ID, MSG = "") `hexk_check_set(VAL, SET, ID, MSG, uvm_pkg::UVM_FATAL)

// Error if VAL has a bit set that is not set in MASK.
`define hexk_check_mask(VAL, MASK, ID, MSG = "") `hexk_check_bits(VAL, MASK, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal if VAL has a bit set that is not set in MASK.
`define hexk_check_mask_fatal(VAL, MASK, ID, MSG = "") `hexk_check_bits(VAL, MASK, ID, MSG, uvm_pkg::UVM_FATAL)

// Error unless VAL is a multiple of ALIGN.
`define hexk_check_aligned(VAL, ALIGN, ID, MSG = "") `hexk_check_multiple(VAL, ALIGN, ID, MSG, uvm_pkg::UVM_ERROR)

// Fatal unless VAL is a multiple of ALIGN.
`define hexk_check_aligned_fatal(VAL, ALIGN, ID, MSG = "") \
   `hexk_check_multiple(VAL, ALIGN, ID, MSG, uvm_pkg::UVM_FATAL)

// Fatal if OBJ.randomize() fails.
`define hexk_randomize_or_fatal(OBJ, ID) \
   begin \
      if (OBJ.randomize() != 1) begin \
         `hexk_check_report(uvm_pkg::UVM_FATAL, ID, {"randomization failed: ", `"OBJ`"}) \
      end \
   end

// Fatal if OBJ.randomize() with the given constraints fails; CONSTRAINTS is written without braces.
`define hexk_randomize_with_or_fatal(OBJ, ID, CONSTRAINTS) \
   begin \
      if (OBJ.randomize() with {CONSTRAINTS} != 1) begin \
         `hexk_check_report(uvm_pkg::UVM_FATAL, ID, {"randomization with constraints failed: ", `"OBJ`"}) \
      end \
   end

// Fatal if std::randomize(VAR) fails.
`define hexk_std_randomize_or_fatal(VAR, ID) \
   begin \
      if (std::randomize(VAR) != 1) begin \
         `hexk_check_report(uvm_pkg::UVM_FATAL, ID, {"randomization failed: ", `"VAR`"}) \
      end \
   end

// Fatal if std::randomize(VAR) with the given constraints fails; CONSTRAINTS is written without braces.
`define hexk_std_randomize_with_or_fatal(VAR, ID, CONSTRAINTS) \
   begin \
      if (std::randomize(VAR) with {CONSTRAINTS} != 1) begin \
         `hexk_check_report(uvm_pkg::UVM_FATAL, ID, {"randomization with constraints failed: ", `"VAR`"}) \
      end \
   end

// Fatal if SRC cannot be cast to DST.
`define hexk_cast_or_fatal(DST, SRC, ID) \
   begin \
      if ($cast(DST, SRC) == 0) begin \
         `hexk_check_report(uvm_pkg::UVM_FATAL, ID, {"cast failed: ", `"SRC`", " to ", `"DST`"}) \
      end \
   end

`endif  // HEXK_CHECK_MACROS_SVH
