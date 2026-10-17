// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_agent.sv
//
// Agent of the register bus: sequencer, driver and monitor, and the adapter that the register
// model uses. A small agent of the testbench, written the way a project writes one; the library
// has no bus agent, and hexk_csr_util works with any. Its cfg (hexk_ref_bus_agent_cfg) holds the
// mode, the bus and the wait of the driver for ack; the environment assigns it before the build
// phase. Passive, it has only its monitor and the adapter, and drives nothing.

`ifndef HEXK_REF_BUS_AGENT_SV
`define HEXK_REF_BUS_AGENT_SV

class hexk_ref_bus_agent extends uvm_agent;

   // The cfg; assigned by the environment before the build phase.
   hexk_ref_bus_agent_cfg                    cfg;

   // Sequencer and driver of an active agent; null in a passive one.
   uvm_sequencer #(hexk_ref_bus_item)        sqr;
   hexk_ref_bus_driver                       drv;

   // The monitor, and the adapter between bus items and register operations.
   hexk_ref_bus_monitor                      mon;
   hexk_ref_reg_adapter                      adapter;

   // The ports of the monitor, as handles of the agent (guide CMP-10): completed accesses and committed code words.
   uvm_analysis_port #(hexk_ref_bus_item)    ap;
   uvm_analysis_port #(hexk_ref_commit_item) commit_ap;

   `uvm_component_utils(hexk_ref_bus_agent)

   // Creates the agent.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: creates the parts and hands them the bus.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null || cfg.vif == null) begin
         `uvm_fatal("REF_BUS_VIF", "cfg or cfg.vif is null; the environment assigns both before the build phase")
         return;
      end
      mon     = hexk_ref_bus_monitor::type_id::create("mon", this);
      adapter = hexk_ref_reg_adapter::type_id::create("adapter", this);
      mon.vif = cfg.vif;
      if (get_is_active() == UVM_ACTIVE) begin
         sqr                 = uvm_sequencer#(hexk_ref_bus_item)::type_id::create("sqr", this);
         drv                 = hexk_ref_bus_driver::type_id::create("drv", this);
         drv.vif             = cfg.vif;
         drv.max_wait_cycles = cfg.max_wait_cycles;
      end
   endfunction : build_phase

   // UVM hook: the mode of the cfg.
   function uvm_active_passive_enum get_is_active();
      return cfg.is_active;
   endfunction : get_is_active

   // UVM callback: takes the ports of the monitor and connects the driver to the sequencer of an active agent.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      ap        = mon.ap;
      commit_ap = mon.commit_ap;
      if (get_is_active() == UVM_ACTIVE) begin
         drv.seq_item_port.connect(sqr.seq_item_export);
      end
   endfunction : connect_phase

endclass : hexk_ref_bus_agent

`endif  // HEXK_REF_BUS_AGENT_SV
