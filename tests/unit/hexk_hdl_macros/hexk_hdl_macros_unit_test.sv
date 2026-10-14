// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_hdl_macros_unit_test.sv
//
// SVUnit tests of the HDL access macros.
// The module has a variable and a driven net that the macros reach by their path, which the
// module takes from %m. Each case is a task that uses a macro and lets a nanosecond pass, so
// that the test sees the signal after the access. The errors of the macros, and those that
// UVM reports itself for a path that it cannot find, are demoted and counted through a
// hexk_report_catcher. Results are compared as text (see tests/unit/README.md). Needs UVM
// with its DPI code and a simulation that gives access to the signals of this module: make
// test SIM=questa TEST=hexk_hdl_macros. Where UVM is compiled with UVM_HDL_NO_DPI, which
// is the case on Verilator, one test checks that every macro reports.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_hdl_macros_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;

   string                     name = "hexk_hdl_macros_ut";
   svunit_testcase            svunit_ut;

   hexk_report_catcher        catcher;

   // The signals that the macros reach by path: a variable, and a net with a driver.
   logic               [15:0] word;
   logic               [ 7:0] source;
   wire                [ 7:0] net;

   // Path of this module.
   string                     scope = $sformatf("%m");

   // What the last read returned.
   logic               [15:0] value;
   logic               [ 3:0] nibble;

   assign net = source;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^UT_HDL$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^UT_HDL$", UVM_FATAL, "", 0, -1, UVM_INFO);
      // What UVM reports itself: a path that it cannot find, and access that is compiled off.
      catcher.expect_msg("^UVM/DPI/HDL_", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^UVM_HDL_", UVM_FATAL, "", 0, -1, UVM_INFO);
      word   = 16'h0000;
      source = 8'h00;
      value  = 16'hFFFF;
      nibble = 4'hF;
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Path of a signal of this module.
   function automatic string path(string signal);
      return {scope, ".", signal};
   endfunction : path

   // "<errors> <fatals>" that the macros reported.
   function automatic string reported();
      return $sformatf("%0d %0d", catcher.get_count("^UT_HDL$", UVM_ERROR), catcher.get_count("^UT_HDL$", UVM_FATAL));
   endfunction : reported

   // Assigns the variable in the ordinary way.
   task automatic assign_word(logic [15:0] data);
      word = data;
      #1ns;
   endtask : assign_word

   // Changes what drives the net.
   task automatic drive_net(logic [7:0] data);
      source = data;
      #1ns;
   endtask : drive_net

   // Reads a signal of this module into value.
   task automatic read_signal(string signal);
      `hexk_hdl_read(path(signal), value, "UT_HDL")
      #1ns;
   endtask : read_signal

   // Reads the variable into a variable of four bits.
   task automatic read_word_into_nibble();
      `hexk_hdl_read(path("word"), nibble, "UT_HDL")
      #1ns;
   endtask : read_word_into_nibble

   task automatic deposit_signal(string signal, logic [15:0] data);
      `hexk_hdl_deposit(path(signal), data, "UT_HDL")
      #1ns;
   endtask : deposit_signal

   task automatic force_signal(string signal, logic [15:0] data);
      `hexk_hdl_force(path(signal), data, "UT_HDL")
      #1ns;
   endtask : force_signal

   task automatic release_signal(string signal);
      `hexk_hdl_release(path(signal), "UT_HDL")
      #1ns;
   endtask : release_signal

   task automatic check_signal(string signal);
      `hexk_hdl_check_path_or_fatal(path(signal), "UT_HDL")
      #1ns;
   endtask : check_signal

   // The variable, the net and the value of the last read in hexadecimal.
   function automatic string signals();
      return $sformatf("word=%h net=%h value=%h", word, net, value);
   endfunction : signals

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

`ifndef UVM_HDL_NO_DPI
   `SVTEST(read_returns_the_value_of_a_variable_and_of_a_net)
      assign_word(16'hBEEF);
      read_signal("word");
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=beef net=00 value=beef")
      drive_net(8'h5A);
      read_signal("net");
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=beef net=5a value=005a")
      `FAIL_UNLESS_STR_EQUAL(reported(), "0 0")
   `SVTEST_END

   `SVTEST(read_into_a_narrower_variable_keeps_the_low_bits)
      assign_word(16'hBEEF);
      read_word_into_nibble();
      `FAIL_UNLESS_STR_EQUAL($sformatf("%h", nibble), "f")
      assign_word(16'hBEE3);
      read_word_into_nibble();
      `FAIL_UNLESS_STR_EQUAL($sformatf("%h", nibble), "3")
      `FAIL_UNLESS_STR_EQUAL(reported(), "0 0")
   `SVTEST_END

   `SVTEST(read_of_a_wrong_path_is_an_error_and_leaves_the_variable)
      read_signal("no_such_signal");
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=0000 net=00 value=ffff")
      `FAIL_UNLESS_STR_EQUAL(reported(), "1 0")
   `SVTEST_END

   `SVTEST(deposit_sets_a_variable_until_the_next_assignment)
      deposit_signal("word", 16'h1234);
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=1234 net=00 value=ffff")
      assign_word(16'h0055);
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=0055 net=00 value=ffff")
      `FAIL_UNLESS_STR_EQUAL(reported(), "0 0")
   `SVTEST_END

   `SVTEST(force_holds_a_net_against_its_driver_until_the_release)
      drive_net(8'h11);
      force_signal("net", 16'h00EE);
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=0000 net=ee value=ffff")
      drive_net(8'h22);
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=0000 net=ee value=ffff")
      release_signal("net");
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=0000 net=22 value=ffff")
      `FAIL_UNLESS_STR_EQUAL(reported(), "0 0")
   `SVTEST_END

   `SVTEST(deposit_force_and_release_of_a_wrong_path_are_errors)
      deposit_signal("no_such_signal", 16'h0001);
      `FAIL_UNLESS_STR_EQUAL(reported(), "1 0")
      force_signal("no_such_signal", 16'h0001);
      `FAIL_UNLESS_STR_EQUAL(reported(), "2 0")
      release_signal("no_such_signal");
      `FAIL_UNLESS_STR_EQUAL(reported(), "3 0")
   `SVTEST_END

   `SVTEST(check_path_is_silent_for_a_signal_and_fatal_for_a_wrong_path)
      check_signal("word");
      check_signal("net");
      `FAIL_UNLESS_STR_EQUAL(reported(), "0 0")
      check_signal("no_such_signal");
      `FAIL_UNLESS_STR_EQUAL(reported(), "0 1")
   `SVTEST_END
`else
   `SVTEST(without_the_dpi_code_of_uvm_every_macro_reports)
      read_signal("word");
      deposit_signal("word", 16'h1234);
      force_signal("word", 16'h1234);
      release_signal("word");
      `FAIL_UNLESS_STR_EQUAL(reported(), "4 0")
      check_signal("word");
      `FAIL_UNLESS_STR_EQUAL(reported(), "4 1")
      `FAIL_UNLESS_STR_EQUAL(signals(), "word=0000 net=00 value=ffff")
   `SVTEST_END
`endif

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_hdl_macros_unit_test
