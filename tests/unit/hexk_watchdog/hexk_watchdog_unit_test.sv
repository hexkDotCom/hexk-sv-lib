// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_watchdog_unit_test.sv
//
// SVUnit tests of hexk_watchdog.
// The UVM phases do not run in a unit test simulation, so each test starts run_phase of a
// fresh watchdog in a thread of its own and ends that thread in teardown. The fatal of the
// watchdog is demoted to an info by a report catcher and counted, and a second catcher keeps
// its text, so that the simulation goes on after it. Times in the fatal are absolute; the
// tests build the expected text from the time at which they started.
// +hexk_timeout is not given to this simulation, which other suites share; the conversion
// of its value is tested through parse_timeout().
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_watchdog.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_watchdog_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_watchdog;
   `include "uvm_macros.svh"

   // Object that is always busy, for the report of busy objects.
   class hexk_ut_busy implements hexk_objectable;
      virtual function bit is_busy();
         return 1;
      endfunction : is_busy

      virtual function string busy_reason();
         return "2 items";
      endfunction : busy_reason
   endclass : hexk_ut_busy

   // Keeps the text of the latest HEXK_WATCHDOG message.
   class hexk_ut_text_catcher extends uvm_report_catcher;
      string text;

      function new(string catcher_name = "hexk_ut_text_catcher");
         super.new(catcher_name);
      endfunction : new

      function action_e catch();
         if (get_id() == "HEXK_WATCHDOG") begin
            text = get_message();
         end
         return THROW;
      endfunction : catch
   endclass : hexk_ut_text_catcher

   string                    name = "hexk_watchdog_ut";
   svunit_testcase           svunit_ut;

   hexk_report_catcher       catcher;
   hexk_ut_text_catcher      text_catcher;
   hexk_watchdog             watchdog;
   hexk_objection_aggregator aggregator;
   hexk_ut_busy              scoreboard;
   process                   watchdog_process;
   realtime                  start_time;
   int unsigned              created;

   function automatic void build();
      svunit_ut    = new(name);
      catcher      = hexk_report_catcher::add_global();
      text_catcher = new();
      uvm_report_cb::add(null, text_catcher);
   endfunction : build

   // Every test gets a fresh watchdog; components cannot be deleted, so each has its own name.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_WATCHDOG$", UVM_FATAL, "", 0, -1, UVM_INFO);
      created++;
      watchdog          = new($sformatf("ut_watchdog_%0d", created), null);
      text_catcher.text = "";
      start_time        = $realtime;
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      if (watchdog_process != null) begin
         watchdog_process.kill();
         watchdog_process = null;
      end
      catcher.clear();
   endtask : teardown

   // Sets the two limits of the watchdog, given as times of this module.
   function automatic void configure(realtime global_timeout, realtime inactivity_limit);
      watchdog.global_timeout_ps   = `hexk_ps(global_timeout);
      watchdog.inactivity_limit_ps = `hexk_ps(inactivity_limit);
   endfunction : configure

   // Sets the inactivity limit, given as a time of this module, through set_inactivity_limit().
   function automatic void set_limit(realtime limit);
      watchdog.set_inactivity_limit(`hexk_ps(limit));
   endfunction : set_limit

   // Sets the largest inactivity limit there is.
   function automatic void set_largest_limit();
      watchdog.set_inactivity_limit('1);
   endfunction : set_largest_limit

   // Starts run_phase of the watchdog as UVM would at the start of the run phase.
   task automatic start_watchdog();
      fork
         begin
            watchdog_process = process::self();
            watchdog.run_phase(null);
         end
      join_none
      // Lets the new thread start.
      wait (watchdog_process != null);
   endtask : start_watchdog

   // Gives the watchdog an aggregator with one busy object.
   function automatic void connect_aggregator();
      aggregator = new($sformatf("ut_watchdog_objections_%0d", created), null);
      scoreboard = new();
      aggregator.register(scoreboard, "sb");
      watchdog.aggregator = aggregator;
   endfunction : connect_aggregator

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // Number of watchdog fatals in this test.
   function automatic string fatals();
      return $sformatf("%0d", catcher.get_count("^HEXK_WATCHDOG$", UVM_FATAL));
   endfunction : fatals

   // The text of the latest watchdog fatal on one line, with " | " for every line break.
   function automatic string message();
      return hexk_str::replace(text_catcher.text, "\n", " | ");
   endfunction : message

   // The first line of the latest watchdog fatal.
   function automatic string first_line();
      string lines[$];
      hexk_str::split(text_catcher.text, lines, "\n");
      return (lines.size() == 0) ? "" : lines[0];
   endfunction : first_line

   // The time the test started plus offset, as the watchdog prints a time.
   function automatic string stamp(realtime offset);
      return $sformatf("%0.3fns", (start_time + offset) / 1ns);
   endfunction : stamp

   // The limits of a watchdog nobody configured, in nanoseconds, as "<global> <inactivity>".
   function automatic string default_limits();
      return $sformatf("%0d %0d", watchdog.global_timeout_ps / 1000, watchdog.inactivity_limit_ps / 1000);
   endfunction : default_limits

   // Result of parse_timeout as "<return value> <picoseconds>".
   function automatic string parsed(string text);
      longint unsigned timeout_ps;
      bit              ok = hexk_watchdog::parse_timeout(text, timeout_ps);
      return $sformatf("%0d %0d", ok, timeout_ps);
   endfunction : parsed

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(the_defaults_are_a_global_timeout_of_1ms_and_no_inactivity_limit)
      `FAIL_UNLESS_STR_EQUAL(default_limits(), "1000000 0")
   `SVTEST_END

   `SVTEST(the_global_timeout_fires_at_its_time)
      configure(100ns, 0);
      start_watchdog();
      advance(99ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
      `FAIL_UNLESS_STR_EQUAL(first_line(), "global timeout of 100.000ns reached")
   `SVTEST_END

   `SVTEST(a_global_timeout_of_zero_is_off)
      configure(0, 0);
      start_watchdog();
      advance(2us);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
   `SVTEST_END

   `SVTEST(heartbeats_do_not_stop_the_global_timeout)
      configure(100ns, 0);
      start_watchdog();
      advance(60ns);
      watchdog.heartbeat("driver");
      advance(41ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
   `SVTEST_END

   `SVTEST(without_a_heartbeat_the_inactivity_limit_counts_from_the_start)
      configure(0, 50ns);
      start_watchdog();
      advance(49ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
      `FAIL_UNLESS_STR_EQUAL(first_line(), "no heartbeat for 50.000ns")
   `SVTEST_END

   `SVTEST(heartbeats_keep_the_inactivity_limit_quiet)
      configure(0, 50ns);
      start_watchdog();
      advance(40ns);
      watchdog.heartbeat("driver");
      advance(40ns);
      watchdog.heartbeat("monitor");
      advance(40ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      advance(11ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
   `SVTEST_END

   `SVTEST(set_inactivity_limit_counts_from_the_call)
      configure(0, 50ns);
      start_watchdog();
      advance(40ns);
      set_limit(50ns);
      advance(40ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      advance(11ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
   `SVTEST_END

   `SVTEST(the_largest_inactivity_limit_does_not_wrap_around)
      configure(0, 50ns);
      start_watchdog();
      advance(40ns);
      set_largest_limit();
      advance(200ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      set_limit(30ns);
      advance(31ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
   `SVTEST_END

   `SVTEST(a_new_limit_set_while_the_watch_starts_is_not_lost)
      configure(0, 0);
      set_largest_limit();
      start_watchdog();
      set_limit(30ns);
      advance(31ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
   `SVTEST_END

   `SVTEST(the_inactivity_limit_can_be_switched_off_and_on_during_the_run)
      configure(0, 50ns);
      start_watchdog();
      advance(40ns);
      set_limit(0);
      advance(200ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      set_limit(30ns);
      advance(29ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "0")
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(fatals(), "1")
      `FAIL_UNLESS_STR_EQUAL(first_line(), "no heartbeat for 30.000ns")
   `SVTEST_END

   `SVTEST(the_fatal_lists_the_busy_objects_and_the_heartbeats)
      connect_aggregator();
      configure(0, 50ns);
      start_watchdog();
      advance(10ns);
      watchdog.heartbeat("driver");
      advance(10ns);
      watchdog.heartbeat("monitor");
      watchdog.heartbeat("driver");
      advance(51ns);
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"no heartbeat for 50.000ns | Busy objects: |   sb: busy: 2 items | Heartbeats: |   ",
          "driver: 2 heartbeats, last at ", stamp(20ns), ", 50.000ns ago |   ",
          "monitor: 1 heartbeats, last at ", stamp(20ns), ", 50.000ns ago"})
   `SVTEST_END

   `SVTEST(the_fatal_says_when_there_is_no_aggregator_and_no_heartbeat)
      configure(100ns, 0);
      start_watchdog();
      advance(101ns);
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"global timeout of 100.000ns reached | Busy objects: |   no objection aggregator is connected | ",
          "Heartbeats: |   no heartbeat was given"})
   `SVTEST_END

   `SVTEST(parse_timeout_reads_a_number_with_a_unit)
      `FAIL_UNLESS_STR_EQUAL(parsed("20ns"), "1 20000")
      `FAIL_UNLESS_STR_EQUAL(parsed("500us"), "1 500000000")
      `FAIL_UNLESS_STR_EQUAL(parsed("1.5ms"), "1 1500000000")
      `FAIL_UNLESS_STR_EQUAL(parsed("3s"), "1 3000000000000")
      `FAIL_UNLESS_STR_EQUAL(parsed("250ps"), "1 250")
      `FAIL_UNLESS_STR_EQUAL(parsed("5000fs"), "1 5")
      `FAIL_UNLESS_STR_EQUAL(parsed("1500fs"), "1 2")
      `FAIL_UNLESS_STR_EQUAL(parsed(".5ns"), "1 500")
      `FAIL_UNLESS_STR_EQUAL(parsed("1NS"), "1 1000")
      `FAIL_UNLESS_STR_EQUAL(parsed("0ps"), "1 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("9000000s"), "1 9000000000000000000")
   `SVTEST_END

   `SVTEST(parse_timeout_rejects_a_time_that_does_not_fit_or_rounds_to_zero)
      `FAIL_UNLESS_STR_EQUAL(parsed("18446744073709551616ps"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("9223372036854775808ps"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("10000000s"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("0.1ps"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("400fs"), "0 0")
   `SVTEST_END

   `SVTEST(parse_timeout_rejects_everything_else)
      `FAIL_UNLESS_STR_EQUAL(parsed(""), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("10"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("ms"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed(".ms"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("1.2.3ms"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("10 ns"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("10min"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("-5ns"), "0 0")
      `FAIL_UNLESS_STR_EQUAL(parsed("5ns5"), "0 0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_watchdog_unit_test
