// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_ready_bfm.sv
//
// Throttles the input of the reference DUT: at every rising edge it decides whether the DUT may
// take a word in the next cycle (ready_allow). A module, not a class, so it draws its numbers
// from a hexk_rand_stream: the same seed gives the same pattern on every simulator.
// +hexk_ref_ready_percent=<0..100> is the share of cycles in which ready is allowed (default
// 100: no throttling); another value is the fatal REF_READY_PERCENT. +hexk_ref_ready_seed=<n> seeds
// the pattern (default 1).

`ifndef HEXK_REF_READY_BFM_SV
`define HEXK_REF_READY_BFM_SV

`include "hexk_macros.svh"

module hexk_ref_ready_bfm (
    input  logic clk,
    input  logic rst_n,
    output logic ready_allow
);
   timeunit 1ns; timeprecision 1ps;

   import hexk_core_pkg::hexk_rand_stream;
   import hexk_core_pkg::hexk_plusarg;

   hexk_rand_stream stream;
   int unsigned     percent;

   initial begin
      longint given_percent;
      given_percent = hexk_plusarg::get_int("hexk_ref_ready_percent", 100);
      if (given_percent < 0 || given_percent > 100) begin
         `hexk_static_fatal("REF_READY_PERCENT", $sformatf("+hexk_ref_ready_percent=%0d is not a share of 0 to 100",
                                                           given_percent))
      end
      stream  = new("hexk_ref_ready_bfm");
      percent = 32'(given_percent);
      stream.seed(32'(hexk_plusarg::get_int("hexk_ref_ready_seed", 1)));
      `hexk_static_info("REF_READY", $sformatf(
                        "ready allowed in %0d%% of the cycles, pattern seed %0d",
                        percent,
                        hexk_plusarg::get_int(
                            "hexk_ref_ready_seed", 1
                        )
                        ), uvm_pkg::UVM_LOW)
   end

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         ready_allow <= 1'b1;
      end else begin
         ready_allow <= stream.chance(percent);
      end
   end

endmodule : hexk_ref_ready_bfm

`endif  // HEXK_REF_READY_BFM_SV
