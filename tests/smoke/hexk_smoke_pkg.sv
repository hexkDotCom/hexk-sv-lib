// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_pkg.sv
//
// Package of the smoke testbench: the cfg and the environment around the FIFO, the base test
// and the three tests. It uses the library as a testbench does: the three agents, the
// scoreboard, the objection aggregator, the watchdog, the knobs and the base test.
// Compile it with tests/smoke/hexk_smoke.f after src/hexk_all.f.

`ifndef HEXK_SMOKE_PKG_SV
`define HEXK_SMOKE_PKG_SV

`include "hexk_macros.svh"

package hexk_smoke_pkg;
   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_base_test;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::hexk_watchdog;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent_cfg;
   import hexk_clk_rst_pkg::hexk_clk_rst_reset_seq;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent_cfg;
   import hexk_valid_ready_pkg::hexk_valid_ready_item;
   import hexk_valid_ready_pkg::hexk_valid_ready_random_seq;
   import hexk_valid_ready_pkg::HEXK_VALID_READY_RESPONDER;

   `include "hexk_smoke_env_cfg.sv"

   // The item of the two channels of the FIFO.
   typedef hexk_valid_ready_item#(hexk_smoke_env_cfg::WIDTH) hexk_smoke_item_t;

   `include "hexk_smoke_heartbeat.sv"
   `include "hexk_smoke_env.sv"
   `include "hexk_smoke_base_test.sv"
   `include "hexk_smoke_pass_test.sv"
   `include "hexk_smoke_error_test.sv"
   `include "hexk_smoke_hang_test.sv"
endpackage : hexk_smoke_pkg

`endif  // HEXK_SMOKE_PKG_SV
