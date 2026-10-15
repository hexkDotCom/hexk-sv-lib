// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ecc.sv
//
// Extended Hamming code (SECDED: single error correction, double error detection) for data
// words of 4 to 128 bits. Create an object for a data width and a layout, then call encode()
// for the code word of a data word, check_bits() for its check bits alone, and decode() to
// check a code word: it returns what was found and gives the corrected data and the syndrome.
// flip() and inject() make code words with errors for tests; error_index() tells which bit a
// syndrome points at.
// The code is the textbook one: the bits of a code word have positions, position 0 holds the
// overall parity, the positions that are powers of two hold the check bits, the other
// positions hold the data bits in ascending order; all parities are even. The layout says
// where a position is in the vector: at the bit with that index (HEXK_ECC_INTERLEAVED), or
// as {parity, check bits, data} (HEXK_ECC_APPENDED). docs/api/hexk_ecc.md has the details.
// Illegal arguments are reported with $error; see the same file for what is used instead.
//
//! @module    hexk_ecc
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_ECC_SV
`define HEXK_ECC_SV

class hexk_ecc;

   // Place of the check bits in the code word: at their positions between the data bits, or above the data.
   typedef enum bit {
      HEXK_ECC_INTERLEAVED,
      HEXK_ECC_APPENDED
   } layout_e;

   // What decode found in a code word.
   typedef enum bit [1:0] {
      HEXK_ECC_NO_ERROR,
      HEXK_ECC_CORRECTED,
      HEXK_ECC_UNCORRECTABLE
   } status_e;

   // Smallest data width.
   localparam int unsigned MIN_DATA_WIDTH = 4;

   // Largest data width.
   localparam int unsigned MAX_DATA_WIDTH = 128;

   // Number of bits of the data and code word vectors (HEXK_MAX_WIDTH).
   localparam int unsigned VECTOR_WIDTH = $bits(hexk_bits_t);

   local int unsigned data_bits;
   local int unsigned hamming_bits;
   local int unsigned code_bits;
   local layout_e     bit_layout;

   // The bits of a data word and of a code word that are used; an X or Z in the others is ignored.
   local hexk_bits_t  data_mask;
   local hexk_bits_t  code_mask;

   // Index in the code word of the bit at each position.
   local int unsigned index_of_position[];

   // Position of each data bit.
   local int unsigned position_of_data [];

   // Creates the code for data words of data_width bits (4 to 128) in the given layout.
   function new(int unsigned data_width, layout_e layout = HEXK_ECC_INTERLEAVED);
      data_bits = data_width;
      if (data_width < MIN_DATA_WIDTH || data_width > MAX_DATA_WIDTH) begin
         $error("hexk_ecc::new: data width %0d is not in %0d..%0d", data_width, MIN_DATA_WIDTH, MAX_DATA_WIDTH);
         data_bits = (data_width < MIN_DATA_WIDTH) ? MIN_DATA_WIDTH : MAX_DATA_WIDTH;
      end
      if (code_width_of(data_bits) > VECTOR_WIDTH) begin
         $error("hexk_ecc::new: a code word of %0d bits does not fit HEXK_MAX_WIDTH (%0d)", code_width_of(data_bits),
                VECTOR_WIDTH);
         while (data_bits > 1 && code_width_of(
             data_bits
         ) > VECTOR_WIDTH) begin
            data_bits--;
         end
      end
      hamming_bits = hamming_width_of(data_bits);
      code_bits = code_width_of(data_bits);
      bit_layout = layout;
      data_mask = hexk_math::mask(data_bits);
      code_mask = hexk_math::mask(code_bits);
      map_positions();
   endfunction : new

   // Number of data bits.
   function int unsigned get_data_width();
      return data_bits;
   endfunction : get_data_width

   // Number of check bits, the overall parity bit included.
   function int unsigned get_check_width();
      return hamming_bits + 1;
   endfunction : get_check_width

   // Number of bits of a code word: data width plus check width.
   function int unsigned get_code_width();
      return code_bits;
   endfunction : get_code_width

   // Layout given to new().
   function layout_e get_layout();
      return bit_layout;
   endfunction : get_layout

   // Returns the code word of data; every bit of it is X when a data bit is X or Z.
   function hexk_bits_t encode(hexk_bits_t data);
      hexk_bits_t word = encode_positions(data);
      hexk_bits_t result = '0;
      if ($isunknown(data & data_mask)) begin
         return all_unknown(code_bits);
      end
      for (int unsigned position = 0; position < code_bits; position++) begin
         result[index_of_position[position]] = word[position];
      end
      return result;
   endfunction : encode

   // Returns only the check bits of data: bit 0 is check bit 0, the top bit is the overall parity.
   // Every check bit is X when a data bit is X or Z.
   function hexk_bits_t check_bits(hexk_bits_t data);
      hexk_bits_t word = encode_positions(data);
      hexk_bits_t result = '0;
      if ($isunknown(data & data_mask)) begin
         return all_unknown(hamming_bits + 1);
      end
      for (int unsigned i = 0; i < hamming_bits; i++) begin
         result[i] = word[32'd1<<i];
      end
      result[hamming_bits] = word[0];
      return result;
   endfunction : check_bits

   // Checks code: returns what was found, the data (corrected when possible) and the syndrome.
   // A code word with an X or Z bit is uncorrectable: nothing can be said about it. Its data is all X, its syndrome 0.
   function status_e decode(hexk_bits_t code, output hexk_bits_t data, output int unsigned syndrome);
      hexk_bits_t  word = '0;
      int unsigned position_xor = 0;
      bit          parity = 1'b0;
      status_e     status = HEXK_ECC_NO_ERROR;
      if ($isunknown(code & code_mask)) begin
         data     = all_unknown(data_bits);
         syndrome = 0;
         return HEXK_ECC_UNCORRECTABLE;
      end
      for (int unsigned position = 0; position < code_bits; position++) begin
         if (code[index_of_position[position]] === 1'b1) begin
            word[position] = 1'b1;
            position_xor = position_xor ^ position;
            parity = !parity;
         end
      end
      syndrome = position_xor;
      if (parity) begin
         syndrome[hamming_bits] = 1'b1;
         if (position_xor < code_bits) begin
            word[position_xor] = !word[position_xor];
            status = HEXK_ECC_CORRECTED;
         end else begin
            status = HEXK_ECC_UNCORRECTABLE;
         end
      end else if (position_xor != 0) begin
         status = HEXK_ECC_UNCORRECTABLE;
      end
      data = '0;
      for (int unsigned i = 0; i < data_bits; i++) begin
         data[i] = word[position_of_data[i]];
      end
      return status;
   endfunction : decode

   // Index of the code word bit that a syndrome points at, or -1 when it points at no single bit.
   function int error_index(int unsigned syndrome);
      int unsigned position = syndrome & ((32'd1 << hamming_bits) - 1);
      if ((syndrome >> hamming_bits) != 1 || position >= code_bits) begin
         return -1;
      end
      return int'(index_of_position[position]);
   endfunction : error_index

   // Returns code with the bit at index flipped.
   function hexk_bits_t flip(hexk_bits_t code, int unsigned index);
      hexk_bits_t result = code;
      if (index >= code_bits) begin
         $error("hexk_ecc::flip: index %0d is not in 0..%0d", index, code_bits - 1);
         return code;
      end
      result[index] = !(code[index] === 1'b1);
      return result;
   endfunction : flip

   // Returns code with num_errors different, randomly chosen bits flipped.
   function hexk_bits_t inject(hexk_bits_t code, int unsigned num_errors = 1);
      hexk_bits_t  result = code;
      int unsigned remaining = num_errors;
      if (num_errors > code_bits) begin
         $error("hexk_ecc::inject: %0d errors do not fit a code word of %0d bits", num_errors, code_bits);
         remaining = code_bits;
      end
      // Each bit is taken with the probability (errors still to place) / (bits still to visit),
      // which places exactly num_errors errors and makes every set of bits equally likely.
      for (int unsigned index = 0; index < code_bits; index++) begin
         if ($urandom_range(code_bits - index - 1) < remaining) begin
            result[index] = !(code[index] === 1'b1);
            remaining--;
         end
      end
      return result;
   endfunction : inject

   // A vector whose lowest width bits are X: the result for an input with an X or Z bit.
   local static function hexk_bits_t all_unknown(int unsigned width);
      hexk_bits_t result = '0;
      for (int unsigned i = 0; i < width; i++) begin
         result[i] = 1'bx;
      end
      return result;
   endfunction : all_unknown

   // Number of Hamming check bits for width data bits: the smallest r with 2^r >= width + r + 1.
   local static function int unsigned hamming_width_of(int unsigned width);
      int unsigned result = 1;
      while ((32'd1 << result) < (width + result + 1)) begin
         result++;
      end
      return result;
   endfunction : hamming_width_of

   // Number of bits of the code word for width data bits.
   local static function int unsigned code_width_of(int unsigned width);
      return width + hamming_width_of(width) + 1;
   endfunction : code_width_of

   // Fills the two position tables for the data width and the layout of the object.
   local function void map_positions();
      int unsigned num_check = 0;
      int unsigned num_data = 0;
      bit          interleaved = (bit_layout == HEXK_ECC_INTERLEAVED);
      index_of_position = new[code_bits];
      position_of_data = new[data_bits];
      index_of_position[0] = interleaved ? 0 : (code_bits - 1);
      for (int unsigned position = 1; position < code_bits; position++) begin
         if ((position & (position - 1)) == 0) begin
            index_of_position[position] = interleaved ? position : (data_bits + num_check);
            num_check++;
         end else begin
            index_of_position[position] = interleaved ? position : num_data;
            position_of_data[num_data]  = position;
            num_data++;
         end
      end
   endfunction : map_positions

   // Code word of data in position order: bit 0 is the overall parity, bit p the bit at position p.
   local function hexk_bits_t encode_positions(hexk_bits_t data);
      hexk_bits_t  word = '0;
      int unsigned position_xor = 0;
      bit          parity = 1'b0;
      for (int unsigned i = 0; i < data_bits; i++) begin
         if (data[i] === 1'b1) begin
            word[position_of_data[i]] = 1'b1;
            position_xor = position_xor ^ position_of_data[i];
            parity = !parity;
         end
      end
      // Check bit i is the parity of the data bits at the positions that have bit i set,
      // which is bit i of the XOR of the positions of the data bits that are 1.
      for (int unsigned i = 0; i < hamming_bits; i++) begin
         if (position_xor[i]) begin
            word[32'd1<<i] = 1'b1;
            parity = !parity;
         end
      end
      word[0] = parity;
      return word;
   endfunction : encode_positions

endclass : hexk_ecc

`endif  // HEXK_ECC_SV
