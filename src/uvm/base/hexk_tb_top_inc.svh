// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_tb_top_inc.svh
//
// Include for the body of the testbench top module: it installs the report server of the
// library and starts the test. Write `include "base/hexk_tb_top_inc.svh" once inside the
// module, after its interfaces and the DUT; the module then needs no initial block with
// run_test().
// The report server is installed by the initialiser of a variable, which runs before every
// initial block of the simulation, so that even the first message has the layout of the
// library. Its settings are a new hexk_report_cfg with the +hexk_report_* plusargs applied.
// For work that must be done before run_test(), such as `hexk_vif_set, define
// HEXK_TB_PRE_RUN_TEST as the name of a task or function of the module without arguments,
// before the include or with +define+; it is called at time 0 before run_test().
//
//! @module    hexk_base_test
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_TB_TOP_INC_SVH
`define HEXK_TB_TOP_INC_SVH

// Installs the report server of the library with the settings of the +hexk_report_* plusargs; returns 1.
function automatic bit hexk_tb_install_report_server();
   hexk_uvm_pkg::hexk_report_cfg report_cfg = hexk_uvm_pkg::hexk_report_cfg::type_id::create("report_cfg");
   report_cfg.apply_plusargs();
   void'(hexk_uvm_pkg::hexk_report_server::install(report_cfg));
   return 1;
endfunction : hexk_tb_install_report_server

// Its initialiser installs the report server before the initial blocks start.
bit hexk_tb_report_server_installed = hexk_tb_install_report_server();

initial begin
`ifdef HEXK_TB_PRE_RUN_TEST
   `HEXK_TB_PRE_RUN_TEST();
`endif
   uvm_pkg::run_test();
end

`endif  // HEXK_TB_TOP_INC_SVH
