// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_agent.sv
//
// Valid/ready agent: one side of a data channel with a valid/ready handshake, or a passive
// observer of it.
// The parent creates the agent and assigns cfg, with the interface in it, before the build
// phase; without that the agent takes the cfg that uvm_config_db holds for it under "cfg".
// An initiator sends the items of the sequences that a test starts on sqr; a responder
// answers by itself and takes items only to set the timing of single transfers.
// Consumers connect to ap, which has one item per transfer, and to cycle_ap, which has one
// hexk_handshake_cycle_t per rising edge of the clock: the ports of the monitor, which the agent
// hands on from its build phase (guide rule CMP-10). With cfg.has_coverage the agent
// connects a hexk_handshake_coverage to cycle_ap; other coverage connects there too. The
// agent is a hexk_objectable: registered with hexk_objection_aggregator, it keeps a phase
// alive while a transfer waits.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-8 CMP-10 CFG-6 CFG-7 OBJ-2
//! @emits     HEXK_VALID_READY_CFG:fatal
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_AGENT_SV
`define HEXK_VALID_READY_AGENT_SV

class hexk_valid_ready_agent #(
    int DATA_WIDTH = 32
) extends uvm_agent implements hexk_objectable;

   // The cfg of the agent; assigned by the parent before the build phase, else taken from uvm_config_db.
   hexk_valid_ready_agent_cfg #(DATA_WIDTH)                 cfg;

   // Sequencer and driver; null in passive mode.
   uvm_sequencer #(hexk_valid_ready_item #(DATA_WIDTH))     sqr;
   hexk_valid_ready_driver #(DATA_WIDTH)                    drv;

   // The monitor.
   hexk_valid_ready_monitor #(DATA_WIDTH)                   mon;

   // The handshake coverage, a subscriber of cycle_ap; null when cfg.has_coverage is 0.
   hexk_handshake_coverage                                  cov;

   // One item per transfer, and one record per rising edge of the clock: the ports of the monitor, set in the build
   // phase, so a consumer connects to them in its connect phase.
   uvm_analysis_port #(hexk_valid_ready_item #(DATA_WIDTH)) ap;
   uvm_analysis_port #(hexk_handshake_cycle_t)              cycle_ap;

   `uvm_component_param_utils(hexk_valid_ready_agent#(DATA_WIDTH))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_valid_ready_agent";
   endfunction : get_type_name

   // Creates the agent; the children, and with the monitor the ports, come in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: checks the cfg and its interface, creates the monitor, the coverage and, in active mode, the rest.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // A cfg that the parent assigned comes first; a parent that cannot see the type of the agent sets it.
      if (cfg == null) begin
         void'(uvm_config_db#(hexk_valid_ready_agent_cfg#(DATA_WIDTH))::get(this, "", "cfg", cfg));
      end
      if (cfg == null) begin
         `uvm_fatal("HEXK_VALID_READY_CFG", {"cfg is null and uvm_config_db has none under \"cfg\"; the parent ",
                                             "assigns it or sets it there before the build phase"})
         return;
      end
      if (cfg.vif == null) begin
         `uvm_fatal("HEXK_VALID_READY_CFG", "cfg.vif is null; the parent assigns the interface before the build phase")
         return;
      end
      mon = hexk_valid_ready_monitor#(DATA_WIDTH)::type_id::create("mon", this);
      mon.cfg = cfg;
      ap = mon.ap;
      cycle_ap = mon.cycle_ap;
      if (cfg.has_coverage) begin
         cov = hexk_handshake_coverage::type_id::create("cov", this);
      end
      if (get_is_active() == UVM_ACTIVE) begin
         sqr     = uvm_sequencer#(hexk_valid_ready_item#(DATA_WIDTH))::type_id::create("sqr", this);
         drv     = hexk_valid_ready_driver#(DATA_WIDTH)::type_id::create("drv", this);
         drv.cfg = cfg;
      end
   endfunction : build_phase

   // UVM callback: connects the coverage to the records of the monitor, and the driver to the sequencer.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (cov != null) begin
         cycle_ap.connect(cov.analysis_export);
      end
      if (get_is_active() == UVM_ACTIVE) begin
         drv.seq_item_port.connect(sqr.seq_item_export);
      end
   endfunction : connect_phase

   // UVM callback: tells the interface which side this agent drives and whether its protocol assertions are on.
   function void start_of_simulation_phase(uvm_phase phase);
      super.start_of_simulation_phase(phase);
      if (get_is_active() == UVM_ACTIVE) begin
         cfg.vif.set_driver(cfg.role == HEXK_VALID_READY_INITIATOR, 1'b1);
      end
      cfg.vif.set_checks(cfg.has_checks);
   endfunction : start_of_simulation_phase

   // UVM hook: the mode of the cfg.
   function uvm_active_passive_enum get_is_active();
      return cfg.is_active;
   endfunction : get_is_active

   // hexk_objectable: 1 while the driver holds an item of a sequence (also during its delay), or while a transfer
   // is offered and not yet accepted. A responder that waits for traffic without an item is not busy.
   virtual function bit is_busy();
      return (drv != null && drv.holds_item()) || (mon != null && mon.num_waiting_cycles() != 0);
   endfunction : is_busy

   // hexk_objectable: whether the driver holds an item, and for how long the transfer has waited.
   virtual function string busy_reason();
      string held = "";
      if (drv != null && drv.holds_item()) begin
         held = "the driver holds an item; ";
      end
      return $sformatf(
          "%svalid has waited for ready for %0d clock cycles", held, (mon == null) ? 0 : mon.num_waiting_cycles()
      );
   endfunction : busy_reason

endclass : hexk_valid_ready_agent

`endif  // HEXK_VALID_READY_AGENT_SV
