// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_env.sv
//
// Environment of the smoke testbench: the clock and reset agent, an initiator at the input
// of the FIFO, a responder at its output, and a scoreboard that compares what went in with
// what comes out, in order.
// The parent assigns cfg, the objection aggregator and the watchdog before the build phase.
// The scoreboard and the two channel agents hold the phases through the aggregator while
// words are on their way; every word that leaves the FIFO is a heartbeat for the watchdog;
// a reset empties the scoreboard.

`ifndef HEXK_SMOKE_ENV_SV
`define HEXK_SMOKE_ENV_SV

class hexk_smoke_env extends uvm_env;

   // Assigned by the parent before the build phase.
   hexk_smoke_env_cfg                                  cfg;
   hexk_objection_aggregator                           aggregator;
   hexk_watchdog                                       watchdog;

   hexk_clk_rst_agent                                  clk_rst_agent;
   hexk_valid_ready_agent #(hexk_smoke_env_cfg::WIDTH) in_agent;
   hexk_valid_ready_agent #(hexk_smoke_env_cfg::WIDTH) out_agent;
   hexk_scoreboard #(hexk_smoke_item_t)                sb;
   hexk_smoke_heartbeat                                heartbeat;

   `uvm_component_utils(hexk_smoke_env)

   // Creates the environment; the children are created in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: creates the agents, the scoreboard and the heartbeat subscriber and hands the cfgs down.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null) begin
         `uvm_fatal("HEXK_SMOKE_CFG", "cfg is null; the parent assigns it before the build phase")
         return;
      end
      clk_rst_agent      = hexk_clk_rst_agent::type_id::create("clk_rst_agent", this);
      clk_rst_agent.cfg  = cfg.clk_rst_cfg;
      in_agent           = hexk_valid_ready_agent#(hexk_smoke_env_cfg::WIDTH)::type_id::create("in_agent", this);
      in_agent.cfg       = cfg.in_cfg;
      out_agent          = hexk_valid_ready_agent#(hexk_smoke_env_cfg::WIDTH)::type_id::create("out_agent", this);
      out_agent.cfg      = cfg.out_cfg;
      sb                 = hexk_scoreboard#(hexk_smoke_item_t)::type_id::create("sb", this);
      sb.cfg             = cfg.sb_cfg;
      sb.aggregator      = aggregator;
      heartbeat          = hexk_smoke_heartbeat::type_id::create("heartbeat", this);
      heartbeat.watchdog = watchdog;
   endfunction : build_phase

   // UVM callback: connects the monitors to the scoreboard and registers the channel agents with the aggregator.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      in_agent.ap.connect(sb.expected_export);
      out_agent.ap.connect(sb.actual_export);
      out_agent.ap.connect(heartbeat.analysis_export);
      if (aggregator != null) begin
         aggregator.register(in_agent, in_agent.get_full_name());
         aggregator.register(out_agent, out_agent.get_full_name());
      end
   endfunction : connect_phase

   // UVM callback: empties the scoreboard at every reset (guide rule CHK-6).
   task run_phase(uvm_phase phase);
      forever begin
         clk_rst_agent.status.reset_asserted.wait_trigger();
         sb.on_reset();
      end
   endtask : run_phase

endclass : hexk_smoke_env

`endif  // HEXK_SMOKE_ENV_SV
