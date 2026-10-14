// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_value_wrapper_example.sv
//
// Minimal use of hexk_value_wrapper: samples of an ADC, which are plain 12-bit numbers, are
// wrapped into objects so that they can go through an analysis port. The model predicts
// each sample only to within two counts, so the expected wrapper carries a tolerance of 2
// and compare() accepts the first sample and rejects the second.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_value_wrapper_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_value_wrapper;
   `include "uvm_macros.svh"

   typedef logic [11:0] hexk_example_sample_t;
   typedef hexk_value_wrapper#(hexk_example_sample_t) hexk_example_sample_item_t;

   localparam longint unsigned TOLERANCE = 2;

   // Compares a predicted sample with a measured one, as a scoreboard would.
   function automatic void check_sample(hexk_example_sample_t predicted, hexk_example_sample_t measured);
      hexk_example_sample_item_t expected = hexk_example_sample_item_t::wrap(predicted, TOLERANCE);
      hexk_example_sample_item_t actual = hexk_example_sample_item_t::wrap(measured);
      if (expected.compare(actual)) begin
         `uvm_info("EXAMPLE", $sformatf("%s is within %0d of %s", actual.convert2string(), TOLERANCE,
                                        expected.convert2string()), UVM_NONE)
      end else begin
         `uvm_error("EXAMPLE", $sformatf(
                    "%s is not within %0d of %s", actual.convert2string(), TOLERANCE, expected.convert2string()))
      end
   endfunction : check_sample

   initial begin
      check_sample(12'd1000, 12'd1002);
      check_sample(12'd1000, 12'd1003);
   end

endmodule : hexk_value_wrapper_example
