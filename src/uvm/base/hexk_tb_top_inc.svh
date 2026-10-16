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
// The test is +UVM_TESTNAME; the include reads it itself and gives it to run_test(), so that it
// also works where UVM is compiled with UVM_CMDLINE_NO_DPI, as on Verilator.
// When the simulation ends, also after a fatal, a final block prints the banner of the verdict of a
// hexk_base_test (hexk_base_test::report_banner()): PASSED, FAILED, or ABORTED when the simulation
// ended before the final phase of the test.
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
   // The test is +UVM_TESTNAME, read here as well: UVM compiled with UVM_CMDLINE_NO_DPI, as on Verilator, does not
   // read it itself. Where UVM reads it, the command line wins and names the same test.
   string hexk_tb_test_name;
   void'($value$plusargs("UVM_TESTNAME=%s", hexk_tb_test_name));
`ifdef HEXK_TB_PRE_RUN_TEST
   `HEXK_TB_PRE_RUN_TEST();
`endif
   uvm_pkg::run_test(hexk_tb_test_name);
end

// The banner of the verdict, whichever way the simulation ends.
final begin
   hexk_uvm_pkg::hexk_base_test::report_banner();
end

`endif  // HEXK_TB_TOP_INC_SVH
