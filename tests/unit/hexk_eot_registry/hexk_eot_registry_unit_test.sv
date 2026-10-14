// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_eot_registry_unit_test.sv
//
// SVUnit tests of hexk_eot_registry and hexk_checkable.
// The UVM phases do not run in a unit test simulation, so the tests call check_phase of the
// registry themselves. The registered objects write their name into a log when they are
// checked, and one of them can report an error. That error is a real one and stays in the
// simulation log: the registry finds the objects that complained by the error count of the
// report server, which a demoted message would not change. A small report catcher keeps the
// text of the summary message of the registry.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_eot_registry.

`include "svunit_defines.svh"

module hexk_eot_registry_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_checkable;
   import hexk_uvm_pkg::hexk_eot_registry;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   // Names of the objects whose eot_check ran, in that order.
   string call_log;

   // Object that notes its check in call_log and reports an error when told to.
   class hexk_ut_checkable implements hexk_checkable;
      string label;
      bit    has_leftover;

      function new(string object_label);
         label = object_label;
      endfunction : new

      virtual function void eot_check();
         call_log = {call_log, label, " "};
         if (has_leftover) begin
            `uvm_error("UT_EOT_LEFTOVER", {label, " has a leftover"})
         end
      endfunction : eot_check
   endclass : hexk_ut_checkable

   // Keeps the text of the latest HEXK_EOT_CHECK message.
   class hexk_ut_summary_catcher extends uvm_report_catcher;
      string summary;

      function new(string catcher_name = "hexk_ut_summary_catcher");
         super.new(catcher_name);
      endfunction : new

      function action_e catch();
         if (get_id() == "HEXK_EOT_CHECK") begin
            summary = get_message();
         end
         return THROW;
      endfunction : catch
   endclass : hexk_ut_summary_catcher

   string                  name = "hexk_eot_registry_ut";
   svunit_testcase         svunit_ut;

   hexk_report_catcher     catcher;
   hexk_ut_summary_catcher summary_catcher;
   hexk_eot_registry       registry;
   hexk_ut_checkable       first;
   hexk_ut_checkable       second;
   hexk_ut_checkable       third;

   function automatic void build();
      svunit_ut       = new(name);
      catcher         = hexk_report_catcher::add_global();
      summary_catcher = new();
      uvm_report_cb::add(null, summary_catcher);
      registry = hexk_eot_registry::get();
      // The summary has verbosity UVM_MEDIUM; make sure it is issued whatever the default is.
      registry.set_report_verbosity_level(UVM_HIGH);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_EOT_REGISTER$", UVM_ERROR, "", 0, -1, UVM_INFO);
      hexk_eot_registry::reset_for_test();
      call_log                = "";
      summary_catcher.summary = "";
      first                   = new("first");
      second                  = new("second");
      third                   = new("third");
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_eot_registry::reset_for_test();
      catcher.clear();
   endtask : teardown

   // Registers the three objects in the order third, first, second.
   function automatic void register_all();
      registry.register(third, "third");
      registry.register(first, "first");
      registry.register(second, "second");
   endfunction : register_all

   // "same" when get() returns the registry that build() got.
   function automatic string get_again();
      return (hexk_eot_registry::get() == registry) ? "same" : "other";
   endfunction : get_again

   // Makes an object report an error in its check.
   function automatic void give_leftover(hexk_ut_checkable obj);
      obj.has_leftover = 1;
   endfunction : give_leftover

   // Number of HEXK_EOT_REGISTER errors in this test.
   function automatic string register_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_EOT_REGISTER$"));
   endfunction : register_errors

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(get_returns_the_one_registry)
      `FAIL_UNLESS_STR_EQUAL(get_again(), "same")
      `FAIL_UNLESS_STR_EQUAL(registry.get_name(), "eot_registry")
   `SVTEST_END

   `SVTEST(check_phase_checks_every_object_in_the_order_of_registration)
      register_all();
      `FAIL_UNLESS_STR_EQUAL(call_log, "")
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(call_log, "third first second ")
      `FAIL_UNLESS_STR_EQUAL(summary_catcher.summary, "3 objects checked, none reported an error")
   `SVTEST_END

   `SVTEST(a_registry_without_objects_checks_nothing_and_says_nothing)
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(call_log, "")
      `FAIL_UNLESS_STR_EQUAL(summary_catcher.summary, "")
   `SVTEST_END

   `SVTEST(the_summary_names_the_objects_that_reported_errors)
      register_all();
      give_leftover(third);
      give_leftover(second);
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(call_log, "third first second ")
      `FAIL_UNLESS_STR_EQUAL(summary_catcher.summary, "3 objects checked, 2 reported errors: third, second")
   `SVTEST_END

   `SVTEST(a_null_handle_is_an_error_and_is_not_registered)
      registry.register(null, "nothing");
      registry.register(first, "first");
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(register_errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(call_log, "first ")
   `SVTEST_END

   `SVTEST(a_second_registration_is_an_error_and_the_object_is_checked_once)
      registry.register(first, "first");
      registry.register(first, "first_again");
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(register_errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(call_log, "first ")
   `SVTEST_END

   `SVTEST(reset_for_test_forgets_the_objects_and_keeps_the_registry)
      register_all();
      hexk_eot_registry::reset_for_test();
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(call_log, "")
      `FAIL_UNLESS_STR_EQUAL(get_again(), "same")
      registry.register(second, "second");
      registry.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(call_log, "second ")
      `FAIL_UNLESS_STR_EQUAL(register_errors(), "0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_eot_registry_unit_test
