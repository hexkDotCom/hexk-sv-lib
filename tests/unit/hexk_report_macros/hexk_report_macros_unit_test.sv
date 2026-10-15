// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_macros_unit_test.sv
//
// SVUnit tests of the static report macros.
// The macros are used where they are meant for: in functions of this module and in a static
// method of a class derived from uvm_component. A listener on hexk_report_server records what
// arrives (severity, ID, text, file, line); infos are checked through the counts of the
// server. The fatal is demoted by a hexk_report_catcher so that the run continues. Results
// are compared as text (see tests/unit/README.md). Needs UVM. Runs on Verilator with UVM 2020:
// make test SIM=verilator TEST=hexk_report_macros.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_report_macros_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_server;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_msg_listener;
   import hexk_core_pkg::hexk_str;

   // Listener that keeps a one-line description of the last message it was told about.
   class hexk_ut_last_message implements hexk_msg_listener;
      string text;
      virtual function void on_message(uvm_report_message msg);
         uvm_severity severity = msg.get_severity();
         text = $sformatf(
             "%s %s %s %s:%0d",
             severity.name(),
             msg.get_id(),
             msg.get_message(),
             hexk_str::basename(
                 msg.get_filename()
             ),
             msg.get_line()
         );
      endfunction : on_message
   endclass : hexk_ut_last_message

   // Component with a static method, where `uvm_error does not compile.
   class hexk_ut_component extends uvm_component;
      function new(string instance_name, uvm_component parent);
         super.new(instance_name, parent);
      endfunction : new

      static function void report_error(string what);
         `hexk_static_error("UT_STATIC_METHOD", what)
      endfunction : report_error
   endclass : hexk_ut_component

   string               name = "hexk_report_macros_ut";
   svunit_testcase      svunit_ut;

   hexk_report_server   server;
   hexk_report_catcher  catcher;
   hexk_ut_last_message last;

   function automatic void build();
      svunit_ut = new(name);
      // The UVM suites share one simulation: use the server that is installed, if any.
      server    = hexk_report_server::get_installed();
      if (server == null) begin
         server = hexk_report_server::install();
      end
      catcher = hexk_report_catcher::add_global();
      last    = new();
      server.add_listener(last);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      last.text = "";
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Reports an info with the macro and returns how many infos with that ID the server has counted.
   function automatic string info_count(string id, int verbosity);
      `hexk_static_info(id, "an info", verbosity)
      return $sformatf("%0d", server.get_count(id, UVM_INFO));
   endfunction : info_count

   // Reports a warning with the macro.
   function automatic void warn();
      `hexk_static_warning("UT_STATIC_WARNING", "a warning")
   endfunction : warn

   // Reports an error with the macro, after an if without begin and end.
   function automatic void complain(bit really);
      if (really) `hexk_static_error("UT_STATIC_ERROR", $sformatf("an error with a value %0d", 42))
      else last.text = "nothing reported";
   endfunction : complain

   // Reports a fatal with the macro.
   function automatic void give_up();
      `hexk_static_fatal("UT_STATIC_FATAL", "a fatal")
   endfunction : give_up

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(static_info_reports_at_an_enabled_verbosity)
      `FAIL_UNLESS_STR_EQUAL(info_count("UT_STATIC_INFO", UVM_NONE), "1")
      `FAIL_UNLESS_STR_EQUAL(info_count("UT_STATIC_INFO", UVM_MEDIUM), "2")
   `SVTEST_END

   `SVTEST(static_info_is_filtered_by_the_verbosity)
      `FAIL_UNLESS_STR_EQUAL(info_count("UT_STATIC_QUIET", UVM_HIGH), "0")
      `FAIL_UNLESS_STR_EQUAL(info_count("UT_STATIC_QUIET", UVM_DEBUG), "0")
   `SVTEST_END

   `SVTEST(static_warning_reports_a_warning_with_file_and_line)
      warn();
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip(last.text, "0123456789"),
         "UVM_WARNING UT_STATIC_WARNING a warning hexk_report_macros_unit_test.sv:")
   `SVTEST_END

   `SVTEST(static_error_reports_an_error)
      complain(1);
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip(last.text, "0123456789"),
         "UVM_ERROR UT_STATIC_ERROR an error with a value 42 hexk_report_macros_unit_test.sv:")
   `SVTEST_END

   `SVTEST(the_macro_is_one_statement)
      complain(0);
      `FAIL_UNLESS_STR_EQUAL(last.text, "nothing reported")
   `SVTEST_END

   `SVTEST(static_error_works_in_a_static_method_of_a_component)
      hexk_ut_component::report_error("from a static method");
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip(last.text, "0123456789"),
         "UVM_ERROR UT_STATIC_METHOD from a static method hexk_report_macros_unit_test.sv:")
   `SVTEST_END

   `SVTEST(static_fatal_reports_a_fatal_that_a_catcher_can_demote)
      catcher.expect_msg("^UT_STATIC_FATAL$", UVM_FATAL, "", 1, 1, UVM_WARNING);
      give_up();
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip(last.text, "0123456789"),
         "UVM_WARNING UT_STATIC_FATAL a fatal hexk_report_macros_unit_test.sv:")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", catcher.get_count("^UT_STATIC_FATAL$", UVM_FATAL)), "1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_report_macros_unit_test
