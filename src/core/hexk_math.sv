// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_math.sv
//
// Bit and integer helpers as static functions: clamp, powers of two, alignment, range
// overlap, population count, parity, bit and byte reversal, sign extension and masks.
// Call them as hexk_math::align_up(...); the class is abstract and never constructed.
// Integer helpers work on 64-bit values. Bit-vector helpers take a hexk_bits_t, a vector of
// HEXK_MAX_WIDTH bits (default 1024, see hexk_core_pkg.sv), and an explicit width, so one
// function serves every width. Narrower arguments are zero-extended by the call; strict
// linters want the extension written as a cast, hexk_bits_t'(value).
// An illegal argument (for example an alignment of 0) is reported with $error and the
// function returns the value documented in docs/api/hexk_math.md.
//
//! @module    hexk_math
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_MATH_SV
`define HEXK_MATH_SV

virtual class hexk_math;

   // Number of bits of the vector arguments and results of the bit-vector helpers.
   localparam int unsigned MAX_WIDTH = $bits(hexk_bits_t);

   // Number of bits of the 64-bit integer helpers.
   localparam int unsigned INT_WIDTH = $bits(longint);

   // Number of bits in a byte, for swap_bytes.
   localparam int unsigned BYTE_WIDTH = 8;

   // Returns v limited to the range lo to hi (inclusive).
   static function longint clamp(longint v, longint lo, longint hi);
      if (lo > hi) begin
         $error("hexk_math::clamp: lo (%0d) is greater than hi (%0d)", lo, hi);
         return lo;
      end
      if (v < lo) begin
         return lo;
      end
      return (v > hi) ? hi : v;
   endfunction : clamp

   // Returns the unsigned v limited to the range lo to hi (inclusive).
   static function longint unsigned clamp_u(longint unsigned v, longint unsigned lo, longint unsigned hi);
      if (lo > hi) begin
         $error("hexk_math::clamp_u: lo (%0d) is greater than hi (%0d)", lo, hi);
         return lo;
      end
      if (v < lo) begin
         return lo;
      end
      return (v > hi) ? hi : v;
   endfunction : clamp_u

   // True when v is a power of two; 0 is not.
   static function bit is_pow2(longint unsigned v);
      return v != 0 && (v & (v - 1)) == 0;
   endfunction : is_pow2

   // Smallest n with 2**n >= v; 0 for v of 0 or 1.
   static function int unsigned log2_ceil(longint unsigned v);
      int unsigned result;
      if (v <= 1) begin
         return 0;
      end
      for (longint unsigned rest = v - 1; rest != 0; rest >>= 1) begin
         result++;
      end
      return result;
   endfunction : log2_ceil

   // Largest multiple of align that is not above v; align may be any value except 0.
   static function longint unsigned align_down(longint unsigned v, longint unsigned align);
      if (align == 0) begin
         $error("hexk_math::align_down: align is 0");
         return v;
      end
      return v - (v % align);
   endfunction : align_down

   // Smallest multiple of align that is not below v; align may be any value except 0.
   // When that multiple does not fit 64 bits, an $error is issued and v is returned.
   static function longint unsigned align_up(longint unsigned v, longint unsigned align);
      longint unsigned excess;
      longint unsigned step;
      longint unsigned largest = '1;
      if (align == 0) begin
         $error("hexk_math::align_up: align is 0");
         return v;
      end
      excess = v % align;
      if (excess == 0) begin
         return v;
      end
      step = align - excess;
      if (v > largest - step) begin
         $error("hexk_math::align_up: no multiple of 'h%0h at or above 'h%0h fits 64 bits", align, v);
         return v;
      end
      return v + step;
   endfunction : align_up

   // True when v is a multiple of align; align may be any value except 0.
   static function bit is_aligned(longint unsigned v, longint unsigned align);
      if (align == 0) begin
         $error("hexk_math::is_aligned: align is 0");
         return 0;
      end
      return (v % align) == 0;
   endfunction : is_aligned

   // True when the inclusive ranges a_lo..a_hi and b_lo..b_hi share a value; a range with lo > hi is empty.
   static function bit ranges_overlap(longint unsigned a_lo, longint unsigned a_hi, longint unsigned b_lo,
                                      longint unsigned b_hi);
      if (a_lo > a_hi || b_lo > b_hi) begin
         return 0;
      end
      return a_lo <= b_hi && b_lo <= a_hi;
   endfunction : ranges_overlap

   // Number of bits of v that are 1; X and Z bits are not counted.
   static function int unsigned popcount(hexk_bits_t v);
      return $unsigned($countones(v));
   endfunction : popcount

   // Parity bit for v: makes the number of ones even, or odd when odd is set; X and Z bits count as 0.
   static function bit parity(hexk_bits_t v, bit odd = 0);
      bit ones_are_odd = (popcount(v) % 2) == 1;
      return ones_are_odd ^ odd;
   endfunction : parity

   // Bits width-1..0 of v in reverse order; the bits above are 0.
   static function hexk_bits_t reverse_bits(hexk_bits_t v, int unsigned width);
      hexk_bits_t  result = '0;
      int unsigned count = legal_width(width, "reverse_bits");
      for (int unsigned i = 0; i < count; i++) begin
         result[i] = v[count-1-i];
      end
      return result;
   endfunction : reverse_bits

   // The low num_bytes bytes of v in reverse byte order; the bits above are 0.
   static function hexk_bits_t swap_bytes(hexk_bits_t v, int unsigned num_bytes);
      hexk_bits_t  result = '0;
      int unsigned count = legal_width(num_bytes * BYTE_WIDTH, "swap_bytes") / BYTE_WIDTH;
      for (int unsigned i = 0; i < count; i++) begin
         result[i*BYTE_WIDTH+:BYTE_WIDTH] = v[(count-1-i)*BYTE_WIDTH+:BYTE_WIDTH];
      end
      return result;
   endfunction : swap_bytes

   // Reads bits width-1..0 of v as a two's-complement number; width is 1 to 64.
   static function longint sign_extend(longint unsigned v, int unsigned width);
      longint unsigned low_bits;
      longint unsigned sign_bits;
      if (width == 0 || width > INT_WIDTH) begin
         $error("hexk_math::sign_extend: width %0d is not in 1..%0d", width, INT_WIDTH);
         return longint'(v);
      end
      if (width == INT_WIDTH) begin
         return longint'(v);
      end
      low_bits  = (64'd1 << width) - 1;
      sign_bits = v[width-1] ? ~low_bits : 0;
      return longint'((v & low_bits) | sign_bits);
   endfunction : sign_extend

   // Vector with the low width bits set.
   static function hexk_bits_t mask(int unsigned width);
      hexk_bits_t ones = '1;
      return ones >> (MAX_WIDTH - legal_width(width, "mask"));
   endfunction : mask

   // Returns width, or MAX_WIDTH with an $error when width is larger than the vectors.
   local static function int unsigned legal_width(int unsigned width, string caller);
      if (width > MAX_WIDTH) begin
         $error("hexk_math::%s: %0d bits do not fit HEXK_MAX_WIDTH (%0d)", caller, width, MAX_WIDTH);
         return MAX_WIDTH;
      end
      return width;
   endfunction : legal_width

endclass : hexk_math

`endif  // HEXK_MATH_SV
