// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_catcher_example.sv
//
// Minimal use of hexk_report_catcher in a negative test: two parity errors are provoked on
// purpose, so exactly two errors with that ID are expected: a count without a maximum is
// exact. They are demoted to info, and check_expectations() reports an error if there were
// fewer or more. In a real testbench expect_msg() is called by the test before the stimulus
// starts; a test derived from hexk_base_test has the expectations checked in its report
// phase, any other test calls check_expectations() in its check_phase. A check that fails on
// purpose is declared with expect_check(id, count). Needs UVM and src/uvm/hexk_uvm.f.

module hexk_report_catcher_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   localparam int unsigned INJECTED_ERRORS = 2;

   hexk_report_catcher catcher;

   initial begin
      catcher = hexk_report_catcher::add_global();
      catcher.expect_msg("^DRV_PARITY$", UVM_ERROR, "", INJECTED_ERRORS);

      `uvm_error("DRV_PARITY", "parity error on beat 3")
      `uvm_error("DRV_PARITY", "parity error on beat 7")

      catcher.check_expectations();
   end

endmodule : hexk_report_catcher_example
