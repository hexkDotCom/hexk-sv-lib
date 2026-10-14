// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_enum_util_unit_test.sv
//
// SVUnit tests of hexk_enum_util.
// Three enum types cover the shapes that matter: one member only, sparse and negative
// values with a shared name prefix, and names that share no prefix. Results are compared
// as text through the helpers below (see tests/unit/README.md).
// Runs on Verilator: make test SIM=verilator TEST=hexk_enum_util.

`include "svunit_defines.svh"

module hexk_enum_util_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_enum_util;

   // Enum with a single member.
   typedef enum {HEXK_UT_SINGLE_ONLY} hexk_ut_single_e;

   // Enum with sparse and negative values; all names share a prefix.
   typedef enum int {
      HEXK_UT_MODE_IDLE = 0,
      HEXK_UT_MODE_RUN  = 5,
      HEXK_UT_MODE_STOP = -3,
      HEXK_UT_MODE_HOLD = 1000
   } hexk_ut_mode_e;

   // Enum whose names share no prefix (waived in tests/lint/hexk_style_check.waiver).
   typedef enum bit [7:0] {
      SEND  = 8'h01,
      SENT  = 8'h02,
      ABORT = 8'hFF
   } hexk_ut_plain_e;

   // The enum methods of Verilator 5.046 stop at 64 bits, so the wide enum and its test are left out there.
`ifndef VERILATOR
   // Enum wider than 64 bits; the low 64 bits of the second member are zero.
   typedef enum bit [64:0] {
      HEXK_UT_WIDE_ONE = 65'h0_0000_0000_0000_0001,
      HEXK_UT_WIDE_TOP = 65'h1_0000_0000_0000_0000
   } hexk_ut_wide_e;
`endif

   string          name = "hexk_enum_util_ut";
   svunit_testcase svunit_ut;

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // Decimal text of an int result.
   function automatic string int_text(int value);
      return $sformatf("%0d", value);
   endfunction : int_text

   // "1" or "0" for a bit result.
   function automatic string bit_text(bit value);
      return value ? "1" : "0";
   endfunction : bit_text

   // try_from_name on the mode enum as "<found>:<name of the returned value>".
   function automatic string mode_try(string text, bit ignore_case = 0);
      hexk_ut_mode_e value;
      bit found = hexk_enum_util#(hexk_ut_mode_e)::try_from_name(text, value, ignore_case);
      return {bit_text(found), ":", value.name()};
   endfunction : mode_try

   // from_name on the mode enum as the name of the returned value.
   function automatic string mode_from(string text);
      hexk_ut_mode_e value = hexk_enum_util#(hexk_ut_mode_e)::from_name(text);
      return value.name();
   endfunction : mode_from

   // all() on the mode enum as "<count>:<value>,<value>...".
   function automatic string mode_all();
      hexk_ut_mode_e values[$];
      string text;
      hexk_enum_util#(hexk_ut_mode_e)::all(values);
      foreach (values[i]) begin
         text = {text, (i == 0) ? "" : ",", $sformatf("%0d", values[i])};
      end
      return {int_text(values.size()), ":", text};
   endfunction : mode_all

   // to_map() on the mode enum as "<count>;<key>=<value>;..." with the keys in map order.
   function automatic string mode_map(bit strip_prefix);
      hexk_ut_mode_e map  [string];
      string         text;
      map["stale"] = HEXK_UT_MODE_RUN;
      hexk_enum_util#(hexk_ut_mode_e)::to_map(map, strip_prefix);
      text = int_text(map.size());
      foreach (map[key]) begin
         text = {text, ";", key, "=", $sformatf("%0d", map[key])};
      end
      return text;
   endfunction : mode_map

   // to_map() on the plain enum, same format as mode_map.
   function automatic string plain_map(bit strip_prefix);
      hexk_ut_plain_e map  [string];
      string          text;
      hexk_enum_util#(hexk_ut_plain_e)::to_map(map, strip_prefix);
      text = int_text(map.size());
      foreach (map[key]) begin
         text = {text, ";", key, "=", $sformatf("%0d", map[key])};
      end
      return text;
   endfunction : plain_map

`ifndef VERILATOR
   // to_map() on the wide enum with the values in hexadecimal, same format as mode_map.
   function automatic string wide_map();
      hexk_ut_wide_e map  [string];
      string         text;
      hexk_enum_util#(hexk_ut_wide_e)::to_map(map, 1);
      text = int_text(map.size());
      foreach (map[key]) begin
         text = {text, ";", key, "=", $sformatf("%0h", map[key])};
      end
      return text;
   endfunction : wide_map

   // name() of a value of the wide enum that is given as a number.
   function automatic string wide_name(bit [64:0] value);
      return hexk_enum_util#(hexk_ut_wide_e)::name(hexk_ut_wide_e'(value));
   endfunction : wide_name
