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
// With cfg.check_period it also checks the clock: the time between two rising edges is the
// period of the status within twice its jitter (each edge may move by the jitter), counted with
// hexk_check_stats and reported as HEXK_CLK_RST_PERIOD otherwise. An interval is not checked when
// it starts or ends in reset, when the status changed in it (a clock sequence), or when the
// generator was stopped and started in it; a passive agent cannot see a stop of the clock that it
// does not drive, so a clock stopped outside reset is a long interval there. Clearing
// cfg.check_period during the run ends the check at the next rising edge, for the rest of the run.
// num_checked() and num_checked_at() tell how many intervals were checked, in all and at one period.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-5 CMP-12 CHK-6
//! @emits     HEXK_CLK_RST_RESET:info HEXK_CLK_RST_PERIOD:error
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

   // Intervals of the clock checked, in all and by the period in picoseconds that the status gave.
   local int unsigned                     checked;
   local int unsigned                     checked_by_period[longint unsigned];

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

   // UVM callback: watches the reset and, with cfg.check_period, the clock.
   task run_phase(uvm_phase phase);
      super.run_phase(phase);
      if (cfg.check_period) begin
         fork
            check_clock();
         join_none
      end
      watch_reset();
   endtask : run_phase

   // Number of intervals of the clock that were checked.
   function int unsigned num_checked();
      return checked;
   endfunction : num_checked

   // Number of intervals of the clock that were checked while the status gave the period period_ps.
   function int unsigned num_checked_at(longint unsigned period_ps);
      return checked_by_period.exists(period_ps) ? checked_by_period[period_ps] : 0;
   endfunction : num_checked_at

   // Reports every change of the reset between asserted and released. A reset that is asserted at the start is
   // reported; a pin without a level is neither and changes nothing.
   local task watch_reset();
      bit was_active = 0;
      bit is_active;
      forever begin
         if (vif.get_reset(is_active) && is_active != was_active) begin
            was_active = is_active;
            publish(is_active);
         end
         vif.wait_reset_change();
      end
   endtask : watch_reset

   // Checks the time between every two rising edges against the clock of the status, until cfg.check_period is 0.
   local task check_clock();
      bit              seen = 0;
      longint unsigned last_ps;
      bit              last_in_reset;
      longint unsigned last_period_ps;
      longint unsigned last_jitter_ps;
      int unsigned     last_starts;
      longint unsigned now_ps;
      longint unsigned interval_ps;
      longint unsigned distance_ps;
      forever begin
         vif.wait_clks(1);
         if (!cfg.check_period) begin
            return;
         end
         now_ps = hexk_uvm_pkg::hexk_wait_util::now_ps();
         if (seen && !last_in_reset && !status.in_reset && last_period_ps == status.period_ps &&
             last_jitter_ps == status.jitter_ps && last_starts == vif.get_start_count()) begin
            interval_ps = now_ps - last_ps;
            distance_ps = (interval_ps > status.period_ps) ? interval_ps - status.period_ps :
                status.period_ps - interval_ps;
            `hexk_check_le(
                distance_ps, 2 * status.jitter_ps, "HEXK_CLK_RST_PERIOD",
                $sformatf("the clock had an interval of %0d ps between two rising edges, not %0d ps within %0d ps",
                          interval_ps, status.period_ps, 2 * status.jitter_ps))
            checked++;
            checked_by_period[status.period_ps] = num_checked_at(status.period_ps) + 1;
         end
         seen           = 1;
         last_ps        = now_ps;
         last_in_reset  = status.in_reset;
         last_period_ps = status.period_ps;
         last_jitter_ps = status.jitter_ps;
         last_starts    = vif.get_start_count();
      end
   endtask : check_clock

   // Writes the item of a change to the port, updates the status, triggers its event and reports the change.
   local function void publish(bit reset_active);
      // Under the name of the monitor, so that a factory override of one agent's items can name its path.
      hexk_clk_rst_item item = hexk_clk_rst_item::type_id::create("item", this);
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
