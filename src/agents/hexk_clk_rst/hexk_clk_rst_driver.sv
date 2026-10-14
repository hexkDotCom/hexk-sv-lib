// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_driver.sv
//
// Driver of the clock and reset agent: applies the cfg at the start of the run phase and
// then carries out the items of the sequences, one after the other. It notes the clock it
// drives in the status of the agent; it does not change the cfg.
// It is thin: the clock is generated and the pins are driven by the interface, whose tasks
// the driver calls. It is created by hexk_clk_rst_agent in active mode; a testbench does
// not use it directly.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-5 CMP-13 IFC-8
//! @emits     HEXK_CLK_RST_ILLEGAL:error HEXK_CLK_RST_STOPPED:error HEXK_CLK_RST_CLOCK:info
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_DRIVER_SV
`define HEXK_CLK_RST_DRIVER_SV

class hexk_clk_rst_driver extends uvm_driver #(hexk_clk_rst_item);

   // The cfg and the status of the agent; assigned by the agent before the connect phase.
   hexk_clk_rst_agent_cfg        cfg;
   hexk_clk_rst_status           status;

   local virtual hexk_clk_rst_if vif;

   `uvm_component_utils(hexk_clk_rst_driver)

   // Creates the driver.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: takes the interface from the cfg; the agent has checked both.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vif = cfg.vif;
   endfunction : connect_phase

   // UVM callback: applies the cfg, then carries out the items.
   task run_phase(uvm_phase phase);
      apply_cfg();
      forever begin
         seq_item_port.get_next_item(req);
         drive_item(req);
         seq_item_port.item_done();
      end
   endtask : run_phase

   // Gives the interface the clock and the reset of the cfg; an illegal clock is replaced by the default one.
   local function void apply_cfg();
      string reason = cfg.illegal_reason();
      if (reason.len() == 0) begin
         status.set_clock(cfg.period_ps, cfg.duty_percent, cfg.jitter_ps);
      end else begin
         `uvm_error("HEXK_CLK_RST_ILLEGAL", $sformatf(
                    "the clock of the cfg is not legal: %s; the default clock is used", reason))
         status.set_clock(hexk_clk_rst_agent_cfg::DEFAULT_PERIOD_PS, hexk_clk_rst_agent_cfg::DEFAULT_DUTY_PERCENT, 0);
      end
      vif.set_clock(status.period_ps, hexk_clk_rst_agent_cfg::high_time_ps(status.period_ps, status.duty_percent),
                    status.jitter_ps);
      vif.set_start_delay(cfg.phase_ps);
      vif.drive_reset(cfg.reset_at_start);
      if (cfg.start_clock) begin
         vif.request_run(1'b1);
      end
   endfunction : apply_cfg

   // Carries out one item; returns when the item is done.
   local task drive_item(hexk_clk_rst_item item);
      case (item.op)
         HEXK_CLK_RST_RESET: drive_reset(item);
         HEXK_CLK_RST_CLOCK: drive_clock(item);
         HEXK_CLK_RST_STOP:  stop_clock(item);
         HEXK_CLK_RST_START: start_clock();
         default: begin
            `uvm_error(
                "HEXK_CLK_RST_ILLEGAL", $sformatf(
                "the operation of an item (%0d) is not a value of hexk_clk_rst_op_e; the item is ignored", item.op))
         end
      endcase
   endtask : drive_item

   // Asserts the reset, holds it and releases it.
   local task drive_reset(hexk_clk_rst_item item);
      int unsigned hold_cycles = item.hold_cycles;
      bit          sync_assert = item.sync_assert;
      bit          sync_release = item.sync_release;
      if (!vif.is_running() && (hold_cycles != 0 || sync_assert || sync_release)) begin
         `uvm_error("HEXK_CLK_RST_STOPPED",
                    $sformatf("the clock is stopped, but the reset item needs rising edges (%s); they are left out",
                              item.convert2string()))
         hold_cycles  = 0;
         sync_assert  = 0;
         sync_release = 0;
      end
      if (sync_assert) begin
         vif.drive_reset_at_edge(1'b1, 1'b1);
      end else begin
         vif.drive_reset(1'b1);
      end
      vif.wait_clks(hold_cycles);
      if (item.hold_ps != 0) begin
         vif.wait_ps(item.hold_ps);
      end
      if (sync_release) begin
         // After a hold that ended with a rising edge the driver is at that edge; otherwise it waits for one.
         vif.drive_reset_at_edge(1'b0, hold_cycles == 0 || item.hold_ps != 0);
      end else if (sync_assert && hold_cycles == 0 && item.hold_ps == 0) begin
         // Without a hold the assertion at the edge has not happened yet in this time step. A release at once
         // would come first and be overwritten; this one comes after the assertion, in the same time step.
         vif.drive_reset_at_edge(1'b0, 1'b0);
      end else begin
         vif.drive_reset(1'b0);
      end
   endtask : drive_reset

   // Gives the clock a new period, duty cycle and jitter; done at the rising edge from which they hold.
   local task drive_clock(hexk_clk_rst_item item);
      string reason = hexk_clk_rst_agent_cfg::clock_illegal_reason(item.period_ps, item.duty_percent, item.jitter_ps);
      if (reason.len() != 0) begin
         `uvm_error("HEXK_CLK_RST_ILLEGAL",
                    $sformatf("the clock of an item is not legal: %s; the clock is not changed", reason))
         return;
      end
      vif.set_clock(item.period_ps, hexk_clk_rst_agent_cfg::high_time_ps(item.period_ps, item.duty_percent),
                    item.jitter_ps);
      status.set_clock(item.period_ps, item.duty_percent, item.jitter_ps);
      `uvm_info("HEXK_CLK_RST_CLOCK", $sformatf("clock set: %s", item.convert2string()), UVM_MEDIUM)
      if (vif.is_running()) begin
         vif.wait_clks(1);
      end
   endtask : drive_clock

   // Stops the clock; with a hold time it starts the clock again after that time.
   local task stop_clock(hexk_clk_rst_item item);
      if (vif.is_running()) begin
         vif.request_run(1'b0);
         vif.wait_stopped();
         `uvm_info("HEXK_CLK_RST_CLOCK", "clock stopped", UVM_MEDIUM)
      end
      if (item.hold_ps != 0) begin
         vif.wait_ps(item.hold_ps);
         start_clock();
      end
   endtask : stop_clock

   // Starts a clock that is stopped; done at its first rising edge.
   local task start_clock();
      if (!vif.is_running()) begin
         vif.request_run(1'b1);
         `uvm_info("HEXK_CLK_RST_CLOCK", "clock started", UVM_MEDIUM)
         vif.wait_clks(1);
      end
   endtask : start_clock

endclass : hexk_clk_rst_driver

`endif  // HEXK_CLK_RST_DRIVER_SV