`endif

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(name_returns_the_member_name)
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_mode_e)::name(HEXK_UT_MODE_RUN), "HEXK_UT_MODE_RUN")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_mode_e)::name(HEXK_UT_MODE_STOP), "HEXK_UT_MODE_STOP")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_single_e)::name(HEXK_UT_SINGLE_ONLY), "HEXK_UT_SINGLE_ONLY")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_plain_e)::name(ABORT), "ABORT")
   `SVTEST_END

   `SVTEST(name_of_a_value_outside_the_enum_is_empty)
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_mode_e)::name(hexk_ut_mode_e'(7)), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_plain_e)::name(hexk_ut_plain_e'(8'h00)), "")
   `SVTEST_END

   `SVTEST(try_from_name_finds_a_member_by_name)
      `FAIL_UNLESS_STR_EQUAL(mode_try("HEXK_UT_MODE_HOLD"), "1:HEXK_UT_MODE_HOLD")
      `FAIL_UNLESS_STR_EQUAL(mode_try("HEXK_UT_MODE_IDLE"), "1:HEXK_UT_MODE_IDLE")
   `SVTEST_END

   `SVTEST(try_from_name_returns_the_first_member_for_an_unknown_name)
      `FAIL_UNLESS_STR_EQUAL(mode_try("HEXK_UT_MODE_NONE"), "0:HEXK_UT_MODE_IDLE")
      `FAIL_UNLESS_STR_EQUAL(mode_try(""), "0:HEXK_UT_MODE_IDLE")
      `FAIL_UNLESS_STR_EQUAL(mode_try("MODE_RUN"), "0:HEXK_UT_MODE_IDLE")
   `SVTEST_END

   `SVTEST(try_from_name_ignores_case_only_on_request)
      `FAIL_UNLESS_STR_EQUAL(mode_try("hexk_ut_mode_run"), "0:HEXK_UT_MODE_IDLE")
      `FAIL_UNLESS_STR_EQUAL(mode_try("hexk_ut_mode_run", 1), "1:HEXK_UT_MODE_RUN")
      `FAIL_UNLESS_STR_EQUAL(mode_try("HEXK_UT_mode_Stop", 1), "1:HEXK_UT_MODE_STOP")
   `SVTEST_END

   `SVTEST(from_name_returns_the_member)
      `FAIL_UNLESS_STR_EQUAL(mode_from("HEXK_UT_MODE_STOP"), "HEXK_UT_MODE_STOP")
   `SVTEST_END

   `SVTEST(from_name_of_an_unknown_name_returns_the_first_member)
      `FAIL_UNLESS_STR_EQUAL(mode_from("HEXK_UT_MODE_NONE"), "HEXK_UT_MODE_IDLE")
   `SVTEST_END

   `SVTEST(is_member_tests_a_value)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_mode_e)::is_member(5)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_mode_e)::is_member(-3)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_mode_e)::is_member(1000)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_mode_e)::is_member(1)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_mode_e)::is_member(3)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_plain_e)::is_member(255)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_plain_e)::is_member(-1)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_single_e)::is_member(0)), "1")
   `SVTEST_END

   `SVTEST(num_counts_the_members)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_enum_util#(hexk_ut_mode_e)::num()), "4")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_enum_util#(hexk_ut_single_e)::num()), "1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_enum_util#(hexk_ut_plain_e)::num()), "3")
   `SVTEST_END

   `SVTEST(all_lists_the_members_in_declaration_order)
      `FAIL_UNLESS_STR_EQUAL(mode_all(), "4:0,5,-3,1000")
   `SVTEST_END

   `SVTEST(common_prefix_ends_at_an_underscore)
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_mode_e)::common_prefix(), "HEXK_UT_MODE_")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_single_e)::common_prefix(), "HEXK_UT_SINGLE_")
   `SVTEST_END

   `SVTEST(common_prefix_is_empty_without_a_shared_underscore)
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_plain_e)::common_prefix(), "")
   `SVTEST_END

`ifndef VERILATOR
   `SVTEST(an_enum_wider_than_64_bits_keeps_its_upper_bits)
      `FAIL_UNLESS_STR_EQUAL(wide_name(65'h1_0000_0000_0000_0000), "HEXK_UT_WIDE_TOP")
      `FAIL_UNLESS_STR_EQUAL(wide_name(65'h0), "")
      `FAIL_UNLESS_STR_EQUAL(wide_map(), "2;ONE=1;TOP=10000000000000000")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_wide_e)::is_member(0)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_enum_util#(hexk_ut_wide_e)::is_member(1)), "1")
   `SVTEST_END
`endif

   `SVTEST(to_map_holds_every_name_and_value)
      `FAIL_UNLESS_STR_EQUAL(mode_map(0),
         "4;HEXK_UT_MODE_HOLD=1000;HEXK_UT_MODE_IDLE=0;HEXK_UT_MODE_RUN=5;HEXK_UT_MODE_STOP=-3")
      `FAIL_UNLESS_STR_EQUAL(plain_map(0), "3;ABORT=255;SEND=1;SENT=2")
   `SVTEST_END

   `SVTEST(to_map_can_strip_the_common_prefix)
      `FAIL_UNLESS_STR_EQUAL(mode_map(1), "4;HOLD=1000;IDLE=0;RUN=5;STOP=-3")
      `FAIL_UNLESS_STR_EQUAL(plain_map(1), "3;ABORT=255;SEND=1;SENT=2")
   `SVTEST_END

   `SVTEST(to_list_str_joins_the_names)
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_plain_e)::to_list_str(), "SEND, SENT, ABORT")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_plain_e)::to_list_str("|"), "SEND|SENT|ABORT")
      `FAIL_UNLESS_STR_EQUAL(hexk_enum_util#(hexk_ut_single_e)::to_list_str(), "HEXK_UT_SINGLE_ONLY")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_enum_util_unit_test
