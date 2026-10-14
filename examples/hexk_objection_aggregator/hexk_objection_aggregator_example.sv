// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_objection_aggregator_example.sv
//
// Minimal use of hexk_objection_aggregator: a scoreboard that only says whether it is busy,
// and a test that raises one objection around its stimulus. The stimulus ends after 100 ns
// with two responses outstanding; they arrive at 250 ns. Without the aggregator the run
// phase would end at 100 ns. With it, the phase is held until the scoreboard is empty, and
// the log says who is waiting and for what. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_objection_aggregator_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   `include "uvm_macros.svh"

   // Scoreboard that counts outstanding responses; it never touches an objection itself.
   class hexk_example_scoreboard extends uvm_scoreboard implements hexk_objectable;
      local int unsigned outstanding;

      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      // The stimulus announces responses it expects.
      function void expect_responses(int unsigned count);
         outstanding += count;
      endfunction : expect_responses

      // The monitor delivers the responses; this example checks nothing else.
      function void all_responses_seen();
         outstanding = 0;
      endfunction : all_responses_seen

      virtual function bit is_busy();
         return outstanding != 0;
      endfunction : is_busy

      virtual function string busy_reason();
         return $sformatf("waiting for %0d responses", outstanding);
      endfunction : busy_reason
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator objections;
      hexk_example_scoreboard   scoreboard;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections = hexk_objection_aggregator::type_id::create("objections", this);
         scoreboard = hexk_example_scoreboard::type_id::create("scoreboard", this);
         objections.register(scoreboard, scoreboard.get_full_name());
         // The responses of this example come on a 10 ns grid.
         objections.poll_interval_ps = `hexk_ps(10ns);
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "stimulus");
         scoreboard.expect_responses(2);
         fork
            begin
               #250ns;
               scoreboard.all_responses_seen();
            end
         join_none
         #100ns;
         phase.drop_objection(this, "stimulus");
      endtask : run_phase

      function void report_phase(uvm_phase phase);
         super.report_phase(phase);
         `uvm_info("EXAMPLE", $sformatf("run phase ended at %0t", $realtime), UVM_NONE)
      endfunction : report_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_objection_aggregator_example
