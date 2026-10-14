// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_lfsr_example.sv
//
// Minimal use of hexk_lfsr: a maximal-length register from the built-in tap table, and a
// register with explicit taps and form that mirrors a hardware LFSR.
// Needs only src/core/hexk_core.f.

module hexk_lfsr_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_lfsr;

   localparam int unsigned PATTERN_WIDTH = 16;
   localparam longint unsigned PATTERN_SEED = 64'hACE1;

   hexk_lfsr pattern;
   hexk_lfsr scrambler;

   initial begin
      pattern = hexk_lfsr::maximal(PATTERN_WIDTH, PATTERN_SEED);
      repeat (3) begin
         $info("pattern word 0x%0h", pattern.next());
      end

      // x^7 + x^6 + 1 as taps: bit 6 for x^7, bit 5 for x^6. Fibonacci form, seed all ones.
      scrambler = new(7, 64'h60, 64'h7F, hexk_lfsr::HEXK_LFSR_FIBONACCI);
      $info("scrambler repeats after %0d steps", scrambler.period());
   end

endmodule : hexk_lfsr_example
