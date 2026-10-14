// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_crc_example.sv
//
// Minimal use of hexk_crc: the CRC of a complete message with a preset, a running CRC that
// is read while data still arrives, and a custom model from catalogue parameters.
// Needs only src/core/hexk_core.f.

module hexk_crc_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_crc;

   byte unsigned payload   [$];
   hexk_crc      frame_crc;
   hexk_crc      token_crc;

   initial begin
      payload   = '{8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37, 8'h38, 8'h39};

      frame_crc = hexk_crc::crc32();
      $info("CRC-32 of the whole payload: 0x%0h", hexk_crc::compute(frame_crc, payload));

      frame_crc.reset();
      foreach (payload[i]) begin
         frame_crc.update_byte(payload[i]);
      end
      $info("the same, fed byte by byte: 0x%0h", frame_crc.get());

      // CRC-5/USB from its catalogue parameters: width, poly, init, refin, refout, xorout.
      token_crc = new(5, 64'h05, 64'h1F, 1, 1, 64'h1F);
      $info("CRC-5/USB of the payload: 0x%0h", hexk_crc::compute(token_crc, payload));
   end

endmodule : hexk_crc_example
