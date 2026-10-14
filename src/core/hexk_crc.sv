// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_crc.sv
//
// Cyclic redundancy check of 1 to 64 bits, described by the usual six parameters: width,
// polynomial, initial value, input reflection, output reflection and final XOR.
// Take a preset (hexk_crc::crc32() and others) or call new() with your own parameters, feed
// data with update_byte, update_bytes or update_bits, and read the result with get().
// reset() starts a new message. get() does not change the state, so a running CRC can be
// read at any point. hexk_crc::compute() does reset, update and get in one call.
// The polynomial is given without its top term, as in CRC catalogues (CRC-32: 'h04C11DB7).
// The calculation is bit-serial: simple and fast enough for testbench data.
// Illegal arguments are reported with $error; see docs/api/hexk_crc.md for what is used instead.
//
//! @module    hexk_crc
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CRC_SV
`define HEXK_CRC_SV

class hexk_crc;

   // Largest CRC width.
   localparam int unsigned MAX_WIDTH = 64;

   // Number of bits in a byte.
   localparam int unsigned BYTE_WIDTH = 8;

   // Number of bits of the data vector of update_bits.
   localparam int unsigned VECTOR_WIDTH = $bits(hexk_bits_t);

   local int unsigned     crc_width;
   local longint unsigned polynomial;
   local longint unsigned initial_value;
   local bit              reflect_in;
   local bit              reflect_out;
   local longint unsigned final_xor;
   local longint unsigned state;
   local longint unsigned state_mask;

   // Creates a CRC from its parameters; width is 1 to 64, poly is given without the top term.
   function new(int unsigned width, longint unsigned poly, longint unsigned init = 0, bit refin = 0, bit refout = 0,
                longint unsigned xorout = 0);
      crc_width = width;
      if (width == 0 || width > MAX_WIDTH) begin
         $error("hexk_crc::new: width %0d is not in 1..%0d", width, MAX_WIDTH);
         crc_width = MAX_WIDTH;
      end
      state_mask = '1;
      state_mask = state_mask >> (MAX_WIDTH - crc_width);
      polynomial = poly & state_mask;
      initial_value = init & state_mask;
      reflect_in = refin;
      reflect_out = refout;
      final_xor = xorout & state_mask;
      reset();
   endfunction : new

   // CRC-8 (SMBus): poly 'h07, init 0, not reflected, no final XOR.
   static function hexk_crc crc8();
      hexk_crc result = new(8, 64'h07);
      return result;
   endfunction : crc8

   // CRC-16/CCITT-FALSE: poly 'h1021, init 'hFFFF, not reflected, no final XOR.
   static function hexk_crc crc16_ccitt();
      hexk_crc result = new(16, 64'h1021, 64'hFFFF);
      return result;
   endfunction : crc16_ccitt

   // CRC-16/ARC (IBM): poly 'h8005, init 0, reflected, no final XOR.
   static function hexk_crc crc16_ibm();
      hexk_crc result = new(16, 64'h8005, 64'h0, 1, 1);
      return result;
   endfunction : crc16_ibm

   // CRC-32 (Ethernet): poly 'h04C11DB7, init and final XOR 'hFFFFFFFF, reflected.
   static function hexk_crc crc32();
      hexk_crc result = new(32, 64'h04C1_1DB7, 64'hFFFF_FFFF, 1, 1, 64'hFFFF_FFFF);
      return result;
   endfunction : crc32

   // CRC-32C (Castagnoli): poly 'h1EDC6F41, init and final XOR 'hFFFFFFFF, reflected.
   static function hexk_crc crc32c();
      hexk_crc result = new(32, 64'h1EDC_6F41, 64'hFFFF_FFFF, 1, 1, 64'hFFFF_FFFF);
      return result;
   endfunction : crc32c

   // CRC-64/ECMA-182: poly 'h42F0E1EBA9EA3693, init 0, not reflected, no final XOR.
   static function hexk_crc crc64_ecma();
      hexk_crc result = new(64, 64'h42F0_E1EB_A9EA_3693);
      return result;
   endfunction : crc64_ecma

   // Starts a new message: the state returns to the initial value.
   function void reset();
      state = initial_value;
   endfunction : reset

   // Feeds one byte: most significant bit first, or least significant bit first when refin is set.
   function void update_byte(byte unsigned data);
      for (int unsigned i = 0; i < BYTE_WIDTH; i++) begin
         shift_in(reflect_in ? data[i] : data[BYTE_WIDTH-1-i]);
      end
   endfunction : update_byte

   // Feeds the bytes of data in order.
   function void update_bytes(const ref byte unsigned data[$]);
      foreach (data[i]) begin
         update_byte(data[i]);
      end
   endfunction : update_bytes

   // Feeds num_bits bits of data in serial order, bit 0 first, whatever refin is.
   function void update_bits(hexk_bits_t data, int unsigned num_bits);
      int unsigned count = num_bits;
      if (num_bits > VECTOR_WIDTH) begin
         $error("hexk_crc::update_bits: %0d bits do not fit HEXK_MAX_WIDTH (%0d)", num_bits, VECTOR_WIDTH);
         count = VECTOR_WIDTH;
      end
      for (int unsigned i = 0; i < count; i++) begin
         shift_in(data[i] === 1'b1);
      end
   endfunction : update_bits

   // Returns the CRC of the data fed since the last reset; the state is not changed.
   function longint unsigned get();
      longint unsigned result = state;
      if (reflect_out) begin
         result = 0;
         for (int unsigned i = 0; i < crc_width; i++) begin
            result[i] = state[crc_width-1-i];
         end
      end
      return result ^ final_xor;
   endfunction : get

   // CRC of data with the given model, from a fresh start; the model keeps the final state.
   static function longint unsigned compute(hexk_crc model, const ref byte unsigned data[$]);
      if (model == null) begin
         $error("hexk_crc::compute: model is null");
         return 0;
      end
      model.reset();
      model.update_bytes(data);
      return model.get();
   endfunction : compute

   // Shifts one message bit into the state.
   local function void shift_in(bit data_bit);
      bit feedback = state[crc_width-1] ^ data_bit;
      state = (state << 1) & state_mask;
      if (feedback) begin
         state = state ^ polynomial;
      end
   endfunction : shift_in

endclass : hexk_crc

`endif  // HEXK_CRC_SV
