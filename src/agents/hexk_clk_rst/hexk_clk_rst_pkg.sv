// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_pkg.sv
//
// Package of the clock and reset agent: the item, the cfg, the status, the driver, the
// monitor, the agent and the sequences that reset the DUT and change, stop and start its clock.
// Compile it with src/agents/hexk_clk_rst/hexk_clk_rst.f, which also compiles the interface
// hexk_clk_rst_if, and import the classes that the testbench uses.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_PKG_SV
`define HEXK_CLK_RST_PKG_SV

`include "hexk_macros.svh"

package hexk_clk_rst_pkg;
   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_clk_countable;

   // What an item asks the driver to do; an item of the monitor is always HEXK_CLK_RST_RESET.
   typedef enum bit [2:0] {
      // Assert the reset, hold it, release it.
      HEXK_CLK_RST_RESET,
      // A new period, duty cycle and jitter.
      HEXK_CLK_RST_CLOCK,
      // Stop the clock, and start it again after a time if one is given.
      HEXK_CLK_RST_STOP,
      // Start the clock.
      HEXK_CLK_RST_START,
      // Assert the reset and leave it asserted, so that the clock can be changed before the release.
      HEXK_CLK_RST_ASSERT,
      // Release the reset.
      HEXK_CLK_RST_RELEASE
   } hexk_clk_rst_op_e;

   `include "hexk_clk_rst_item.sv"
   `include "hexk_clk_rst_agent_cfg.sv"
   `include "hexk_clk_rst_status.sv"
   `include "hexk_clk_rst_driver.sv"
   `include "hexk_clk_rst_monitor.sv"
   `include "hexk_clk_rst_agent.sv"
   `include "sequences/hexk_clk_rst_reset_seq.sv"
   `include "sequences/hexk_clk_rst_clock_seq.sv"
   `include "sequences/hexk_clk_rst_stop_seq.sv"
   `include "sequences/hexk_clk_rst_start_seq.sv"
   `include "sequences/hexk_clk_rst_assert_seq.sv"
   `include "sequences/hexk_clk_rst_release_seq.sv"
endpackage : hexk_clk_rst_pkg

`endif  // HEXK_CLK_RST_PKG_SV
