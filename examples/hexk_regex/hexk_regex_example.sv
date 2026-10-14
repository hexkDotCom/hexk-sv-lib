// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_regex_example.sv
//
// Minimal use of hexk_regex: an include/exclude filter on message IDs, a one-off match,
// and a glob turned into a regular expression. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_regex_example;
   timeunit 1ns / 1ps;

   import hexk_uvm_pkg::hexk_regex;

   hexk_regex trace_filter;

   initial begin
      // Every scoreboard ID, except the leftover report.
      trace_filter = new("^SB_", "LEFTOVER");
      $info("SB_MISMATCH passes: %0b", trace_filter.is_match("SB_MISMATCH"));
      $info("SB_LEFTOVER passes: %0b", trace_filter.is_match("SB_LEFTOVER"));
      $info("DRV_TIMEOUT passes: %0b", trace_filter.is_match("DRV_TIMEOUT"));

      $info("WR_17 is a transfer name: %0b", hexk_regex::match("^(RD|WR)_[0-9]+$", "WR_17"));
      $info("glob as expression: %s", hexk_regex::glob_to_regex("uvm_test_top.env.*"));
   end

endmodule : hexk_regex_example
