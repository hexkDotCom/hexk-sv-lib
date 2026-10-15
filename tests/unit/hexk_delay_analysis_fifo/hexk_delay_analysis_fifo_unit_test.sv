// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_analysis_fifo_unit_test.sv
//
// SVUnit tests of hexk_delay_analysis_fifo with int as the item type, and one test with a class
// of this module as the item type, whose time unit (1 ns) differs from that of the package.
// The UVM phases do not run in a unit test simulation, so each test starts run_phase of a
// fresh FIFO in a thread of its own and ends that thread in teardown. Items are written
// through an analysis port that is connected to the FIFO, as a monitor would write them.
// The tests look at what try_get() returns at different times. A clock for the tests of
// latency_cycles is an event that a thread triggers every 10 ns.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_delay_analysis_fifo.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_delay_analysis_fifo_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay_analysis_fifo;
   import hexk_uvm_pkg::hexk_report_catcher;

   // Item class of this module.
   class hexk_ut_fifo_item;
      int unsigned value;
   endclass : hexk_ut_fifo_item

   string                          name = "hexk_delay_analysis_fifo_ut";
   svunit_testcase                 svunit_ut;

   hexk_report_catcher             catcher;
   hexk_delay_analysis_fifo #(int) fifo;
   uvm_analysis_port #(int)        port;
   process                         fifo_process;
   process                         clock_process;
   process                         item_fifo_process;
   string                          item_counts;
   event                           clock_tick;
   int unsigned                    created;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   // Every test gets a fresh FIFO with a port connected to it; components cannot be deleted,
   // so each has its own name.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_DELAY_FIFO_CLOCK$", UVM_ERROR, "", 0, -1, UVM_INFO);
      created++;
      fifo = new($sformatf("ut_delay_fifo_%0d", created), null);
      port = new($sformatf("ut_delay_port_%0d", created), null);
      port.connect(fifo.analysis_export);
      port.resolve_bindings();
      fork
         begin
            fifo_process = process::self();
            fifo.run_phase(null);
         end
      join_none
      wait (fifo_process != null);
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      if (fifo_process != null) begin
         fifo_process.kill();
         fifo_process = null;
      end
      if (clock_process != null) begin
         clock_process.kill();
         clock_process = null;
      end
      if (item_fifo_process != null) begin
         item_fifo_process.kill();
         item_fifo_process = null;
      end
      catcher.clear();
   endtask : teardown

   // Sets the latency of the FIFO, given as a time of this module.
   function automatic void set_latency(realtime latency);
      fifo.latency_ps = `hexk_ps(latency);
   endfunction : set_latency

   // Sets the largest latency there is.
   function automatic void set_latency_max();
      fifo.latency_ps = '1;
   endfunction : set_latency_max

   // An item with the largest latency, then in the same time step and after a zero delay a flush and an item with a
   // latency of 10 ns.
   task automatic flush_behind_the_largest_latency();
      fifo.latency_ps = '1;
      port.write(21);
      #0ns;
      fifo.flush();
      fifo.latency_ps = `hexk_ps(10ns);
      port.write(22);
   endtask : flush_behind_the_largest_latency

   // Sets the latency of the FIFO in clock events.
   function automatic void set_latency_cycles(int unsigned cycles);
      fifo.latency_cycles = cycles;
   endfunction : set_latency_cycles

   // Gives the FIFO a clock that ticks every 10 ns, first 10 ns from now.
   task automatic start_clock();
      fifo.set_clock(clock_tick);
      fork
         begin
            clock_process = process::self();
            forever begin
               #10ns;
               ->clock_tick;
            end
         end
      join_none
      wait (clock_process != null);
   endtask : start_clock

   // Gives the FIFO the clock event without a thread that triggers it; the tests trigger it with the tasks below.
   // Time passes before it returns, so that the FIFO is waiting for the event when the first trigger comes.
   task automatic use_manual_clock();
      fifo.set_clock(clock_tick);
      #1ns;
   endtask : use_manual_clock

   // One clock event, then 1 ns.
   task automatic tick();
      ->clock_tick;
      #1ns;
   endtask : tick

   // A write and a clock event in one time step, the write first: the FIFO counts the event after the write.
   task automatic write_then_tick(int item);
      port.write(item);
      ->clock_tick;
      #1ns;
   endtask : write_then_tick

   // A clock event and a write in one time step, the event first: the write waits for the region of the
   // nonblocking assignments, so the FIFO has counted the event when the write comes. A zero delay is not
   // enough for that on Questa 2024.1.
   task automatic tick_then_write(int item);
      ->clock_tick;
      uvm_wait_for_nba_region();
      port.write(item);
      #1ns;
   endtask : tick_then_write

   // Stops the clock of start_clock().
   function automatic void stop_clock();
      clock_process.kill();
      clock_process = null;
   endfunction : stop_clock

   // Puts an item with the blocking put() of the FIFO, which must return at once.
   task automatic put_item(int item);
      fifo.put(item);
   endtask : put_item

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // Takes everything that is visible out of the FIFO: the values separated by blanks, "-" when there is none.
   function automatic string visible();
      string text;
      int    item;
      while (fifo.try_get(
          item
      )) begin
         text = {text, $sformatf("%0d ", item)};
      end
      return (text.len() == 0) ? "-" : text;
   endfunction : visible

   // "<number of items in flight> <is_busy>"; an item that is visible and not read keeps the FIFO busy.
   function automatic string in_flight();
      return $sformatf("%0d %0d", fifo.num_in_flight(), fifo.is_busy());
   endfunction : in_flight

   // A FIFO of items of a class of this module with a latency of 30 ns gets an item; gives the number of visible
   // items 29 ns and 31 ns later in item_counts, as "<count> <count>".
   task automatic latency_with_a_class_of_this_module();
      hexk_delay_analysis_fifo #(hexk_ut_fifo_item) item_fifo;
      hexk_ut_fifo_item                             item = new();
      item_fifo            = new($sformatf("ut_delay_item_fifo_%0d", created), null);
      item_fifo.latency_ps = `hexk_ps(30ns);
      fork
         begin
            item_fifo_process = process::self();
            item_fifo.run_phase(null);
         end
      join_none
      wait (item_fifo_process != null);
      void'(item_fifo.try_put(item));
      #29ns;
      item_counts = $sformatf("%0d", item_fifo.used());
      #2ns;
      item_counts = $sformatf("%s %0d", item_counts, item_fifo.used());
   endtask : latency_with_a_class_of_this_module

   // Number of HEXK_DELAY_FIFO_CLOCK errors in this test.
   function automatic string clock_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_DELAY_FIFO_CLOCK$"));
   endfunction : clock_errors

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(without_a_latency_an_item_is_visible_at_once)
      port.write(11);
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 1")
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 ")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
   `SVTEST_END

   `SVTEST(an_item_that_is_visible_and_not_read_keeps_the_fifo_busy)
      set_latency(100ps);
      port.write(5);
      advance(150ps);
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 1")
      `FAIL_UNLESS_STR_EQUAL(fifo.busy_reason(),
         "0 items are waiting for the end of their delay, 1 are visible and not yet read")
      `FAIL_UNLESS_STR_EQUAL(visible(), "5 ")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
   `SVTEST_END

   `SVTEST(an_item_becomes_visible_after_the_latency)
      set_latency(30ns);
      port.write(11);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "1 1")
      advance(29ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 ")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
   `SVTEST_END

   `SVTEST(every_item_has_the_latency_from_its_own_write)
      set_latency(30ns);
      port.write(1);
      advance(10ns);
      port.write(2);
      advance(10ns);
      port.write(3);
      advance(11ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "1 ")
      advance(10ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "2 ")
      advance(10ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "3 ")
   `SVTEST_END

   `SVTEST(items_written_at_the_same_time_keep_their_order)
      set_latency(20ns);
      port.write(5);
      port.write(6);
      port.write(7);
      advance(21ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "5 6 7 ")
   `SVTEST_END

   `SVTEST(a_shorter_latency_does_not_let_an_item_overtake)
      set_latency(50ns);
      port.write(1);
      set_latency(10ns);
      port.write(2);
      advance(20ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      advance(31ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "1 2 ")
   `SVTEST_END

   `SVTEST(an_item_without_latency_waits_behind_delayed_items)
      set_latency(30ns);
      port.write(1);
      set_latency(0);
      port.write(2);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      advance(31ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "1 2 ")
   `SVTEST_END

   `SVTEST(latency_cycles_counts_clock_events)
      set_latency_cycles(3);
      start_clock();
      advance(5ns);
      port.write(11);
      advance(20ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      advance(6ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 ")
   `SVTEST_END

   `SVTEST(the_largest_latency_in_cycles_does_not_wrap_to_an_early_one)
      set_latency_cycles(32'hFFFF_FFFF);
      use_manual_clock();
      tick();
      port.write(11);
      tick();
      tick();
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "1 1")
   `SVTEST_END

   `SVTEST(latency_cycles_is_used_instead_of_the_time)
      set_latency(1us);
      set_latency_cycles(1);
      start_clock();
      port.write(11);
      advance(11ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 ")
   `SVTEST_END

   `SVTEST(a_clock_event_in_the_time_step_of_the_write_does_not_count)
      set_latency_cycles(2);
      use_manual_clock();
      write_then_tick(11);
      tick();
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      tick();
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 ")
   `SVTEST_END

   `SVTEST(the_latency_in_cycles_is_the_same_when_the_clock_event_comes_first)
      set_latency_cycles(2);
      use_manual_clock();
      tick_then_write(11);
      tick();
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      tick();
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 ")
   `SVTEST_END

   `SVTEST(items_of_one_time_step_wait_for_the_same_clock_event)
      set_latency_cycles(1);
      use_manual_clock();
      port.write(1);
      tick_then_write(2);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      tick();
      `FAIL_UNLESS_STR_EQUAL(visible(), "1 2 ")
   `SVTEST_END

   `SVTEST(latency_cycles_without_a_clock_is_an_error_and_does_not_delay)
      set_latency_cycles(2);
      port.write(11);
      port.write(12);
      `FAIL_UNLESS_STR_EQUAL(clock_errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(visible(), "11 12 ")
   `SVTEST_END

   `SVTEST(flush_drops_the_items_in_flight_and_the_visible_ones)
      port.write(1);
      set_latency(30ns);
      port.write(2);
      port.write(3);
      fifo.flush();
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
      advance(40ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      port.write(4);
      advance(31ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "4 ")
   `SVTEST_END

   `SVTEST(an_item_written_after_a_flush_does_not_wait_for_a_dropped_item)
      set_latency(1us);
      port.write(1);
      advance(10ns);
      fifo.flush();
      set_latency(10ns);
      port.write(2);
      advance(9ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "2 ")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
   `SVTEST_END

   `SVTEST(a_flush_frees_the_fifo_from_a_clock_that_has_stopped)
      set_latency_cycles(2);
      start_clock();
      port.write(1);
      advance(11ns);
      stop_clock();
      fifo.flush();
      set_latency_cycles(0);
      set_latency(10ns);
      port.write(2);
      advance(11ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "2 ")
   `SVTEST_END

   `SVTEST(put_delays_an_item_like_write_and_keeps_the_order)
      set_latency(30ns);
      port.write(1);
      put_item(2);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "2 1")
      advance(31ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "1 2 ")
   `SVTEST_END

   `SVTEST(busy_reason_says_how_many_items_are_waiting)
      set_latency(30ns);
      port.write(1);
      port.write(2);
      `FAIL_UNLESS_STR_EQUAL(fifo.busy_reason(),
         "2 items are waiting for the end of their delay, 0 are visible and not yet read")
   `SVTEST_END

   `SVTEST(the_largest_latency_does_not_wrap_around)
      advance(5ns);
      set_latency_max();
      port.write(12);
      advance(100ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "-")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "1 1")
      fifo.flush();
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
   `SVTEST_END

   `SVTEST(a_flush_ends_the_wait_for_the_largest_latency)
      advance(5ns);
      flush_behind_the_largest_latency();
      advance(11ns);
      `FAIL_UNLESS_STR_EQUAL(visible(), "22 ")
      `FAIL_UNLESS_STR_EQUAL(in_flight(), "0 0")
   `SVTEST_END

   `SVTEST(the_latency_is_the_same_with_an_item_class_of_a_scope_with_another_time_unit)
      latency_with_a_class_of_this_module();
      `FAIL_UNLESS_STR_EQUAL(item_counts, "0 1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_delay_analysis_fifo_unit_test
