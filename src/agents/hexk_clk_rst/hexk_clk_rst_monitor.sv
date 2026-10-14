// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_monitor.sv
//
// Monitor of the clock and reset agent: tells the testbench when the reset is asserted and
// when it is released.
// Every such change is one item on the analysis port ap and one trigger of the event
// reset_asserted or reset_released of the status of the agent, with the item as data, which
// also says in in_reset whether the reset is asserted. Scoreboards and
// models subscribe to drop what they hold when the reset comes (guide rule CHK-6). The
// monitor watches the pin itself, not the clock: a reset may change between clock edges
// and while the clock is stopped. It is created by hexk_clk_rst_agent in both modes.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-5 CMP-12 CHK-6
//! @emits     HEXK_CLK_RST_RESET:info
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_MONITOR_SV
`define HEXK_CLK_RST_MONITOR_SV

class hexk_clk_rst_monitor extends uvm_monitor;

   // The cfg and the status of the agent; assigned by the agent before the connect phase.
   hexk_clk_rst_agent_cfg                 cfg;
   hexk_clk_rst_status                    status;

   // One item per assertion and per release of the reset.
   uvm_analysis_port #(hexk_clk_rst_item) ap;

   local virtual hexk_clk_rst_if          vif;

   `uvm_component_utils(hexk_clk_rst_monitor)

   // Creates the monitor and its port.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
   endfunction : new

   // UVM callback: takes the interface from the cfg; the agent has checked both.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vif = cfg.vif;
   endfunction : connect_phase

   // UVM callback: reports every change of the reset between asserted and released.
   // A reset that is asserted at the start is reported; a pin without a level is neither and changes nothing.
   task run_phase(uvm_phase phase);
      bit was_active = 0;
      bit is_active;
      forever begin
         if (vif.get_reset(is_active) && is_active != was_active) begin
            was_active = is_active;
            publish(is_active);
         end
         vif.wait_reset_change();
      end
   endtask : run_phase

   // Writes the item of a change to the port, updates the status, triggers its event and reports the change.
   local function void publish(bit reset_active);
      hexk_clk_rst_item item = hexk_clk_rst_item::type_id::create("item");
      item.op           = HEXK_CLK_RST_RESET;
      item.reset_active = reset_active;
      item.clk_count    = vif.get_clk_count();
      status.in_reset   = reset_active;
      ap.write(item);
      if (reset_active) begin
         status.reset_asserted.trigger(item);
      end else begin
         status.reset_released.trigger(item);
      end
      `uvm_info("HEXK_CLK_RST_RESET", $sformatf(
                "reset %s at clock count %0d", reset_active ? "asserted" : "released", item.clk_count), UVM_MEDIUM)
   endfunction : publish

endclass : hexk_clk_rst_monitor

`endif  // HEXK_CLK_RST_MONITOR_SV
