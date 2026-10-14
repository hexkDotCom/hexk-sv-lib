// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_server_example.sv
//
// Minimal use of hexk_report_server: build a cfg, let the command line override it, install
// the server, report through the usual UVM macros, and print the summary table.
// In a real testbench the install comes before run_test(), and UVM prints the summary at
// the end of the test by itself. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_report_server_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_cfg;
   import hexk_uvm_pkg::hexk_report_server;
   `include "uvm_macros.svh"

   localparam int unsigned CONTEXT_WIDTH = 20;

   hexk_report_cfg    cfg;
   hexk_report_server server;

   initial begin
      cfg               = hexk_report_cfg::type_id::create("cfg");
      cfg.context_width = CONTEXT_WIDTH;
      cfg.stacktrace_triggers.push_back("^SB_MISMATCH$");
      cfg.apply_plusargs();
      server = hexk_report_server::install(cfg);

      `uvm_info("EXAMPLE", "printed in the compact layout", UVM_NONE)
      `uvm_warning("EXAMPLE", "warnings, errors and fatals get a running number")
      $info("\n%s", server.summary());
   end

endmodule : hexk_report_server_example
