// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_wait_macros_unit_test.sv
//
// SVUnit tests of the wait macros and of hexk_wait_util.
// Each case is a task that starts a small scenario (a bit that becomes 1 after some time, an
// event, a slow statement), runs the wait under test and records one line in result: the
// time that passed in nanoseconds, what was reported (through a hexk_report_catcher that
// demotes the provoked errors and fatals), and scenario-specific facts. Results are compared
// as text (see tests/unit/README.md). Needs UVM. Runs on Verilator with UVM 2020:
// make test SIM=verilator TEST=hexk_wait_macros.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

// A scope whose time unit is a thousand times that of the test module, for the times in picoseconds.
module hexk_wait_macros_ut_us_scope;
   timeunit 1us; timeprecision 1ns;

   // `hexk_ps of 10ns and of 2.5us written in this scope: "<ps> <ps>".
   function automatic string conversions();
      return $sformatf("%0d %0d", `hexk_ps(10ns), `hexk_ps(2.5us));
   endfunction : conversions

   // A wait_or_timeout of `hexk_ps(2us) from this scope that times out, measured with now_ps():
   // "<picoseconds that passed> timed_out=<bit>".
   task automatic timed_wait(output string text);
      longint unsigned start_ps = hexk_uvm_pkg::hexk_wait_util::now_ps();
      bit              never;
      bit              timed_out;
      hexk_uvm_pkg::hexk_wait_util::wait_or_timeout(never, `hexk_ps(2us), timed_out);
      text = $sformatf("%0d timed_out=%0b", hexk_uvm_pkg::hexk_wait_util::now_ps() - start_ps, timed_out);
   endtask : timed_wait
endmodule : hexk_wait_macros_ut_us_scope

module hexk_wait_macros_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_wait_util;

   string              name = "hexk_wait_macros_ut";
   svunit_testcase     svunit_ut;

   hexk_report_catcher catcher;
   string              result;
   bit                 flag;
   logic               ready;
   bit                 sibling_done;
   bit                 body_done;
   event               pulse;
   realtime            start_time;
   int unsigned        scenario;

   hexk_wait_macros_ut_us_scope us_scope ();

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Starts a scenario: clears the state and makes flag 1 after set_after (never, if that is 0).
   task automatic start(realtime set_after);
      catcher.clear();
      catcher.expect_msg("^UT_", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^UT_", UVM_FATAL, "", 0, -1, UVM_INFO);
      flag         = 0;
      sibling_done = 0;
      body_done    = 0;
      start_time   = $realtime;
      scenario++;
      if (set_after > 0) begin
         fork
            begin
               // A scenario may end before its flag is set; the thread must then do nothing.
               automatic int unsigned mine = scenario;
               #(set_after);
               if (mine == scenario) begin
                  flag = 1;
                  ->pulse;
               end
            end
         join_none
      end
   endtask : start

   // `hexk_ps of 20ns and 1.5ns in this module (time unit 1ns): "<ps> <ps>".
   function automatic string conversions();
      return $sformatf("%0d %0d", `hexk_ps(20ns), `hexk_ps(1.5ns));
   endfunction : conversions

   // The wait of the scope with the time unit 1us, into result.
   task automatic wait_in_us_scope();
      us_scope.timed_wait(result);
   endtask : wait_in_us_scope

   // "<nanoseconds since start> <errors caught> <fatals caught>".
   function automatic string report_line();
      int elapsed = int'(($realtime - start_time) / 1ns);
      return $sformatf(
          "%0dns %0d %0d", elapsed, catcher.get_count("^UT_", UVM_ERROR), catcher.get_count("^UT_", UVM_FATAL)
      );
   endfunction : report_line

   // `hexk_wait_timeout on flag with a timeout of 20 ns.
   task automatic wait_for_flag(realtime set_after, bit already_set = 0);
      start(set_after);
      flag = already_set;
      `hexk_wait_timeout(flag, 20ns, "UT_WAIT")
      result = report_line();
   endtask : wait_for_flag

   // `hexk_wait_timeout on a four-state signal that starts as X and gets a value after set_after (never, if that is 0).
   task automatic wait_for_ready(realtime set_after, logic value);
      start(0);
      ready = 1'bx;
      if (set_after > 0) begin
         fork
            begin
               #(set_after);
               ready = value;
            end
         join_none
      end
      `hexk_wait_timeout(ready, 20ns, "UT_WAIT")
      result = report_line();
      // The thread that sets the signal must be over before the next scenario starts.
      #(set_after);
   endtask : wait_for_ready

   // `hexk_wait_timeout_fatal on flag with a timeout of 20 ns.
   task automatic wait_for_flag_fatal(realtime set_after);
      start(set_after);
      `hexk_wait_timeout_fatal(flag, 20ns, "UT_WAIT")
      result = report_line();
   endtask : wait_for_flag_fatal

   // A thread of the caller that ends after 50 ns must survive a wait that times out after 20 ns.
   task automatic sibling_survives(bit use_task);
      bit timed_out;
      start(0);
      fork
         begin
            #50ns;
            sibling_done = 1;
         end
      join_none
      if (use_task) begin
         hexk_wait_util::wait_or_timeout(flag, `hexk_ps(20ns), timed_out);
      end else begin
         `hexk_wait_timeout(flag, 20ns, "UT_WAIT")
      end
      #40ns;
      result = $sformatf("%s sibling_done=%0b", report_line(), sibling_done);
   endtask : sibling_survives

   // `hexk_spinwait around statements that take body_time, with a timeout of 30 ns.
   task automatic spin(realtime body_time);
      start(0);
      `hexk_spinwait(#(body_time); body_done = 1;, 30ns, "UT_SPIN")
      #50ns;
      result = $sformatf("%s body_done=%0b", report_line(), body_done);
   endtask : spin

   // A wait with a timeout inside the statements of a spinwait.
   task automatic nested(realtime set_after);
      start(set_after);
      `hexk_spinwait(`hexk_wait_timeout(flag, 20ns, "UT_INNER") body_done = 1;, 100ns, "UT_OUTER")
      result = $sformatf("%s body_done=%0b", report_line(), body_done);
   endtask : nested

   // hexk_wait_util::wait_or_timeout on flag with a timeout of 20 ns.
   task automatic util_wait(realtime set_after, bit already_set = 0, realtime timeout = 20ns);
      bit timed_out;
      start(set_after);
      flag = already_set;
      hexk_wait_util::wait_or_timeout(flag, `hexk_ps(timeout), timed_out);
      result = $sformatf("%s timed_out=%0b", report_line(), timed_out);
   endtask : util_wait

   // hexk_wait_util::wait_event_or_timeout on pulse with a timeout of 20 ns.
   task automatic util_wait_event(realtime trigger_after);
      bit timed_out;
      start(trigger_after);
      hexk_wait_util::wait_event_or_timeout(pulse, `hexk_ps(20ns), timed_out);
      result = $sformatf("%s timed_out=%0b", report_line(), timed_out);
   endtask : util_wait_event

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(wait_timeout_returns_when_the_condition_becomes_true)
      wait_for_flag(5ns);
      `FAIL_UNLESS_STR_EQUAL(result, "5ns 0 0")
      wait_for_flag(19ns);
      `FAIL_UNLESS_STR_EQUAL(result, "19ns 0 0")
   `SVTEST_END

   `SVTEST(wait_timeout_returns_at_once_when_the_condition_is_true)
      wait_for_flag(0, 1);
      `FAIL_UNLESS_STR_EQUAL(result, "0ns 0 0")
   `SVTEST_END

   `SVTEST(wait_timeout_reports_an_error_after_the_timeout)
      wait_for_flag(0);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 1 0")
      wait_for_flag(35ns);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 1 0")
   `SVTEST_END

   `SVTEST(wait_timeout_waits_for_a_signal_that_starts_unknown)
      wait_for_ready(5ns, 1'b1);
      `FAIL_UNLESS_STR_EQUAL(result, "5ns 0 0")
      wait_for_ready(5ns, 1'b0);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 1 0")
   `SVTEST_END

   // Variables have two states on Verilator: an X is a 0 there, and the timeout was always reported.
`ifndef VERILATOR
   `SVTEST(wait_timeout_reports_a_signal_that_stays_unknown)
      wait_for_ready(0, 1'bx);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 1 0")
   `SVTEST_END
`endif

   `SVTEST(wait_timeout_fatal_reports_a_fatal)
      wait_for_flag_fatal(5ns);
      `FAIL_UNLESS_STR_EQUAL(result, "5ns 0 0")
      wait_for_flag_fatal(0);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 0 1")
   `SVTEST_END

   `SVTEST(threads_of_the_caller_survive_a_timed_out_wait)
      sibling_survives(0);
      `FAIL_UNLESS_STR_EQUAL(result, "60ns 1 0 sibling_done=1")
   `SVTEST_END

   `SVTEST(spinwait_lets_the_statements_finish_in_time)
      spin(10ns);
      `FAIL_UNLESS_STR_EQUAL(result, "60ns 0 0 body_done=1")
   `SVTEST_END

   `SVTEST(spinwait_ends_the_statements_at_the_timeout)
      spin(45ns);
      `FAIL_UNLESS_STR_EQUAL(result, "80ns 1 0 body_done=0")
   `SVTEST_END

   `SVTEST(a_wait_inside_a_spinwait_times_out_on_its_own)
      nested(5ns);
      `FAIL_UNLESS_STR_EQUAL(result, "5ns 0 0 body_done=1")
      nested(0);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 1 0 body_done=1")
   `SVTEST_END

   `SVTEST(wait_or_timeout_tells_which_came_first)
      util_wait(5ns);
      `FAIL_UNLESS_STR_EQUAL(result, "5ns 0 0 timed_out=0")
      util_wait(0);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 0 0 timed_out=1")
      util_wait(35ns);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 0 0 timed_out=1")
   `SVTEST_END

   `SVTEST(wait_or_timeout_returns_at_once_when_the_flag_is_set)
      util_wait(0, 1);
      `FAIL_UNLESS_STR_EQUAL(result, "0ns 0 0 timed_out=0")
   `SVTEST_END

   `SVTEST(wait_or_timeout_with_a_timeout_of_zero_does_not_wait)
      util_wait(5ns, 0, 0);
      `FAIL_UNLESS_STR_EQUAL(result, "0ns 0 0 timed_out=1")
   `SVTEST_END

   `SVTEST(threads_of_the_caller_survive_wait_or_timeout)
      sibling_survives(1);
      `FAIL_UNLESS_STR_EQUAL(result, "60ns 0 0 sibling_done=1")
   `SVTEST_END

   `SVTEST(hexk_ps_gives_the_same_picoseconds_whatever_the_time_unit_of_the_caller)
      `FAIL_UNLESS_STR_EQUAL(conversions(), "20000 1500")
      `FAIL_UNLESS_STR_EQUAL(us_scope.conversions(), "10000 2500000")
   `SVTEST_END

   `SVTEST(a_timeout_in_picoseconds_lasts_as_long_from_a_scope_with_another_time_unit)
      wait_in_us_scope();
      `FAIL_UNLESS_STR_EQUAL(result, "2000000 timed_out=1")
   `SVTEST_END

   `SVTEST(wait_event_or_timeout_tells_which_came_first)
      util_wait_event(5ns);
      `FAIL_UNLESS_STR_EQUAL(result, "5ns 0 0 timed_out=0")
      util_wait_event(0);
      `FAIL_UNLESS_STR_EQUAL(result, "20ns 0 0 timed_out=1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_wait_macros_unit_test
