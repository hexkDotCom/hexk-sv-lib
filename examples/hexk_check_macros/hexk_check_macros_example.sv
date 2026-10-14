// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_check_macros_example.sv
//
// Minimal use of the check macros: four checks with static message IDs on an address, a
// length, a status register and a data queue, and the table of executed checks at the end.
// All four pass here; a failing one would report a UVM error that names the values.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_check_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_check_stats;

   localparam int unsigned WORD_BYTES = 4;
   localparam int unsigned MAX_LENGTH = 64;
   localparam logic [7:0] STATUS_BITS = 8'h0F;

   logic         [31:0] addr = 32'h0000_1004;
   logic         [ 7:0] status = 8'h03;
   int unsigned         length = 12;
   byte unsigned        observed             [$];
   byte unsigned        expected             [$];

   initial begin
      observed = '{8'h10, 8'h11, 8'h12};
      expected = '{8'h10, 8'h11, 8'h12};

      `hexk_check_aligned(addr, WORD_BYTES, "EXAMPLE_ADDR", "write address")
      `hexk_check_in_range(length, 1, MAX_LENGTH, "EXAMPLE_LENGTH")
      `hexk_check_mask(status, STATUS_BITS, "EXAMPLE_STATUS", "reserved status bits")
      `hexk_check_q_eq(observed, expected, "EXAMPLE_DATA")

      $info("\n%s", hexk_check_stats::summary());
   end

endmodule : hexk_check_macros_example
