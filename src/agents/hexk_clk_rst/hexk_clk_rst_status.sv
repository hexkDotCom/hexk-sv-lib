// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_status.sv
//
// What a hexk_clk_rst_agent knows during the run: whether the reset is asserted, the two
// events that tell everyone who holds the status when the reset is asserted and released,
// and the clock that is being driven. The agent creates it in its constructor and keeps it
// in the member status; the monitor and the driver keep it up to date. Hand agent.status to
// whatever waits for a reset or wants the current clock, such as an env that empties its
// scoreboards at a reset. The cfg of the agent stays the setup: the library never changes it.
// A status belongs to its agent; it is not meant to be copied.
// All times are whole picoseconds.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    CHK-6
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_STATUS_SV
`define HEXK_CLK_RST_STATUS_SV

class hexk_clk_rst_status extends uvm_object;

   // Triggered by the monitor, with the item as data, when the reset is asserted and when it is released.
   uvm_event        reset_asserted;
   uvm_event        reset_released;

   // 1 from the moment the monitor saw the reset asserted until it saw it released.
   bit              in_reset;

   // The clock that the driver drives now: from the cfg at the start of the run phase, then from every
   // clock sequence. In a passive agent the values of the cfg, which the agent does not drive.
   longint unsigned period_ps;
   int unsigned     duty_percent;
   longint unsigned jitter_ps;

   `uvm_object_utils(hexk_clk_rst_status)

   // Creates a status with the two events, out of reset, with the default clock of a cfg.
   function new(string name = "hexk_clk_rst_status");
      super.new(name);
      reset_asserted = new("reset_asserted");
      reset_released = new("reset_released");
      in_reset       = 0;
      set_clock(hexk_clk_rst_agent_cfg::DEFAULT_PERIOD_PS, hexk_clk_rst_agent_cfg::DEFAULT_DUTY_PERCENT, 0);
   endfunction : new

   // Notes the clock that is driven from now on; called by the agent and its driver.
   function void set_clock(longint unsigned period, int unsigned duty, longint unsigned jitter);
      period_ps    = period;
      duty_percent = duty;
      jitter_ps    = jitter;
   endfunction : set_clock

   // The frequency in MHz of the clock that is driven; 0 for a period of 0.
   function real get_freq_mhz();
      return (period_ps == 0) ? 0.0 : hexk_clk_rst_agent_cfg::PS_PER_MHZ_PERIOD / real'(period_ps);
   endfunction : get_freq_mhz

   // The reset and the clock, on one line.
   function string convert2string();
      return $sformatf("in_reset=%0b period_ps=%0d duty_percent=%0d jitter_ps=%0d", in_reset, period_ps, duty_percent,
                       jitter_ps);
   endfunction : convert2string

endclass : hexk_clk_rst_status

`endif  // HEXK_CLK_RST_STATUS_SV
