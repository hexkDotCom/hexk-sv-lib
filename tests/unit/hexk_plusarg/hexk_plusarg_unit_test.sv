// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_plusarg_unit_test.sv
//
// SVUnit tests of hexk_plusarg.
// The plusargs come from hexk_plusarg_unit_test.plusargs in this directory, which make test
// puts on the simulation command line. Every getter is checked for a present, an absent
// and a malformed plusarg; malformed values make the library call $error on purpose and the
// tests check that the default is returned. Results are compared as text (see
// tests/unit/README.md). Runs on Verilator: make test SIM=verilator TEST=hexk_plusarg.

`include "svunit_defines.svh"

module hexk_plusarg_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_plusarg;
   import hexk_core_pkg::hexk_str;

   localparam longint DEFAULT_INT = -999;
   localparam real DEFAULT_REAL = -9.5;

   string          name = "hexk_plusarg_ut";
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

   // "1" or "0" for a bit result.
   function automatic string bit_text(bit value);
      return value ? "1" : "0";
   endfunction : bit_text

   // get_int with DEFAULT_INT as default, as decimal text.
   function automatic string int_of(string plusarg);
      return $sformatf("%0d", hexk_plusarg::get_int(plusarg, DEFAULT_INT));
   endfunction : int_of

   // get_real with DEFAULT_REAL as default, with three decimals.
   function automatic string real_of(string plusarg);
      return $sformatf("%0.3f", hexk_plusarg::get_real(plusarg, DEFAULT_REAL));
   endfunction : real_of

   // get_bit with both defaults, as "<result for default 0><result for default 1>".
   function automatic string bit_of(string plusarg);
      return {bit_text(hexk_plusarg::get_bit(plusarg, 0)), bit_text(hexk_plusarg::get_bit(plusarg, 1))};
   endfunction : bit_of

   // get_list as "<count>:<field>|<field>...", starting from a queue that is not empty.
   function automatic string list_of(string plusarg, byte sep = ",");
      string values[$];
      values.push_back("stale");
      hexk_plusarg::get_list(plusarg, values, sep);
      return $sformatf("%0d:%s", values.size(), hexk_str::join_str(values, "|"));
   endfunction : list_of

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(has_sees_both_forms)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_flag")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_int")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_empty")), "1")
   `SVTEST_END

   `SVTEST(has_is_false_for_an_absent_plusarg)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_absent")), "0")
   `SVTEST_END

   `SVTEST(has_matches_the_whole_name)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_prefix")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_fla")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_plusarg::has("hexk_ut_prefix_longer")), "1")
   `SVTEST_END

   `SVTEST(get_int_reads_decimal_values)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_int"), "42")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_neg"), "-17")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_zero"), "0")
   `SVTEST_END

   `SVTEST(get_int_reads_prefixed_values)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_hex"), "31")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_bin"), "165")
   `SVTEST_END

   `SVTEST(get_int_reads_verilog_literals)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_vhex"), "255")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_sized"), "200")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_octal"), "15")
   `SVTEST_END

   `SVTEST(get_int_reads_a_full_64_bit_pattern)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_big"), "-1")
   `SVTEST_END

   `SVTEST(get_int_takes_a_decimal_number_only_inside_the_range_of_a_longint)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_max"), "9223372036854775807")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_min"), "-9223372036854775808")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_over"), "-999")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_under"), "-999")
   `SVTEST_END

   `SVTEST(get_int_returns_the_default_when_absent)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_absent"), "-999")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_prefix"), "-999")
   `SVTEST_END

   `SVTEST(get_int_returns_the_default_for_a_malformed_value)
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_bad_int"), "-999")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_too_big"), "-999")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_str"), "-999")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_flag"), "-999")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_empty"), "-999")
   `SVTEST_END

   `SVTEST(get_str_returns_the_value)
      `FAIL_UNLESS_STR_EQUAL(hexk_plusarg::get_str("hexk_ut_str", "dflt"), "hello_world")
      `FAIL_UNLESS_STR_EQUAL(hexk_plusarg::get_str("hexk_ut_int", "dflt"), "42")
      `FAIL_UNLESS_STR_EQUAL(hexk_plusarg::get_str("hexk_ut_empty", "dflt"), "")
   `SVTEST_END

   `SVTEST(get_str_returns_the_default_without_a_value)
      `FAIL_UNLESS_STR_EQUAL(hexk_plusarg::get_str("hexk_ut_absent", "dflt"), "dflt")
      `FAIL_UNLESS_STR_EQUAL(hexk_plusarg::get_str("hexk_ut_flag", "dflt"), "dflt")
   `SVTEST_END

   `SVTEST(get_bit_is_set_by_the_bare_form)
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_flag"), "11")
   `SVTEST_END

   `SVTEST(get_bit_reads_numbers_and_words)
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_zero"), "00")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_one"), "11")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_int"), "11")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_word"), "11")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_off"), "00")
   `SVTEST_END

   `SVTEST(get_bit_returns_the_default_when_absent_or_malformed)
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_absent"), "01")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_str"), "01")
   `SVTEST_END

   `SVTEST(get_real_reads_a_number)
      `FAIL_UNLESS_STR_EQUAL(real_of("hexk_ut_real"), "2.500")
      `FAIL_UNLESS_STR_EQUAL(real_of("hexk_ut_int"), "42.000")
      `FAIL_UNLESS_STR_EQUAL(real_of("hexk_ut_neg"), "-17.000")
   `SVTEST_END

   `SVTEST(get_real_returns_the_default_when_absent_or_malformed)
      `FAIL_UNLESS_STR_EQUAL(real_of("hexk_ut_absent"), "-9.500")
      `FAIL_UNLESS_STR_EQUAL(real_of("hexk_ut_bad_real"), "-9.500")
      `FAIL_UNLESS_STR_EQUAL(real_of("hexk_ut_flag"), "-9.500")
   `SVTEST_END

   `SVTEST(get_list_splits_the_value)
      `FAIL_UNLESS_STR_EQUAL(list_of("hexk_ut_list"), "4:a|b||c")
      `FAIL_UNLESS_STR_EQUAL(list_of("hexk_ut_colons", ":"), "2:x|y")
      `FAIL_UNLESS_STR_EQUAL(list_of("hexk_ut_str"), "1:hello_world")
   `SVTEST_END

   `SVTEST(get_list_is_empty_without_a_value)
      `FAIL_UNLESS_STR_EQUAL(list_of("hexk_ut_absent"), "0:")
      `FAIL_UNLESS_STR_EQUAL(list_of("hexk_ut_flag"), "0:")
      `FAIL_UNLESS_STR_EQUAL(list_of("hexk_ut_empty"), "0:")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_plusarg_unit_test
