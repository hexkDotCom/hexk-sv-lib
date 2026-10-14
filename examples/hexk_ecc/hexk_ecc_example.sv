// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ecc_example.sv
//
// Minimal use of hexk_ecc: the code word of a 32-bit memory word with the check bits above
// the data, then the same word read back with one flipped bit (corrected, and the syndrome
// tells which bit) and with two flipped bits (reported, not corrected).
// Needs only src/core/hexk_core.f.

module hexk_ecc_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_ecc;
   import hexk_core_pkg::hexk_bits_t;

   localparam int unsigned DATA_WIDTH  = 32;
   localparam int unsigned CODE_WIDTH  = 39;
   localparam int unsigned FLIPPED_BIT = 5;

   hexk_ecc                            ecc;
   logic              [DATA_WIDTH-1:0] word;
   logic              [CODE_WIDTH-1:0] stored;
   hexk_bits_t                         damaged;
   hexk_bits_t                         read_data;
   int unsigned                        syndrome;
   hexk_ecc::status_e                  status;

   initial begin
      ecc    = new(DATA_WIDTH, hexk_ecc::HEXK_ECC_APPENDED);
      word   = 32'hDEAD_BEEF;
      stored = CODE_WIDTH'(ecc.encode(hexk_bits_t'(word)));
      $info("%0d data bits and %0d check bits: 0x%0h is stored as 0x%0h", ecc.get_data_width(), ecc.get_check_width(),
            word, stored);

      // One flipped bit: decode corrects the data, and the syndrome points at the bit.
      damaged = ecc.flip(hexk_bits_t'(stored), FLIPPED_BIT);
      status  = ecc.decode(damaged, read_data, syndrome);
      $info("bit %0d flipped: %s, data 0x%0h, syndrome 0x%0h points at bit %0d", FLIPPED_BIT, status.name(), read_data,
            syndrome, ecc.error_index(syndrome));

      // Two flipped bits, chosen at random: decode reports them and leaves the data as read.
      damaged = ecc.inject(hexk_bits_t'(stored), 2);
      status  = ecc.decode(damaged, read_data, syndrome);
      if (status == hexk_ecc::HEXK_ECC_UNCORRECTABLE) begin
         $info("two bits flipped: not corrected, data as read 0x%0h, syndrome 0x%0h", read_data, syndrome);
      end
   end

endmodule : hexk_ecc_example
