// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_pkg.sv
//
// Package of the reference testbench: the bus agent, the register model, the predictor and the
// checkers, the environment, the virtual sequences and the tests. Compile it with tests/reference/hexk_ref.f after
// src/hexk_all.f; see tests/reference/README.md.

`ifndef HEXK_REF_PKG_SV
`define HEXK_REF_PKG_SV

`include "hexk_macros.svh"

package hexk_ref_pkg;
   timeunit 1ns; timeprecision 1ps;

   `include "uvm_macros.svh"
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_crc;
   import hexk_core_pkg::hexk_lfsr;
   import hexk_core_pkg::hexk_ecc;
   import hexk_core_pkg::hexk_str;
   // FIL-5 waived: the testbench uses most of the library and of both agent packages; these three imports are the
   // only wildcard imports of user packages.
   import hexk_uvm_pkg::*;
   import hexk_clk_rst_pkg::*;
   import hexk_valid_ready_pkg::*;

   `include "hexk_ref_commit_item.sv"
   `include "hexk_ref_bus_item.sv"
   `include "hexk_ref_bus_seq.sv"
   `include "hexk_ref_reg_adapter.sv"
   `include "hexk_ref_bus_driver.sv"
   `include "hexk_ref_bus_monitor.sv"
   `include "hexk_ref_bus_agent_cfg.sv"
   `include "hexk_ref_bus_agent.sv"
   `include "hexk_ref_reg.sv"
   `include "hexk_ref_regs.sv"
   `include "hexk_ref_result.sv"
   `include "hexk_ref_mem_model.sv"
   `include "hexk_ref_predictor.sv"
   `include "hexk_ref_env_cfg.sv"
   `include "hexk_ref_result_sb.sv"
   `include "hexk_ref_env.sv"
   `include "hexk_ref_vseq_base.sv"
   `include "hexk_ref_packet_vseq.sv"
   `include "hexk_ref_burst_vseq.sv"
   `include "hexk_ref_control_vseq.sv"
   `include "hexk_ref_scenario_vseq.sv"
   `include "hexk_ref_random_vseq.sv"
   `include "hexk_ref_vectors.svh"
   `include "hexk_ref_vectors_vseq.sv"
   `include "hexk_ref_regs_vseq.sv"
   `include "hexk_ref_layout.sv"
   `include "hexk_ref_multi_vseq.sv"
   `include "hexk_ref_warm_reset_vseq.sv"
   `include "hexk_ref_ecc_vseq.sv"
   `include "hexk_ref_corrupt_vseq.sv"
   `include "hexk_ref_back_to_back_vseq.sv"
   `include "hexk_ref_mem_vseq.sv"
   `include "hexk_ref_fault_vseq.sv"
   `include "hexk_ref_test_vseq.sv"
   `include "hexk_ref_base_test.sv"
   `include "hexk_ref_pass_test.sv"
   `include "hexk_ref_vectors_test.sv"
   `include "hexk_ref_regs_test.sv"
   `include "hexk_ref_multi_test.sv"
   `include "hexk_ref_warm_reset_test.sv"
   `include "hexk_ref_ecc_test.sv"
   `include "hexk_ref_corrupt_test.sv"
   `include "hexk_ref_back_to_back_test.sv"
   `include "hexk_ref_control_test.sv"
   `include "hexk_ref_mem_test.sv"
   `include "hexk_ref_shared_bus_test.sv"
   `include "hexk_ref_hang_test.sv"
   `include "hexk_ref_stall_test.sv"
endpackage : hexk_ref_pkg

`endif  // HEXK_REF_PKG_SV
