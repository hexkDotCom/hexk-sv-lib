// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uvm_pkg.sv
//
// UVM utility package of hexk-sv-lib: checks, reporting, end of test, knobs, delays,
// scoreboard and memory model.
// Compile it with src/uvm/hexk_uvm.f after UVM itself, import it next to uvm_pkg, and
// include hexk_macros.svh for the macros. The package does not re-export hexk_core_pkg;
// import both where both are needed.
// The package has the time unit and precision 1ps, so that $time and #(n) inside it are whole
// picoseconds: every time that crosses its API is a longint unsigned number of picoseconds,
// with a name that ends in _ps, and means the same whatever the time unit of the caller is.
//
//! @module    hexk_uvm_pkg
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_UVM_PKG_SV
`define HEXK_UVM_PKG_SV

`include "hexk_sim_compat.svh"
`include "hexk_macros.svh"

package hexk_uvm_pkg;
   timeunit 1ps; timeprecision 1ps;
   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_core_pkg::hexk_plusarg;
   import hexk_core_pkg::hexk_enum_util;
   import hexk_core_pkg::hexk_rand_stream;

   `include "data/hexk_regex.sv"
   `include "data/hexk_uid.sv"
   `include "data/hexk_uid_pool.sv"
   `include "report/hexk_msg_listener.sv"
   `include "report/hexk_report_cfg.sv"
   `include "report/hexk_report_server.sv"
   `include "report/hexk_report_catcher_rule.sv"
   `include "report/hexk_report_catcher.sv"
   `include "report/hexk_check_stats.sv"
   `include "data/hexk_value_wrapper.sv"
   `include "data/hexk_meta_item.sv"
   `include "stim/hexk_wait_util.sv"
   `include "stim/hexk_clk_countable.sv"
   `include "eot/hexk_objectable.sv"
   `include "eot/hexk_objection_member.sv"
   `include "eot/hexk_objection_aggregator.sv"
   `include "eot/hexk_checkable.sv"
   `include "eot/hexk_eot_registry.sv"
   `include "eot/hexk_watchdog.sv"
   `include "tlm/hexk_delay_analysis_fifo.sv"
   `include "check/hexk_scoreboard_cfg.sv"
   `include "check/hexk_sb_stats.sv"
   `include "check/hexk_sb_stream.sv"
   `include "check/hexk_scoreboard.sv"
   `include "mem/hexk_mem_model.sv"
   `include "csr/hexk_csr_util.sv"
   `include "config/hexk_knob.sv"
   `include "config/hexk_knobs.sv"
   `include "config/hexk_enum_knob.sv"
   `include "cov/hexk_handshake_coverage.sv"
   `include "stim/hexk_delay_cfg.sv"
   `include "stim/hexk_delay.sv"
   `include "stim/hexk_rand_once_guard.sv"
   `include "base/hexk_base_test.sv"
endpackage : hexk_uvm_pkg

`endif  // HEXK_UVM_PKG_SV
