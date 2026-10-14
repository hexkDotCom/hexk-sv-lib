// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_pkg.sv
//
// Package of the valid/ready agent: the item, the cfg, the driver, the monitor, the agent and
// two sequences, all with the width of the data as parameter DATA_WIDTH.
// Compile it with src/agents/hexk_valid_ready/hexk_valid_ready.f, which also compiles the
// interface hexk_valid_ready_if, and import the classes that the testbench uses.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_PKG_SV
`define HEXK_VALID_READY_PKG_SV

`include "hexk_macros.svh"

package hexk_valid_ready_pkg;
   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay;
   import hexk_uvm_pkg::hexk_delay_cfg;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_handshake_coverage;
   import hexk_uvm_pkg::hexk_handshake_cycle_t;

   // Which side of the channel an active agent drives.
   typedef enum {
      // Drives valid and data.
      HEXK_VALID_READY_INITIATOR,
      // Drives ready.
      HEXK_VALID_READY_RESPONDER
   } hexk_valid_ready_role_e;

   `include "hexk_valid_ready_item.sv"
   `include "hexk_valid_ready_agent_cfg.sv"
   `include "hexk_valid_ready_driver.sv"
   `include "hexk_valid_ready_monitor.sv"
   `include "hexk_valid_ready_agent.sv"
   `include "sequences/hexk_valid_ready_random_seq.sv"
   `include "sequences/hexk_valid_ready_data_seq.sv"
endpackage : hexk_valid_ready_pkg

`endif  // HEXK_VALID_READY_PKG_SV
