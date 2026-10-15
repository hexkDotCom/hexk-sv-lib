// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_example.sv
//
// Minimal use of hexk_valid_ready: a DUT with a valid/ready channel at its input and one at
// its output, here one register stage. An initiator agent sends random words into the DUT
// with random gaps; a responder agent takes them from its output with random back-pressure.
// A hexk_scoreboard compares what the two monitors saw, in order. The inputs of the DUT are
// connected to the channel signals of the interfaces, its outputs to their ext_ inputs.
// The scoreboard and the agent at the output hold the phase through the aggregator until
// the last word has left the DUT, or the scoreboard reports a word that is overdue; the test
// checks that every word was compared.
// Needs UVM, src/uvm/hexk_uvm.f and src/agents/hexk_valid_ready/hexk_valid_ready.f.

`include "hexk_macros.svh"

module hexk_valid_ready_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent_cfg;
   import hexk_valid_ready_pkg::hexk_valid_ready_item;
   import hexk_valid_ready_pkg::hexk_valid_ready_random_seq;
   import hexk_valid_ready_pkg::HEXK_VALID_READY_RESPONDER;
   `include "uvm_macros.svh"

   localparam int unsigned WIDTH = 16;
   localparam int unsigned NUM_WORDS = 8;

   bit clk;
   bit rst_n;

   always #5ns clk = !clk;

   initial begin
      #22ns;
      rst_n = 1'b1;
   end

   hexk_valid_ready_if #(
       .DATA_WIDTH(WIDTH)
   ) in_if (
       .clk  (clk),
       .rst_n(rst_n)
   );
   hexk_valid_ready_if #(
       .DATA_WIDTH(WIDTH)
   ) out_if (
       .clk  (clk),
       .rst_n(rst_n)
   );

   // The DUT: one register stage. It takes a word when it is empty or its word leaves in the same cycle.
   logic             full;
   logic [WIDTH-1:0] held;

   assign in_if.ext_ready  = !full || out_if.ready;
   assign out_if.ext_valid = full;
   assign out_if.ext_data  = held;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         full <= 1'b0;
      end else if (in_if.valid && in_if.ready) begin
         held <= in_if.data;
         full <= 1'b1;
      end else if (out_if.ready) begin
         full <= 1'b0;
      end
   end

   class hexk_example_test extends uvm_test;
      typedef hexk_valid_ready_item#(WIDTH) item_t;

      hexk_valid_ready_agent_cfg #(WIDTH) in_cfg;
      hexk_valid_ready_agent_cfg #(WIDTH) out_cfg;
      hexk_valid_ready_agent #(WIDTH)     in_agent;
      hexk_valid_ready_agent #(WIDTH)     out_agent;
      hexk_scoreboard_cfg                 sb_cfg;
      hexk_scoreboard #(item_t)           sb;
      hexk_objection_aggregator           objections;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         in_cfg  = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("in_cfg");
         out_cfg = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("out_cfg");
         `hexk_vif_get_or_fatal(hexk_valid_ready_if#(WIDTH), "in_vif", in_cfg.vif)
         `hexk_vif_get_or_fatal(hexk_valid_ready_if#(WIDTH), "out_vif", out_cfg.vif)
         out_cfg.role       = HEXK_VALID_READY_RESPONDER;
         in_agent           = hexk_valid_ready_agent#(WIDTH)::type_id::create("in_agent", this);
         in_agent.cfg       = in_cfg;
         out_agent          = hexk_valid_ready_agent#(WIDTH)::type_id::create("out_agent", this);
         out_agent.cfg      = out_cfg;
         objections         = hexk_objection_aggregator::type_id::create("objections", this);
         // A word that never leaves the DUT is an error after 1 us, instead of a run phase that never ends.
         sb_cfg             = hexk_scoreboard_cfg::type_id::create("sb_cfg");
         sb_cfg.max_wait_ps = `hexk_ps(1us);
         sb                 = hexk_scoreboard#(item_t)::type_id::create("sb", this);
         sb.cfg             = sb_cfg;
         sb.aggregator      = objections;
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         in_agent.ap.connect(sb.expected_export);
         out_agent.ap.connect(sb.actual_export);
         objections.register(out_agent, out_agent.get_full_name());
      endfunction : connect_phase

      task main_phase(uvm_phase phase);
         hexk_valid_ready_random_seq #(WIDTH) seq = hexk_valid_ready_random_seq#(WIDTH)::type_id::create("seq");
         super.main_phase(phase);
         phase.raise_objection(this, "stimulus");
         `hexk_randomize_with_or_fatal(seq, "EXAMPLE", num_items == NUM_WORDS;)
         seq.start(in_agent.sqr);
         `uvm_info("EXAMPLE", $sformatf("%0d words were sent by %0t", NUM_WORDS, $realtime), UVM_NONE)
         phase.drop_objection(this, "stimulus done");
      endtask : main_phase

      // An empty scoreboard reports nothing either: the test checks that every word it sent was compared.
      function void check_phase(uvm_phase phase);
         hexk_sb_stats stats = sb.get_stats();
         super.check_phase(phase);
         `hexk_check_eq(stats.matched, NUM_WORDS, "EXAMPLE_MATCHED")
      endfunction : check_phase
   endclass : hexk_example_test

   initial begin
      `hexk_vif_set(hexk_valid_ready_if#(WIDTH), "uvm_test_top", "in_vif", in_if)
      `hexk_vif_set(hexk_valid_ready_if#(WIDTH), "uvm_test_top", "out_vif", out_if)
      run_test("hexk_example_test");
   end

endmodule : hexk_valid_ready_example
