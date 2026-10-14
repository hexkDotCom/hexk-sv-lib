// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_once_unit_test.sv
//
// SVUnit tests of hexk_rand_once_guard and `hexk_rand_once_guard_decl.
// Two small cfg classes are guarded: one through the macro, one by hand with a
// pre_randomize() of its own. The error of the guard is demoted by a report catcher and
// counted; a second catcher keeps its text. The trap message is an info and is counted by
// the report server. hexk_rand_once_unit_test.plusargs names one object for the trap.
// The stack traces go to the log and are not checked; on Verilator there are none.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_rand_once.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_rand_once_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_rand_once_guard;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   // Cfg that is guarded through the macro.
   class hexk_ut_cfg extends uvm_object;
      rand int unsigned value;

      `hexk_rand_once_guard_decl

      function new(string object_name = "hexk_ut_cfg");
         super.new(object_name);
      endfunction : new
   endclass : hexk_ut_cfg

   // Cfg that has a pre_randomize() of its own and asks its guard there.
   class hexk_ut_manual_cfg extends uvm_object;
      rand int unsigned    value;
      int unsigned         pre_calls;
      hexk_rand_once_guard guard;

      function new(string object_name = "hexk_ut_manual_cfg");
         super.new(object_name);
         guard = new(this);
      endfunction : new

      function void pre_randomize();
         pre_calls++;
         guard.on_pre_randomize();
      endfunction : pre_randomize

      function void post_randomize();
         guard.on_post_randomize();
      endfunction : post_randomize
   endclass : hexk_ut_manual_cfg

   // Keeps the text of the latest HEXK_RAND_ONCE message.
   class hexk_ut_text_catcher extends uvm_report_catcher;
      string text;

      function new(string catcher_name = "hexk_ut_text_catcher");
         super.new(catcher_name);
      endfunction : new

      function action_e catch();
         if (get_id() == "HEXK_RAND_ONCE") begin
            text = get_message();
         end
         return THROW;
      endfunction : catch
   endclass : hexk_ut_text_catcher

   string               name = "hexk_rand_once_ut";
   svunit_testcase      svunit_ut;

   hexk_report_catcher  catcher;
   hexk_ut_text_catcher text_catcher;
   hexk_ut_cfg          cfg;
   hexk_ut_cfg          other_cfg;
   hexk_ut_cfg          trapped_cfg;
   hexk_ut_manual_cfg   manual_cfg;
   int                  traps_at_start;

   function automatic void build();
      svunit_ut    = new(name);
      catcher      = hexk_report_catcher::add_global();
      text_catcher = new();
      uvm_report_cb::add(null, text_catcher);
   endfunction : build

   task automatic setup();
      uvm_report_server server = uvm_report_server::get_server();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_RAND_ONCE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      cfg               = new("ut_top_cfg");
      other_cfg         = new("ut_other_cfg");
      trapped_cfg       = new("hexk_ut_trapped_cfg");
      manual_cfg        = new("ut_manual_cfg");
      text_catcher.text = "";
      traps_at_start    = server.get_id_count("HEXK_RAND_ONCE_TRAP");
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Randomizes an object of the macro-guarded class; "ok" when randomize() succeeded.
   function automatic string randomize_cfg(hexk_ut_cfg target);
      if (target.randomize() != 1) begin
         return "failed";
      end
      return "ok";
   endfunction : randomize_cfg

   // Randomizes an object of the macro-guarded class with a constraint that cannot hold.
   function automatic string randomize_cfg_in_vain(hexk_ut_cfg target);
      if (target.randomize() with {
             value > 5;
             value < 3;
          } != 1) begin
         return "failed";
      end
      return "ok";
   endfunction : randomize_cfg_in_vain

   // Randomizes the hand-guarded object; "ok" when randomize() succeeded.
   function automatic string randomize_manual();
      if (manual_cfg.randomize() != 1) begin
         return "failed";
      end
      return "ok";
   endfunction : randomize_manual

   // Number of errors of the guards in this test.
   function automatic string errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_RAND_ONCE$"));
   endfunction : errors

   // Number of trap messages in this test.
   function automatic string traps();
      uvm_report_server server = uvm_report_server::get_server();
      return $sformatf("%0d", server.get_id_count("HEXK_RAND_ONCE_TRAP") - traps_at_start);
   endfunction : traps

   // "0" or "1": whether the guard of an object has seen a randomization.
   function automatic string was_randomized(hexk_ut_cfg target);
      return $sformatf("%0d", target.rand_once.was_randomized());
   endfunction : was_randomized

   // The first two words of the latest error text, which are the name of the object and "is".
   function automatic string error_subject();
      string words[$];
      hexk_core_pkg::hexk_str::split(text_catcher.text, words, " ", 3);
      if (words.size() < 2) begin
         return "";
      end
      return {words[0], " ", words[1]};
   endfunction : error_subject

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(the_first_randomization_is_silent)
      `FAIL_UNLESS_STR_EQUAL(was_randomized(cfg), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(was_randomized(cfg), "1")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
   `SVTEST_END

   `SVTEST(a_second_randomization_is_an_error_that_names_the_object)
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(error_subject(), "ut_top_cfg is")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "2")
   `SVTEST_END

   `SVTEST(every_object_has_its_own_guard)
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(other_cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(other_cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(error_subject(), "ut_other_cfg is")
   `SVTEST_END

   `SVTEST(allow_rerandomize_allows_exactly_one_more_randomization)
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      cfg.rand_once.allow_rerandomize();
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
   `SVTEST_END

   `SVTEST(allow_rerandomize_before_the_first_randomization_is_kept_for_the_second)
      cfg.rand_once.allow_rerandomize();
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
   `SVTEST_END

   // Constrained randomization on Verilator needs an external SMT solver (z3) on the PATH.
   // On Verilator 5.046 post_randomize() runs also after a failed randomize(), so that a failed attempt counts there.
`ifndef VERILATOR
   `SVTEST(a_randomization_that_fails_does_not_count)
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg_in_vain(cfg), "failed")
      `FAIL_UNLESS_STR_EQUAL(was_randomized(cfg), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(was_randomized(cfg), "1")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
   `SVTEST_END

   `SVTEST(a_failed_rerandomization_does_not_use_up_its_allowance)
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(other_cfg), "ok")
      other_cfg.rand_once.allow_rerandomize();
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg_in_vain(other_cfg), "failed")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(other_cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(other_cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
   `SVTEST_END
`endif

   `SVTEST(a_class_with_its_own_pre_randomize_calls_the_guard_itself)
      `FAIL_UNLESS_STR_EQUAL(randomize_manual(), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_manual(), "ok")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(error_subject(), "ut_manual_cfg is")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", manual_cfg.pre_calls), "2")
   `SVTEST_END

   `SVTEST(the_trap_plusarg_reports_the_first_randomization_of_the_named_object)
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(traps(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(trapped_cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(traps(), "1")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(randomize_cfg(trapped_cfg), "ok")
      `FAIL_UNLESS_STR_EQUAL(traps(), "1")
      `FAIL_UNLESS_STR_EQUAL(errors(), "1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_rand_once_unit_test
