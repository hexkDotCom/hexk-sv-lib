// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_watchdog_example.sv
//
// Minimal use of hexk_watchdog: a test whose stimulus stops making progress. The driver
// gives a heartbeat for every item it sends; after the fifth item it waits for a response
// that never comes. The global timeout of 100 us would end the test much later; the
// inactivity limit of 200 ns ends it 200 ns after the last heartbeat, with a fatal that
// names the busy scoreboard and the last heartbeat of the driver.
// Run it with +hexk_timeout=1us to see the global timeout from the command line.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_watchdog_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::hexk_watchdog;
   `include "uvm_macros.svh"

   // Scoreboard that waits for one response for ever.
   class hexk_example_scoreboard extends uvm_scoreboard implements hexk_objectable;
      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function bit is_busy();
         return 1;
      endfunction : is_busy

      virtual function string busy_reason();
         return "waiting for the response to item 5";
      endfunction : busy_reason
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator objections;
      hexk_watchdog             watchdog;
      hexk_example_scoreboard   scoreboard;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections = hexk_objection_aggregator::type_id::create("objections", this);
         watchdog   = hexk_watchdog::type_id::create("watchdog", this);
         scoreboard = hexk_example_scoreboard::type_id::create("scoreboard", this);
         objections.register(scoreboard, scoreboard.get_full_name());
         watchdog.aggregator          = objections;
         watchdog.global_timeout_ps   = `hexk_ps(100us);
         watchdog.inactivity_limit_ps = `hexk_ps(200ns);
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "stimulus");
         repeat (5) begin
            #20ns;
            watchdog.heartbeat("driver");
         end
         // The response never comes: without the watchdog the test would hang here.
         wait (0);
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_watchdog_example
