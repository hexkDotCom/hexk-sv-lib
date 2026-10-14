// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_math_example.sv
//
// Minimal use of hexk_math: alignment, counter sizing, population count and parity, sign
// extension of a register field, and an address-range overlap test. Values narrower than
// the bit-vector helpers' argument are cast with hexk_bits_t'(), which every tool accepts.
// Needs only src/core/hexk_core.f.

module hexk_math_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_math;
   import hexk_core_pkg::hexk_bits_t;

   localparam longint unsigned PAGE_SIZE = 4096;
   localparam int unsigned FIELD_WIDTH = 12;

   longint unsigned raw = 64'hA5F;

   initial begin
      $info("0x1234 rounded up to a page: 0x%0h", hexk_math::align_up(64'h1234, PAGE_SIZE));
      $info("a counter for 1000 values needs %0d bits", hexk_math::log2_ceil(1000));
      $info("0x%0h has %0d ones", raw, hexk_math::popcount(hexk_bits_t'(raw)));
      $info("even-parity bit of 0x%0h: %0b", raw, hexk_math::parity(hexk_bits_t'(raw)));
      $info("0x%0h as a signed %0d-bit field: %0d", raw, FIELD_WIDTH, hexk_math::sign_extend(raw, FIELD_WIDTH));
      $info("buffers overlap: %0b", hexk_math::ranges_overlap(64'h1000, 64'h1FFF, 64'h1800, 64'h27FF));
   end

endmodule : hexk_math_example
