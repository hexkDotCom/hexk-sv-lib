// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_agent.sv
//
// Clock and reset agent: one clock and one reset of a testbench, changed from sequences and
// watched by a monitor.
// The parent creates the agent and assigns cfg, with the interface in it, before the build
// phase; without that the agent takes the cfg that uvm_config_db holds for it under "cfg".
// A test starts the sequences of the package on sqr; consumers connect to ap or wait for the
// events of status, which also holds the clock that is being driven; the cfg is only read.
// In passive mode the agent has the monitor only and the interface follows a clock and a
// reset of the DUT. The agent is a hexk_clk_countable: give it to a component that counts
// or waits for clock cycles.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-8 CMP-10 CFG-6 CFG-7
//! @emits     HEXK_CLK_RST_CFG:fatal
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_AGENT_SV
`define HEXK_CLK_RST_AGENT_SV

class hexk_clk_rst_agent extends uvm_agent implements hexk_clk_countable;

   // The cfg of the agent; assigned by the parent before the build phase, else taken from uvm_config_db.
   hexk_clk_rst_agent_cfg                 cfg;

   // Sequencer and driver; null in passive mode.
   uvm_sequencer #(hexk_clk_rst_item)     sqr;
   hexk_clk_rst_driver                    drv;

   // The monitor.
   hexk_clk_rst_monitor                   mon;

   // One item per assertion and per release of the reset; the monitor writes to it.
   uvm_analysis_port #(hexk_clk_rst_item) ap;

   // The reset and the clock during the run; created with the agent, so it is there before the build phase.
   hexk_clk_rst_status                    status;

   `uvm_component_utils(hexk_clk_rst_agent)

   // Creates the agent, its port and its status; the children are created in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      ap     = new("ap", this);
      status = hexk_clk_rst_status::type_id::create("status");
   endfunction : new

   // UVM callback: checks the cfg and its interface, creates the monitor and, in active mode, sequencer and driver.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // A cfg that the parent assigned comes first; a parent that cannot see the type of the agent sets it.
      if (cfg == null) begin
         void'(uvm_config_db#(hexk_clk_rst_agent_cfg)::get(this, "", "cfg", cfg));
      end
      if (cfg == null) begin
         `uvm_fatal("HEXK_CLK_RST_CFG", {"cfg is null and uvm_config_db has none under \"cfg\"; the parent ",
                                         "assigns it or sets it there before the build phase"})
         return;
      end
      if (cfg.vif == null) begin
         `uvm_fatal("HEXK_CLK_RST_CFG", "cfg.vif is null; the parent assigns the interface before the build phase")
         return;
      end
      status.set_clock(cfg.period_ps, cfg.duty_percent, cfg.jitter_ps);
      mon        = hexk_clk_rst_monitor::type_id::create("mon", this);
      mon.cfg    = cfg;
      mon.status = status;
      if (get_is_active() == UVM_ACTIVE) begin
         sqr        = uvm_sequencer#(hexk_clk_rst_item)::type_id::create("sqr", this);
         drv        = hexk_clk_rst_driver::type_id::create("drv", this);
         drv.cfg    = cfg;
         drv.status = status;
      end
   endfunction : build_phase

   // UVM callback: connects the driver to the sequencer and the port of the monitor to the port of the agent.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      mon.ap.connect(ap);
      if (get_is_active() == UVM_ACTIVE) begin
         drv.seq_item_port.connect(sqr.seq_item_export);
      end
   endfunction : connect_phase

   // UVM callback: tells the interface the mode, the active level of the reset and the seed of the jitter.
   function void start_of_simulation_phase(uvm_phase phase);
      int unsigned seed = cfg.jitter_seed;
      super.start_of_simulation_phase(phase);
      if (seed == 0) begin
         seed = uvm_create_random_seed("hexk_clk_rst_agent", get_full_name());
      end
      cfg.vif.configure(get_is_active() == UVM_PASSIVE, cfg.rst_active_low, seed);
   endfunction : start_of_simulation_phase

   // UVM hook: the mode of the cfg.
   virtual function uvm_active_passive_enum get_is_active();
      return cfg.is_active;
   endfunction : get_is_active

   // hexk_clk_countable: number of rising edges of the clock so far.
   virtual function longint unsigned get_clk_count();
      return cfg.vif.get_clk_count();
   endfunction : get_clk_count

   // hexk_clk_countable: waits for n rising edges of the clock; returns at once when n is 0.
   virtual task wait_clks(int unsigned n);
      cfg.vif.wait_clks(n);
   endtask : wait_clks

endclass : hexk_clk_rst_agent

`endif  // HEXK_CLK_RST_AGENT_SV
