// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_countable.sv
//
// Interface class for something that counts the cycles of a clock and can wait for them.
// A component that only needs "how many clock cycles so far" or "wait five clock cycles"
// takes a hexk_clk_countable and knows neither the interface nor the agent behind it.
// hexk_clk_rst_agent implements it; a testbench with a clock of its own can implement it in a
// few lines. wait_clks takes simulation time; get_clk_count must be cheap and must not block.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CLK_COUNTABLE_SV
`define HEXK_CLK_COUNTABLE_SV

interface class hexk_clk_countable;

   // The formatter breaks a pure virtual prototype over three lines.
   // verilog_format: off

   // Number of clock cycles so far.
   pure virtual function longint unsigned get_clk_count();

   // Waits for n clock cycles; returns at once when n is 0.
   pure virtual task wait_clks(int unsigned n);

   // verilog_format: on

endclass : hexk_clk_countable

`endif  // HEXK_CLK_COUNTABLE_SV
