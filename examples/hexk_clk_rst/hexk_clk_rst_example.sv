// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_example.sv
//
// Minimal use of hexk_clk_rst: a testbench whose clock and reset come from the agent. The
// DUT is a counter with a reset that is active low. The test gives the clock 200 MHz in the
// cfg, resets the DUT for three clock cycles in its reset phase, lets the counter run and
// halves the clock frequency in its main phase. A thread waits for the reset event of the
// status of the agent, as an env would to empty its scoreboards; the status also tells the
// clock that is being driven.
// Needs UVM, src/uvm/hexk_uvm.f and src/agents/hexk_clk_rst/hexk_clk_rst.f.

module hexk_clk_rst_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent_cfg;
   import hexk_clk_rst_pkg::hexk_clk_rst_reset_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_clock_seq;
   `include "uvm_macros.svh"

   localparam int unsigned RESET_CYCLES = 3;
   localparam int unsigned RUN_CYCLES = 10;
   localparam longint unsigned SLOW_PERIOD_PS = 10_000;

   hexk_clk_rst_if clk_rst_if ();

   // The DUT: counts clock cycles while it is not in reset.
   logic [7:0] count;

   always_ff @(posedge clk_rst_if.clk or negedge clk_rst_if.rst) begin
      if (!clk_rst_if.rst) begin
         count <= '0;
      end else begin
         count <= count + 8'd1;
      end
   end

   class hexk_example_test extends uvm_test;
      hexk_clk_rst_agent_cfg clk_rst_cfg;
      hexk_clk_rst_agent     clk_rst_agent;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         clk_rst_cfg = hexk_clk_rst_agent_cfg::type_id::create("clk_rst_cfg");
         if (!uvm_config_db#(virtual hexk_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst_cfg.vif)) begin
            `uvm_fatal("EXAMPLE", "no clk_rst_vif in the config database")
         end
         clk_rst_cfg.set_freq_mhz(200.0);
         clk_rst_agent     = hexk_clk_rst_agent::type_id::create("clk_rst_agent", this);
         clk_rst_agent.cfg = clk_rst_cfg;
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         forever begin
            clk_rst_agent.status.reset_asserted.wait_trigger();
            `uvm_info("EXAMPLE", "the reset is asserted: a scoreboard drops its items here", UVM_NONE)
         end
      endtask : run_phase

      task reset_phase(uvm_phase phase);
         hexk_clk_rst_reset_seq reset_seq = hexk_clk_rst_reset_seq::type_id::create("reset_seq");
         super.reset_phase(phase);
         phase.raise_objection(this, "reset");
         if (reset_seq.randomize() with {hold_cycles == RESET_CYCLES;} != 1) begin
            `uvm_fatal("EXAMPLE", "randomization of the reset sequence failed")
         end
         reset_seq.start(clk_rst_agent.sqr);
         `uvm_info("EXAMPLE", $sformatf("reset released at %0t, after %0d clock cycles", $realtime,
                                        clk_rst_agent.get_clk_count()), UVM_NONE)
         phase.drop_objection(this, "reset done");
      endtask : reset_phase

      task main_phase(uvm_phase phase);
         hexk_clk_rst_clock_seq clock_seq = hexk_clk_rst_clock_seq::type_id::create("clock_seq");
         super.main_phase(phase);
         phase.raise_objection(this, "stimulus");
         clk_rst_agent.wait_clks(RUN_CYCLES);
         `uvm_info("EXAMPLE", $sformatf("at %0t the counter is %0d", $realtime, count), UVM_NONE)
         if (clock_seq.randomize() with {period_ps == SLOW_PERIOD_PS;} != 1) begin
            `uvm_fatal("EXAMPLE", "randomization of the frequency sequence failed")
         end
         clock_seq.start(clk_rst_agent.sqr);
         clk_rst_agent.wait_clks(RUN_CYCLES);
         `uvm_info("EXAMPLE", $sformatf("at %0t, with %0.0f MHz, the counter is %0d", $realtime,
                                        clk_rst_agent.status.get_freq_mhz(), count), UVM_NONE)
         phase.drop_objection(this, "stimulus done");
      endtask : main_phase
   endclass : hexk_example_test

   initial begin
      uvm_config_db#(virtual hexk_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst_if);
      run_test("hexk_example_test");
   end

endmodule : hexk_clk_rst_example
