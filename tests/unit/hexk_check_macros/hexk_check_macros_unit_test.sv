// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_check_macros_unit_test.sv
//
// SVUnit tests of the check macros and of hexk_check_stats.
// Every macro is run through a small helper function with a passing and a failing set of
// operands. The helper returns one line: how hexk_check_stats moved ("P" one pass, "F" one
// fail), which severity a hexk_report_catcher saw ("E" error, "F" fatal, "-" none) and the
// message text that a listener on hexk_report_server received. The catcher demotes the
// provoked errors and fatals to warnings, so nothing ends the run. Results are compared as
// text (see tests/unit/README.md). Needs UVM. Runs on Verilator with UVM 2020:
// make test SIM=verilator TEST=hexk_check_macros.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

// Interface whose signals are operands of checks through a virtual interface.
interface hexk_ut_check_if;
   logic        [7:0] data;
   logic signed [7:0] level;
endinterface : hexk_ut_check_if

module hexk_check_macros_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_server;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_msg_listener;
   import hexk_uvm_pkg::hexk_check_stats;

   // Listener that keeps the text and the reporter of the last message.
   class hexk_ut_last_message implements hexk_msg_listener;
      string text;
      string reporter;
      virtual function void on_message(uvm_report_message msg);
         uvm_report_object source = msg.get_report_object();
         text     = msg.get_message();
         reporter = source.get_full_name();
      endfunction : on_message
   endclass : hexk_ut_last_message

   // Object with one compared field.
   class hexk_ut_item extends uvm_object;
      int value;
      function new(string item_name = "hexk_ut_item");
         super.new(item_name);
      endfunction : new

      virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_ut_item other;
         return $cast(other, rhs) && other.value == value;
      endfunction : do_compare
   endclass : hexk_ut_item

   // Plain object whose members are operands of checks.
   class hexk_ut_packet;
      logic        [7:0] data       = 8'hA5;
      int                count      = 7;
      int unsigned       words  [$] = '{10, 20, 30};
      bit          [3:0] nibbles[3] = '{4'h1, 4'h2, 4'h3};
      int unsigned       reads;

      // Returns count and notes the call, to show how often an operand is evaluated.
      function int read_count();
         reads++;
         return count;
      endfunction : read_count
   endclass : hexk_ut_packet

   // Object of another type, for the failing cast.
   class hexk_ut_other extends uvm_object;
      function new(string item_name = "hexk_ut_other");
         super.new(item_name);
      endfunction : new
   endclass : hexk_ut_other

   // Object with one constrained random field.
   class hexk_ut_random extends uvm_object;
      rand int unsigned value;
      constraint value_cstr {value < 100;}
      function new(string item_name = "hexk_ut_random");
         super.new(item_name);
      endfunction : new
   endclass : hexk_ut_random

   // Component that runs a check in an ordinary method.
   class hexk_ut_component extends uvm_component;
      function new(string instance_name, uvm_component parent);
         super.new(instance_name, parent);
      endfunction : new

      function void check_level(int level);
         `hexk_check_le(level, 8, "UT_COMPONENT", "fifo level")
      endfunction : check_level
   endclass : hexk_ut_component

   string               name = "hexk_check_macros_ut";
   svunit_testcase      svunit_ut;

   hexk_report_server   server;
   hexk_report_catcher  catcher;
   hexk_ut_last_message last;
   hexk_ut_component    component;
   hexk_ut_packet       packet;
   hexk_ut_check_if check_if ();
   virtual hexk_ut_check_if vif;
   int unsigned             passed_before;
   int unsigned             failed_before;
   int unsigned             calls;

   function automatic void build();
      svunit_ut = new(name);
      // The UVM suites share one simulation: use the server that is installed, if any.
      server    = hexk_report_server::get_installed();
      if (server == null) begin
         server = hexk_report_server::install();
      end
      catcher   = hexk_report_catcher::add_global();
      last      = new();
      component = new("ut_component", null);
      server.add_listener(last);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      packet         = new();
      vif            = check_if;
      check_if.data  = 8'h3C;
      check_if.level = -8'sd5;
      catcher.clear();
      catcher.expect_msg("^UT_", UVM_ERROR, "", 0, -1, UVM_WARNING);
      catcher.expect_msg("^UT_", UVM_FATAL, "", 0, -1, UVM_WARNING);
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Remembers the state before a check.
   function automatic void mark();
      catcher.clear();
      catcher.expect_msg("^UT_", UVM_ERROR, "", 0, -1, UVM_WARNING);
      catcher.expect_msg("^UT_", UVM_FATAL, "", 0, -1, UVM_WARNING);
      last.text     = "";
      last.reporter = "";
      passed_before = hexk_check_stats::num_passed();
      failed_before = hexk_check_stats::num_failed();
   endfunction : mark

   // What happened since mark(): "<P|F|?> <E|F|-> <message text>".
   function automatic string outcome();
      int unsigned passed = hexk_check_stats::num_passed() - passed_before;
      int unsigned failed = hexk_check_stats::num_failed() - failed_before;
      string       counted = "?";
      string       severity = "-";
      if (passed == 1 && failed == 0) begin
         counted = "P";
      end
      if (passed == 0 && failed == 1) begin
         counted = "F";
      end
      if (catcher.get_count("^UT_", UVM_ERROR) == 1) begin
         severity = "E";
      end
      if (catcher.get_count("^UT_", UVM_FATAL) == 1) begin
         severity = "F";
      end
      return {counted, " ", severity, " ", last.text};
   endfunction : outcome

   // Counts the calls of value(), to show how often an operand is evaluated. A static method
   // and not a function of the module: VCS takes a call of a module function in the first
   // operand of an equality check as a constant function call (see the contract, section 8).
   class hexk_ut_counter;
      static int unsigned evaluations;

      static function int value(int number);
         evaluations++;
         return number;
      endfunction : value
   endclass : hexk_ut_counter

   // Returns text and counts the call, to show when a message is built.
   function automatic string counted_text(string text);
      calls++;
      return text;
   endfunction : counted_text

   function automatic string run_check(bit condition);
      mark();
      `hexk_check(condition, "UT_CHECK", "the condition does not hold")
      return outcome();
   endfunction : run_check

   function automatic string run_eq(int act, int exp, string msg = "");
      mark();
      `hexk_check_eq(act, exp, "UT_EQ", msg)
      return outcome();
   endfunction : run_eq

   function automatic string run_eq_wide(logic [71:0] act, logic [71:0] exp);
      mark();
      `hexk_check_eq(act, exp, "UT_EQ")
      return outcome();
   endfunction : run_eq_wide

   function automatic string run_relation(string relation, int act, int exp);
      mark();
      case (relation)
         "ne":    `hexk_check_ne(act, exp, "UT_NE")
         "lt":    `hexk_check_lt(act, exp, "UT_LT")
         "le":    `hexk_check_le(act, exp, "UT_LE")
         "gt":    `hexk_check_gt(act, exp, "UT_GT")
         default: `hexk_check_ge(act, exp, "UT_GE")
      endcase
      return outcome();
   endfunction : run_relation

   function automatic string run_four_state(bit case_equality, logic [3:0] act, logic [3:0] exp);
      mark();
      if (case_equality) `hexk_check_case_eq(act, exp, "UT_CASE_EQ")
      else `hexk_check_eq(act, exp, "UT_EQ")
      return outcome();
   endfunction : run_four_state

   function automatic string run_streq(string act, string exp);
      mark();
      `hexk_check_streq(act, exp, "UT_STREQ", "name")
      return outcome();
   endfunction : run_streq

   // Compares the queues {first .. first + count - 1} with a copy in which one element may be changed or dropped.
   function automatic string run_q_eq(int count, int changed_index = -1, bit drop_last = 0);
      int act[$];
      int exp[$];
      for (int i = 0; i < count; i++) begin
         act.push_back(16 + i);
         exp.push_back(16 + i);
      end
      if (changed_index >= 0) begin
         act[changed_index] = 255;
      end
      if (drop_last) begin
         void'(act.pop_back());
      end
      mark();
      `hexk_check_q_eq(act, exp, "UT_Q_EQ")
      return outcome();
   endfunction : run_q_eq

   // Compares two queues of four-state values that differ in the given element only.
   function automatic string run_q_eq_four_state(logic [3:0] act_element, logic [3:0] exp_element);
      logic [3:0] act[$] = '{4'h1, 4'h2, 4'h3};
      logic [3:0] exp[$] = '{4'h1, 4'h2, 4'h3};
      act[1] = act_element;
      exp[1] = exp_element;
      mark();
      `hexk_check_q_eq(act, exp, "UT_Q_EQ")
      return outcome();
   endfunction : run_q_eq_four_state

   // Compares two arrays whose index runs from -2 to -1 and that differ in the first element when asked.
   function automatic string run_q_eq_negative_index(bit differ);
      int act[-2:-1] = '{1, 2};
      int exp[-2:-1] = '{1, 2};
      if (differ) begin
         act[-2] = 3;
      end
      mark();
      `hexk_check_q_eq(act, exp, "UT_Q_EQ")
      return outcome();
   endfunction : run_q_eq_negative_index

   // Compares two items with the given values; a negative value stands for a null handle.
   function automatic string run_obj_eq(int act_value, int exp_value);
      hexk_ut_item act;
      hexk_ut_item exp;
      if (act_value >= 0) begin
         act       = new("act");
         act.value = act_value;
      end
      if (exp_value >= 0) begin
         exp       = new("exp");
         exp.value = exp_value;
      end
      mark();
      `hexk_check_obj_eq(act, exp, "UT_OBJ_EQ")
      // Only the first line of the message; the rest is the printout of both objects.
      if (last.text.len() > 14) begin
         last.text = last.text.substr(0, 13);
      end
      return outcome();
   endfunction : run_obj_eq

   // `hexk_check_gt(value + 1, 0) on an int: the sum is evaluated in the width of the comparison and does not wrap.
   function automatic string run_gt_of_a_sum(int value);
      mark();
      `hexk_check_gt(value + 1, 0, "UT_GT")
      return outcome();
   endfunction : run_gt_of_a_sum

   function automatic string run_in_range(int value, int lo, int hi);
      mark();
      `hexk_check_in_range(value, lo, hi, "UT_IN_RANGE")
      return outcome();
   endfunction : run_in_range

   function automatic string run_inside(int value);
      mark();
      `hexk_check_inside(value, {1, 2, [8 : 15]}, "UT_INSIDE")
      return outcome();
   endfunction : run_inside

   // hexk_check_inside with signed values, as 'inside' compares them: an int, then a byte.
   function automatic string run_inside_signed(int value, byte narrow);
      string first;
      mark();
      `hexk_check_inside(value, {[-2 : 0], 7}, "UT_INSIDE")
      first = outcome();
      mark();
      `hexk_check_inside(narrow, {[-2 : 0]}, "UT_INSIDE")
      return {first, "| ", outcome()};
   endfunction : run_inside_signed

   // hexk_check_inside with an unsigned value above the largest signed one.
   function automatic string run_inside_unsigned(int unsigned value);
      mark();
      `hexk_check_inside(value, {[32'h8000_0000 : 32'hFFFF_FFFF]}, "UT_INSIDE")
      return outcome();
   endfunction : run_inside_unsigned

   function automatic string run_mask(logic [15:0] value, logic [15:0] mask);
      mark();
      `hexk_check_mask(value, mask, "UT_MASK")
      return outcome();
   endfunction : run_mask

   function automatic string run_aligned(int unsigned value, int unsigned align);
      mark();
      `hexk_check_aligned(value, align, "UT_ALIGNED")
      return outcome();
   endfunction : run_aligned

   // Runs one _fatal check that fails, selected by name.
   function automatic string run_fatal(string which);
      string text = "a";
      string result;
      int    queue[$] = '{1};
      int    other[$];
      int    four = 4;
      int    five = 5;
      int    nine = 9;
      logic [7:0] bits = 8'h81;
      hexk_ut_item item = new("item");
      mark();
      case (which)
         "check":    `hexk_check_fatal(0, "UT_FATAL", "gave up")
         "eq":       `hexk_check_eq_fatal(four, 5, "UT_FATAL")
         "ne":       `hexk_check_ne_fatal(five, 5, "UT_FATAL")
         "lt":       `hexk_check_lt_fatal(five, 5, "UT_FATAL")
         "le":       `hexk_check_le_fatal(nine, 5, "UT_FATAL")
         "gt":       `hexk_check_gt_fatal(five, 5, "UT_FATAL")
         "ge":       `hexk_check_ge_fatal(four, 5, "UT_FATAL")
         "case_eq":  `hexk_check_case_eq_fatal(bits, 8'h80, "UT_FATAL")
         "streq":    `hexk_check_streq_fatal(text, "b", "UT_FATAL")
         "q_eq":     `hexk_check_q_eq_fatal(queue, other, "UT_FATAL")
         "obj_eq":   `hexk_check_obj_eq_fatal(item, null, "UT_FATAL")
         "in_range": `hexk_check_in_range_fatal(nine, 1, 8, "UT_FATAL")
         "inside":   `hexk_check_inside_fatal(nine, {1, 2}, "UT_FATAL")
         "mask":     `hexk_check_mask_fatal(bits, 8'h0F, "UT_FATAL")
         default:    `hexk_check_aligned_fatal(nine, 4, "UT_FATAL")
      endcase
      result = outcome();
      return result.substr(0, 2);
   endfunction : run_fatal

   // A check whose first operand is not a plain variable: a member of an object, a signal of a
   // virtual interface, an expression with one, a queue or an array of an object.
   function automatic string run_operand(string kind);
      int unsigned expected_words  [$] = '{10, 20, 30};
      bit [3:0]    expected_nibbles[3] = '{4'h1, 4'h2, 4'h7};
      mark();
      case (kind)
         "member_eq":      `hexk_check_eq(packet.data, 8'hA5, "UT_OPERAND")
         "member_ne":      `hexk_check_eq(packet.data, 8'hA6, "UT_OPERAND")
         "vif_eq":         `hexk_check_eq(vif.data, 8'h3C, "UT_OPERAND")
         "vif_case_eq":    `hexk_check_case_eq(vif.data, 8'h3C, "UT_OPERAND")
         "vif_lt":         `hexk_check_lt(vif.level, 0, "UT_OPERAND")
         "vif_ge":         `hexk_check_ge(vif.level, 0, "UT_OPERAND")
         "expression":     `hexk_check_eq(packet.count + 1, 8, "UT_OPERAND")
         "member_range":   `hexk_check_in_range(packet.count, 0, 7, "UT_OPERAND")
         "member_inside":  `hexk_check_inside(packet.data, {8'hA5, 8'hFF}, "UT_OPERAND")
         "member_mask":    `hexk_check_mask(packet.data, 8'hF7, "UT_OPERAND")
         "member_aligned": `hexk_check_aligned(packet.count + 1, 4, "UT_OPERAND")
         "member_queue":   `hexk_check_q_eq(packet.words, expected_words, "UT_OPERAND")
         default:          `hexk_check_q_eq(packet.nibbles, expected_nibbles, "UT_OPERAND")
      endcase
      return outcome();
   endfunction : run_operand

   // Order checks between operands of different signedness and width.
   function automatic string run_order(string kind);
      logic        [ 7:0] level = 8'd200;
      logic signed [ 7:0] minus_one = -8'sd1;
      logic        [15:0] all_ones = 16'hFFFF;
      int                 far_below = -1000;
      int                 pattern = 32'hDEAD_BEEF;
      mark();
      case (kind)
         "unsigned_lt_negative":  `hexk_check_lt(level, -1, "UT_ORDER")
         "unsigned_gt_negative":  `hexk_check_gt(level, -1, "UT_ORDER")
         "negative_lt_wide":      `hexk_check_lt(minus_one, all_ones, "UT_ORDER")
         "negative_ge_wide":      `hexk_check_ge(minus_one, all_ones, "UT_ORDER")
         "negative_le_far_below": `hexk_check_le(minus_one, far_below, "UT_ORDER")
         "range_signed":          `hexk_check_in_range(minus_one, -5, 5, "UT_ORDER")
         "range_unsigned":        `hexk_check_in_range(level, -1, 255, "UT_ORDER")
         "range_below":           `hexk_check_in_range(minus_one, 0, 5, "UT_ORDER")
         default:                 `hexk_check_eq(pattern, 32'hDEAD_BEEF, "UT_ORDER")
      endcase
      return outcome();
   endfunction : run_order

   // head, count zeros and tail as one text: the message of a check on a wide value.
   function automatic string with_zeros(string head, int unsigned count, string tail);
      string zeros;
      repeat (count) begin
         zeros = {zeros, "0"};
      end
      return {head, zeros, tail};
   endfunction : with_zeros

   // Order checks on a first operand of 1024 bits, the widest that is compared, and of 1101 bits.
   function automatic string run_order_wide(string kind);
      logic [1023:0] widest = '0;
      logic [1100:0] too_wide = '0;
      widest[1023]   = 1'b1;
      too_wide[1090] = 1'b1;
      mark();
      case (kind)
         "widest_gt":        `hexk_check_gt(widest, 0, "UT_ORDER")
         "widest_range":     `hexk_check_in_range(widest, 1, 5, "UT_ORDER")
         "too_wide_le":      `hexk_check_le(too_wide, 0, "UT_ORDER")
         "too_wide_gt":      `hexk_check_gt(too_wide, 0, "UT_ORDER")
         "too_wide_range":   `hexk_check_in_range(too_wide, 0, 5, "UT_ORDER")
         "too_wide_inside":  `hexk_check_inside(too_wide, {0, 1}, "UT_ORDER")
         "too_wide_mask":    `hexk_check_mask(too_wide, 0, "UT_ORDER")
         "too_wide_aligned": `hexk_check_aligned(too_wide, 2, "UT_ORDER")
         "too_wide_ne":      `hexk_check_ne(too_wide, 0, "UT_ORDER")
         "widest_eq":        `hexk_check_eq(widest, 0, "UT_ORDER")
         default:            `hexk_check_eq(too_wide, 0, "UT_ORDER")
      endcase
      return outcome();
   endfunction : run_order_wide

   // Order checks whose second or third operand has 1101 bits, more than a check compares; its low bits are 0,
   // so a check that cut it would pass.
   function automatic string run_wide_other_operand(string kind);
      logic [1100:0] too_wide = '0;
      int unsigned zero = 0;
      too_wide[1090] = 1'b1;
      mark();
      case (kind)
         "exp":   `hexk_check_ge(zero, too_wide, "UT_ORDER")
         "lo":    `hexk_check_in_range(zero, too_wide, 5, "UT_ORDER")
         default: `hexk_check_in_range(zero, 0, too_wide, "UT_ORDER")
      endcase
      return outcome();
   endfunction : run_wide_other_operand

   // Order checks on operands of exactly 64 bits, whose copies need one bit more for the sign, and on a
   // narrow first operand with a second one of 128 bits, which takes the wide copies.
   function automatic string run_order_64(string kind);
      logic   [ 63:0] top = '1;
      longint         minus_one = -1;
      logic   [127:0] big = 128'h1 << 100;
      logic   [  7:0] narrow = 8'd200;
      mark();
      case (kind)
         "unsigned_gt_signed": `hexk_check_gt(top, minus_one, "UT_ORDER")
         "signed_lt_unsigned": `hexk_check_lt(minus_one, top, "UT_ORDER")
         "signed_ge_unsigned": `hexk_check_ge(minus_one, top, "UT_ORDER")
         "range_64":           `hexk_check_in_range(top, minus_one, top, "UT_ORDER")
         "small_lt_big":       `hexk_check_lt(narrow, big, "UT_ORDER")
         default:              `hexk_check_gt(narrow, big, "UT_ORDER")
      endcase
      return outcome();
   endfunction : run_order_64

   // Compares arrays and a queue that hold the same elements under different index ranges.
   function automatic string run_q_eq_other_bounds(string kind);
      int from_zero[  2] = '{1, 2};
      int from_one [1:2] = '{1, 2};
      int downwards[2:1] = '{1, 2};
      int as_queue [  $] = '{1, 2};
      int other    [1:2] = '{1, 3};
      mark();
      case (kind)
         "shifted":   `hexk_check_q_eq(from_zero, from_one, "UT_Q_EQ")
         "downwards": `hexk_check_q_eq(from_zero, downwards, "UT_Q_EQ")
         "queue":     `hexk_check_q_eq(from_one, as_queue, "UT_Q_EQ")
         default:     `hexk_check_q_eq(from_one, other, "UT_Q_EQ")
      endcase
      return outcome();
   endfunction : run_q_eq_other_bounds

   // Returns value and counts the call in a variable of the module. VCS rejected such a call as
   // the first operand while the checks declared their copies with $bits() of the operand.
   function automatic int counted_value(int value);
      calls++;
      return value;
   endfunction : counted_value

   // Every check that compares bits, with a call of counted_value as its first operand.
   function automatic string module_function_operand();
      mark();
      calls = 0;
      `hexk_check_eq(counted_value(7), 7, "UT_OPERAND")
      `hexk_check_ne(counted_value(7), 8, "UT_OPERAND")
      `hexk_check_case_eq(counted_value(7), 7, "UT_OPERAND")
      `hexk_check_inside(counted_value(7), {[5 : 9]}, "UT_OPERAND")
      `hexk_check_mask(counted_value(7), 8'h0F, "UT_OPERAND")
      `hexk_check_aligned(counted_value(8), 4, "UT_OPERAND")
      return $sformatf("%0d calls, %0d failures", calls, hexk_check_stats::num_failed() - failed_before);
   endfunction : module_function_operand

   // Checks whose second operand has another width or signedness than the first, or is a fill literal.
   function automatic string run_widths(string kind);
      logic        [ 7:0] ones = 8'hFF;
      logic        [ 7:0] almost = 8'hFE;
      logic        [ 7:0] zero = 8'h00;
      logic        [15:0] wide_ones = 16'hFFFF;
      logic signed [ 7:0] minus_one = -8'sd1;
      mark();
      case (kind)
         "fill_ones":         `hexk_check_eq(ones, '1, "UT_WIDTH")
         "fill_ones_differs": `hexk_check_eq(almost, '1, "UT_WIDTH")
         "fill_zeros":        `hexk_check_eq(zero, '0, "UT_WIDTH")
         "signed_narrow":     `hexk_check_eq(wide_ones, minus_one, "UT_WIDTH")
         "unsigned_narrow":   `hexk_check_eq(wide_ones, ones, "UT_WIDTH")
         "wide_is_cut":       `hexk_check_eq(ones, 16'h01FF, "UT_WIDTH")
         "negative_first":    `hexk_check_eq(minus_one, 8'hFF, "UT_WIDTH")
         "mask_fill":         `hexk_check_mask(wide_ones, '1, "UT_WIDTH")
         default:             `hexk_check_mask(wide_ones, ones, "UT_WIDTH")
      endcase
      return outcome();
   endfunction : run_widths

   // Returns a value of 72 bits and counts the call in a variable of the module.
   function automatic logic [71:0] counted_wide();
      calls++;
      return 72'h01_0000_0000_0000_00F0;
   endfunction : counted_wide

   // Checks of bits on operands of 64, 65 and 72 bits: the widest that is copied into 64 bits, and
   // operands that are copied into the full check width.
   function automatic string run_two_paths(string kind);
      logic [63:0] word = '1;
      logic [64:0] above = {1'b1, 64'd0};
      logic [71:0] wide = 72'h01_0000_0000_0000_00F0;
      mark();
      calls = 0;
      case (kind)
         "word_eq":       `hexk_check_eq(word, '1, "UT_PATH")
         "word_ne":       `hexk_check_eq(word, 64'h7FFF_FFFF_FFFF_FFFF, "UT_PATH")
         "above_eq":      `hexk_check_eq(above, 65'h1_0000_0000_0000_0000, "UT_PATH")
         "above_ne":      `hexk_check_eq(above, 0, "UT_PATH")
         "wide_inside":   `hexk_check_inside(wide, {72'h01_0000_0000_0000_00F0}, "UT_PATH")
         "wide_outside":  `hexk_check_inside(wide, {1, 2}, "UT_PATH")
         "wide_mask":     `hexk_check_mask(wide, 72'hFF_FFFF_FFFF_FFFF_FFFF, "UT_PATH")
         "wide_unmasked": `hexk_check_mask(wide, 64'hFFFF_FFFF_FFFF_FFFF, "UT_PATH")
         "wide_aligned":  `hexk_check_aligned(wide, 16, "UT_PATH")
         "wide_skewed":   `hexk_check_aligned(wide, 32, "UT_PATH")
         default:         `hexk_check_eq(counted_wide(), 72'h01_0000_0000_0000_00F0, "UT_PATH")
      endcase
      return (kind == "wide_function") ? $sformatf("%s%0d calls", outcome(), calls) : outcome();
   endfunction : run_two_paths

   // An order check on a value with an X bit.
   function automatic string run_order_with_x();
      logic [3:0] with_x = 4'b1x01;
      mark();
      `hexk_check_lt(with_x, 15, "UT_ORDER")
      return outcome();
   endfunction : run_order_with_x

   // How often a function call that is an operand runs in a failing check of each kind.
   function automatic string function_operand_calls();
      mark();
      `hexk_check_eq(packet.read_count(), 8, "UT_ONCE")
      `hexk_check_lt(packet.read_count(), 7, "UT_ONCE")
      `hexk_check_in_range(packet.read_count(), 8, 9, "UT_ONCE")
      `hexk_check_inside(packet.read_count(), {1, 2}, "UT_ONCE")
      `hexk_check_mask(packet.read_count(), 4, "UT_ONCE")
      `hexk_check_aligned(packet.read_count(), 4, "UT_ONCE")
      return $sformatf("%0d calls, %0d failures", packet.reads, hexk_check_stats::num_failed() - failed_before);
   endfunction : function_operand_calls

   // Number of times the operands of one check are evaluated: "<passing check> <failing check>".
   function automatic string operand_evaluations();
      int unsigned passing;
      mark();
      hexk_ut_counter::evaluations = 0;
      `hexk_check_eq(hexk_ut_counter::value(7), hexk_ut_counter::value(7), "UT_ONCE")
      passing                      = hexk_ut_counter::evaluations;
      hexk_ut_counter::evaluations = 0;
      `hexk_check_eq(hexk_ut_counter::value(7), hexk_ut_counter::value(8), "UT_ONCE")
      return $sformatf("%0d %0d", passing, hexk_ut_counter::evaluations);
   endfunction : operand_evaluations

   // Number of times the message of one check is built: "<passing check> <failing check>".
   function automatic string message_evaluations();
      int unsigned passing;
      mark();
      calls = 0;
      `hexk_check(1, "UT_LAZY", counted_text("not needed"))
      passing = calls;
      calls   = 0;
      `hexk_check(0, "UT_LAZY", counted_text("needed"))
      return $sformatf("%0d %0d", passing, calls);
   endfunction : message_evaluations

   // A check as the only statement of an if without begin and end.
   function automatic string after_if(bit run_it);
      int one = 1;
      mark();
      if (run_it) `hexk_check_eq(one, 2, "UT_AFTER_IF")
      else last.text = "skipped";
      return last.text;
   endfunction : after_if

   // A check in a method of a component: "<outcome> by <reporter>".
   function automatic string in_component(int level);
      mark();
      component.check_level(level);
      return {outcome(), " by ", last.reporter};
   endfunction : in_component

   // Counts of hexk_check_stats for a fresh ID after two passes and one fail.
   function automatic string stats_of_id();
      int one = 1;
      int two = 2;
      hexk_check_stats::reset_for_test();
      mark();
      `hexk_check_eq(one, 1, "UT_STATS_A")
      `hexk_check_eq(two, 2, "UT_STATS_A")
      `hexk_check_eq(two, 3, "UT_STATS_A")
      `hexk_check(1, "UT_STATS_B", "")
      return $sformatf(
          "%0d %0d %0d %0d %0d",
          hexk_check_stats::num_passed(
              "UT_STATS_A"
          ),
          hexk_check_stats::num_failed(
              "UT_STATS_A"
          ),
          hexk_check_stats::num_passed(
              "UT_STATS_NONE"
          ),
          hexk_check_stats::num_checks(),
          hexk_check_stats::num_passed(
              "UT_STATS_B"
          )
      );
   endfunction : stats_of_id

   // Casts an object of the right or the wrong type.
   function automatic string run_cast(bit right_type);
      hexk_ut_item  item = new("item");
      hexk_ut_other other = new("other");
      uvm_object    source = other;
      hexk_ut_item  target;
      if (right_type) begin
         source = item;
      end
      mark();
      `hexk_cast_or_fatal(target, source, "UT_CAST")
      return {(target == null) ? "null " : "cast ", outcome()};
   endfunction : run_cast

   // Randomizes an object or a variable with one of the wrappers: "<value as wanted> <outcome>".
   function automatic string run_randomize(string which);
      hexk_ut_random         item = new("item");
      int unsigned           number = 1000;
      // Starts at 0 and is not 0 after a randomization, except once in 2**128 runs.
      bit            [127:0] wide = '0;
      bit                    as_wanted;
      mark();
      case (which)
         "object": begin
            `hexk_randomize_or_fatal(item, "UT_RANDOMIZE")
            as_wanted = item.value < 100;
         end
         "object_with": begin
            `hexk_randomize_with_or_fatal(item, "UT_RANDOMIZE", value inside {[10 : 19]};)
            as_wanted = item.value inside {[10 : 19]};
         end
         "object_impossible": begin
            `hexk_randomize_with_or_fatal(item, "UT_RANDOMIZE", value > 200;)
            as_wanted = 1;
         end
         "variable": begin
            `hexk_std_randomize_or_fatal(wide, "UT_RANDOMIZE")
            as_wanted = wide != 0;
         end
         "variable_with": begin
            `hexk_std_randomize_with_or_fatal(number, "UT_RANDOMIZE", number inside {[10 : 19]};)
            as_wanted = number inside {[10 : 19]};
         end
         default: begin
            `hexk_std_randomize_with_or_fatal(number, "UT_RANDOMIZE", number > 5; number < 3;)
            as_wanted = 1;
         end
      endcase
      return {as_wanted ? "yes " : "no ", outcome()};
   endfunction : run_randomize

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(check_reports_the_message_when_the_condition_fails)
      `FAIL_UNLESS_STR_EQUAL(run_check(1), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_check(0), "F E the condition does not hold")
   `SVTEST_END

   `SVTEST(check_eq_reports_actual_and_expected)
      `FAIL_UNLESS_STR_EQUAL(run_eq(5, 5), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_eq(4, 5), "F E act=0x4 exp=0x5 (expected act == exp)")
      `FAIL_UNLESS_STR_EQUAL(run_eq(4, 5, "beat count"), "F E beat count: act=0x4 exp=0x5 (expected act == exp)")
   `SVTEST_END

   `SVTEST(check_eq_keeps_the_full_width_of_the_operands)
      `FAIL_UNLESS_STR_EQUAL(run_eq_wide(72'h01_0000_0000_0000_0000, 72'h01_0000_0000_0000_0000), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_eq_wide(72'h01_0000_0000_0000_0000, 72'h02_0000_0000_0000_0000),
         "F E act=0x10000000000000000 exp=0x20000000000000000 (expected act == exp)")
   `SVTEST_END

   `SVTEST(relational_checks_compare_signed_values)
      `FAIL_UNLESS_STR_EQUAL(run_relation("ne", 4, 5), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_relation("ne", 5, 5), "F E act=0x5 exp=0x5 (expected act != exp)")
      `FAIL_UNLESS_STR_EQUAL(run_relation("lt", -1, 0), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_relation("lt", 5, 5), "F E act=0x5 exp=0x5 (expected act < exp)")
      `FAIL_UNLESS_STR_EQUAL(run_relation("le", 5, 5), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_relation("le", 6, 5), "F E act=0x6 exp=0x5 (expected act <= exp)")
      `FAIL_UNLESS_STR_EQUAL(run_relation("gt", 0, -1), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_relation("gt", 5, 5), "F E act=0x5 exp=0x5 (expected act > exp)")
      `FAIL_UNLESS_STR_EQUAL(run_relation("ge", 5, 5), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_relation("ge", 4, 5), "F E act=0x4 exp=0x5 (expected act >= exp)")
   `SVTEST_END

   `SVTEST(case_eq_accepts_matching_x_and_z_bits)
      `FAIL_UNLESS_STR_EQUAL(run_four_state(1, 4'b1x0z, 4'b1x0z), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_four_state(1, 4'b1001, 4'b1101), "F E act=0x9 exp=0xd (expected act === exp)")
   `SVTEST_END

   // Variables have two states on Verilator: an X is a 0 there, so these three tests would not show
   // the difference between == and ===. They are compiled, and run on four-state simulators.
`ifndef VERILATOR
   `SVTEST(eq_fails_on_x_bits_even_when_they_match)
      `FAIL_UNLESS_STR_EQUAL(run_four_state(0, 4'b1x0z, 4'b1x0z), "F E act=0xX exp=0xX (expected act == exp)")
   `SVTEST_END

   `SVTEST(an_order_check_fails_on_an_x_bit)
      `FAIL_UNLESS_STR_EQUAL(run_order_with_x(), "F E act=0xX exp=0xf (expected act < exp)")
   `SVTEST_END

   `SVTEST(case_eq_distinguishes_x_from_a_known_bit)
      `FAIL_UNLESS_STR_EQUAL(run_four_state(1, 4'b1x00, 4'b1100), "F E act=0xX exp=0xc (expected act === exp)")
   `SVTEST_END

   `SVTEST(case_eq_distinguishes_z_from_x)
      `FAIL_UNLESS_STR_EQUAL(run_four_state(1, 4'bzzzz, 4'bxxxx), "F E act=0xz exp=0xx (expected act === exp)")
      `FAIL_UNLESS_STR_EQUAL(run_four_state(1, 4'bzzzz, 4'bzzzz), "P - ")
   `SVTEST_END

   `SVTEST(check_q_eq_fails_on_an_x_or_z_bit_in_an_element)
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_four_state(4'b1x00, 4'b1100), "F E first difference at index 1: act=0xX exp=0xc")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_four_state(4'b1x00, 4'b1x00), "F E first difference at index 1: act=0xX exp=0xX")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_four_state(4'b110z, 4'b1100), "F E first difference at index 1: act=0xZ exp=0xc")
   `SVTEST_END
`endif

   `SVTEST(check_streq_compares_strings)
      `FAIL_UNLESS_STR_EQUAL(run_streq("abc", "abc"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_streq("abc", "abd"), "F E name: act=\"abc\" exp=\"abd\"")
      `FAIL_UNLESS_STR_EQUAL(run_streq("", "x"), "F E name: act=\"\" exp=\"x\"")
   `SVTEST_END

   `SVTEST(check_q_eq_reports_the_first_difference)
      `FAIL_UNLESS_STR_EQUAL(run_q_eq(4), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq(0), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq(4, 2), "F E first difference at index 2: act=0xff exp=0x12")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq(4, 0), "F E first difference at index 0: act=0xff exp=0x10")
   `SVTEST_END

   `SVTEST(check_q_eq_reports_a_size_difference)
      `FAIL_UNLESS_STR_EQUAL(run_q_eq(4, -1, 1), "F E size act=3 exp=4")
   `SVTEST_END

   `SVTEST(check_q_eq_compares_four_state_elements_without_x)
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_four_state(4'hC, 4'hC), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_four_state(4'hD, 4'hC), "F E first difference at index 1: act=0xd exp=0xc")
   `SVTEST_END

   `SVTEST(check_q_eq_finds_a_difference_at_a_negative_index)
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_negative_index(0), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_negative_index(1), "F E first difference at index -2: act=0x3 exp=0x1")
   `SVTEST_END

   `SVTEST(check_q_eq_compares_by_position_whatever_the_index_ranges)
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_other_bounds("shifted"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_other_bounds("downwards"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_other_bounds("queue"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_q_eq_other_bounds("differs"),
         "F E first difference at index 2: act=0x2 exp=0x3")
   `SVTEST_END

   `SVTEST(check_obj_eq_uses_compare)
      `FAIL_UNLESS_STR_EQUAL(run_obj_eq(7, 7), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_obj_eq(7, 8), "F E objects differ")
   `SVTEST_END

   `SVTEST(check_obj_eq_handles_null)
      `FAIL_UNLESS_STR_EQUAL(run_obj_eq(-1, -1), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_obj_eq(7, -1), "F E objects differ")
      `FAIL_UNLESS_STR_EQUAL(run_obj_eq(-1, 7), "F E objects differ")
   `SVTEST_END

   `SVTEST(check_in_range_has_inclusive_limits)
      `FAIL_UNLESS_STR_EQUAL(run_in_range(1, 1, 8), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_in_range(8, 1, 8), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_in_range(9, 1, 8), "F E val=0x9 is not in 0x1 to 0x8")
      `FAIL_UNLESS_STR_EQUAL(run_in_range(0, 1, 8), "F E val=0x0 is not in 0x1 to 0x8")
   `SVTEST_END

   `SVTEST(check_inside_tests_a_set_with_ranges)
      `FAIL_UNLESS_STR_EQUAL(run_inside(2), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_inside(12), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_inside(3), "F E val=0x3 is not in the set")
   `SVTEST_END

   `SVTEST(check_inside_compares_a_signed_value_as_signed)
      `FAIL_UNLESS_STR_EQUAL(run_inside_signed(-1, -2), "P - | P - ")
      `FAIL_UNLESS_STR_EQUAL(run_inside_signed(-3, 1),
         "F E val=0xfffffffd is not in the set| F E val=0x1 is not in the set")
      `FAIL_UNLESS_STR_EQUAL(run_inside_unsigned(32'hFFFF_FFFE), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_inside_unsigned(5), "F E val=0x5 is not in the set")
   `SVTEST_END

   `SVTEST(check_mask_reports_the_bits_outside_the_mask)
      `FAIL_UNLESS_STR_EQUAL(run_mask(16'h00A5, 16'h00FF), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_mask(16'h0000, 16'h0000), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_mask(16'h81A5, 16'h00FF), "F E val=0x81a5 has bits outside mask=0xff: 0x8100")
   `SVTEST_END

   `SVTEST(check_aligned_tests_for_a_multiple)
      `FAIL_UNLESS_STR_EQUAL(run_aligned(4096, 4096), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_aligned(0, 8), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_aligned(18, 8), "F E val=0x12 is not aligned to 0x8")
      `FAIL_UNLESS_STR_EQUAL(run_aligned(18, 0), "F E val=0x12 is not aligned to 0x0")
   `SVTEST_END

   `SVTEST(every_fatal_variant_reports_a_fatal)
      `FAIL_UNLESS_STR_EQUAL(run_fatal("check"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("eq"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("ne"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("lt"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("le"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("gt"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("ge"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("case_eq"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("streq"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("q_eq"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("obj_eq"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("in_range"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("inside"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("mask"), "F F")
      `FAIL_UNLESS_STR_EQUAL(run_fatal("aligned"), "F F")
   `SVTEST_END

   `SVTEST(operands_are_evaluated_once)
      `FAIL_UNLESS_STR_EQUAL(operand_evaluations(), "2 2")
   `SVTEST_END

   `SVTEST(a_function_call_as_operand_runs_once_in_every_kind_of_check)
      `FAIL_UNLESS_STR_EQUAL(function_operand_calls(), "6 calls, 6 failures")
   `SVTEST_END

   `SVTEST(a_member_of_an_object_can_be_an_operand)
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_eq"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_ne"), "F E act=0xa5 exp=0xa6 (expected act == exp)")
      `FAIL_UNLESS_STR_EQUAL(run_operand("expression"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_range"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_inside"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_mask"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_aligned"), "P - ")
   `SVTEST_END

   `SVTEST(a_signal_of_a_virtual_interface_can_be_an_operand)
      `FAIL_UNLESS_STR_EQUAL(run_operand("vif_eq"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("vif_case_eq"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("vif_lt"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("vif_ge"), "F E act=0xfb exp=0x0 (expected act >= exp)")
   `SVTEST_END

   `SVTEST(a_queue_and_an_array_of_an_object_can_be_compared)
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_queue"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_operand("member_array"),
         "F E first difference at index 2: act=0x3 exp=0x7")
   `SVTEST_END

   `SVTEST(order_checks_compare_numbers_whatever_the_types)
      `FAIL_UNLESS_STR_EQUAL(run_order("unsigned_lt_negative"), "F E act=0xc8 exp=0xff (expected act < exp)")
      `FAIL_UNLESS_STR_EQUAL(run_order("unsigned_gt_negative"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order("negative_lt_wide"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order("negative_ge_wide"), "F E act=0xff exp=0xffff (expected act >= exp)")
   `SVTEST_END

   `SVTEST(an_order_check_compares_an_operand_of_the_full_vector_width)
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("widest_gt"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("widest_range"),
         with_zeros("F E val=0x8", 255, " is not in 0x1 to 0x5"))
   `SVTEST_END

   `SVTEST(an_order_check_on_a_wider_operand_fails_and_says_so)
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_le"),
         "F E act has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_gt"),
         "F E act has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_range"),
         "F E val has 1101 bits and a check compares at most 1024: not compared")
   `SVTEST_END

   `SVTEST(an_order_check_on_a_wider_second_or_third_operand_fails_and_says_so)
      `FAIL_UNLESS_STR_EQUAL(run_wide_other_operand("exp"),
         "F E exp has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_wide_other_operand("lo"),
         "F E lo has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_wide_other_operand("hi"),
         "F E hi has 1101 bits and a check compares at most 1024: not compared")
   `SVTEST_END

   `SVTEST(an_order_check_on_64_bit_operands_keeps_sign_and_magnitude)
      `FAIL_UNLESS_STR_EQUAL(run_order_64("unsigned_gt_signed"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order_64("signed_lt_unsigned"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order_64("signed_ge_unsigned"),
         "F E act=0xffffffffffffffff exp=0xffffffffffffffff (expected act >= exp)")
      `FAIL_UNLESS_STR_EQUAL(run_order_64("range_64"), "P - ")
   `SVTEST_END

   `SVTEST(an_order_check_takes_the_width_of_its_widest_operand)
      `FAIL_UNLESS_STR_EQUAL(run_order_64("small_lt_big"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order_64("small_gt_big"),
         with_zeros("F E act=0xc8 exp=0x1", 25, " (expected act > exp)"))
   `SVTEST_END

   `SVTEST(a_check_of_bits_compares_an_operand_of_the_full_vector_width)
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("widest_eq"),
         with_zeros("F E act=0x8", 255, " exp=0x0 (expected act == exp)"))
   `SVTEST_END

   `SVTEST(a_check_of_bits_on_a_wider_operand_fails_and_says_so)
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_eq"),
         "F E act has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_ne"),
         "F E act has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_inside"),
         "F E val has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_mask"),
         "F E val has 1101 bits and a check compares at most 1024: not compared")
      `FAIL_UNLESS_STR_EQUAL(run_order_wide("too_wide_aligned"),
         "F E val has 1101 bits and a check compares at most 1024: not compared")
   `SVTEST_END

   `SVTEST(operands_of_up_to_64_bits_and_wider_ones_are_checked_alike)
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("word_eq"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("word_ne"),
         "F E act=0xffffffffffffffff exp=0x7fffffffffffffff (expected act == exp)")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("above_eq"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("above_ne"), "F E act=0x10000000000000000 exp=0x0 (expected act == exp)")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_inside"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_outside"), "F E val=0x100000000000000f0 is not in the set")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_mask"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_unmasked"),
         "F E val=0x100000000000000f0 has bits outside mask=0xffffffffffffffff: 0x10000000000000000")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_aligned"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_skewed"), "F E val=0x100000000000000f0 is not aligned to 0x20")
      `FAIL_UNLESS_STR_EQUAL(run_two_paths("wide_function"), "P - 1 calls")
   `SVTEST_END

   `SVTEST(a_module_function_with_a_side_effect_can_be_the_first_operand)
      `FAIL_UNLESS_STR_EQUAL(module_function_operand(), "6 calls, 0 failures")
   `SVTEST_END

   `SVTEST(the_second_operand_is_brought_to_the_width_of_the_first)
      `FAIL_UNLESS_STR_EQUAL(run_widths("fill_ones"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_widths("fill_ones_differs"), "F E act=0xfe exp=0xff (expected act == exp)")
      `FAIL_UNLESS_STR_EQUAL(run_widths("fill_zeros"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_widths("signed_narrow"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_widths("unsigned_narrow"), "F E act=0xffff exp=0xff (expected act == exp)")
      `FAIL_UNLESS_STR_EQUAL(run_widths("wide_is_cut"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_widths("negative_first"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_widths("mask_fill"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_widths("mask_narrow"), "F E val=0xffff has bits outside mask=0xff: 0xff00")
   `SVTEST_END

   `SVTEST(a_negative_number_is_printed_in_as_many_bits_as_it_needs)
      `FAIL_UNLESS_STR_EQUAL(run_order("negative_le_far_below"), "F E act=0xff exp=0xc18 (expected act <= exp)")
   `SVTEST_END

   `SVTEST(in_range_compares_numbers_whatever_the_types)
      `FAIL_UNLESS_STR_EQUAL(run_order("range_signed"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order("range_unsigned"), "P - ")
      `FAIL_UNLESS_STR_EQUAL(run_order("range_below"), "F E val=0xff is not in 0x0 to 0x5")
   `SVTEST_END

   `SVTEST(eq_compares_bits_so_a_signed_variable_can_hold_a_pattern)
      `FAIL_UNLESS_STR_EQUAL(run_order("pattern"), "P - ")
   `SVTEST_END

   `SVTEST(the_message_is_built_only_on_failure)
      `FAIL_UNLESS_STR_EQUAL(message_evaluations(), "0 1")
   `SVTEST_END

   `SVTEST(a_check_is_one_statement)
      `FAIL_UNLESS_STR_EQUAL(after_if(0), "skipped")
      `FAIL_UNLESS_STR_EQUAL(after_if(1), "act=0x1 exp=0x2 (expected act == exp)")
   `SVTEST_END

   `SVTEST(a_check_in_a_component_reports_through_the_component)
      `FAIL_UNLESS_STR_EQUAL(in_component(8), "P -  by ")
      `FAIL_UNLESS_STR_EQUAL(in_component(9),
         "F E fifo level: act=0x9 exp=0x8 (expected act <= exp) by ut_component")
   `SVTEST_END

   `SVTEST(checks_are_counted_per_id)
      `FAIL_UNLESS_STR_EQUAL(stats_of_id(), "2 1 0 4 1")
   `SVTEST_END

   `SVTEST(the_summary_lists_every_id)
      `FAIL_UNLESS_STR_EQUAL(stats_of_id(), "2 1 0 4 1")
      `FAIL_UNLESS_STR_EQUAL(hexk_check_stats::summary(),
         {"Checks executed: 3 passed, 1 failed\n",
          "        2 passed       1 failed  UT_STATS_A\n",
          "        1 passed       0 failed  UT_STATS_B"})
   `SVTEST_END

   `SVTEST(cast_or_fatal_reports_a_failed_cast)
      `FAIL_UNLESS_STR_EQUAL(run_cast(1), "cast ? - ")
      `FAIL_UNLESS_STR_EQUAL(run_cast(0), "null ? F cast failed: source to target")
   `SVTEST_END

   // Constrained randomization on Verilator needs an external SMT solver (z3) on the PATH.
   `SVTEST(randomize_or_fatal_is_quiet_when_randomization_succeeds)
      `FAIL_UNLESS_STR_EQUAL(run_randomize("object"), "yes ? - ")
      `FAIL_UNLESS_STR_EQUAL(run_randomize("object_with"), "yes ? - ")
      `FAIL_UNLESS_STR_EQUAL(run_randomize("variable"), "yes ? - ")
      `FAIL_UNLESS_STR_EQUAL(run_randomize("variable_with"), "yes ? - ")
   `SVTEST_END

   `SVTEST(randomize_or_fatal_reports_a_failed_randomization)
      `FAIL_UNLESS_STR_EQUAL(run_randomize("object_impossible"),
         "yes ? F randomization with constraints failed: item")
      `FAIL_UNLESS_STR_EQUAL(run_randomize("variable_impossible"),
         "yes ? F randomization with constraints failed: number")
   `SVTEST_END

   `SVTEST(an_expression_operand_is_evaluated_in_the_width_of_the_comparison)
      `FAIL_UNLESS_STR_EQUAL(run_gt_of_a_sum(32'sh7fff_ffff), "P - ")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_check_macros_unit_test
