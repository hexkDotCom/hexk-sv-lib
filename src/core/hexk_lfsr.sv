// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_lfsr.sv
//
// Linear feedback shift register of 1 to 64 bits, Galois or Fibonacci form.
// Create one with hexk_lfsr::maximal(width) for a maximal-length sequence (period 2**width - 1)
// from the built-in tap table, or with new() for your own taps. next() advances one step
// and returns the new state. Use it for pseudo-random patterns that must match a hardware
// LFSR bit for bit, or for cheap reproducible data; it is not a randomization source.
// Taps are a bit mask of the feedback polynomial: bit i stands for the term x**(i+1), so
// bit width-1 is always set. The all-zero state is never reached and never accepted.
// Illegal arguments are reported with $error; see docs/api/hexk_lfsr.md for what is used instead.
//
//! @module    hexk_lfsr
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_LFSR_SV
`define HEXK_LFSR_SV

class hexk_lfsr;

   // Form of the register: Fibonacci shifts left and feeds the XOR of the tapped bits into bit 0;
   // Galois shifts right and XORs the taps into the state when the bit shifted out is 1.
   typedef enum bit {
      HEXK_LFSR_FIBONACCI,
      HEXK_LFSR_GALOIS
   } kind_e;

   // Largest register width.
   localparam int unsigned MAX_WIDTH = 64;

   // Largest width for which period() counts the steps.
   localparam int unsigned MAX_PERIOD_WIDTH = 24;

   local int unsigned     reg_width;
   local longint unsigned tap_mask;
   local longint unsigned current;
   local longint unsigned state_mask;
   local kind_e           form;

   // Creates a register of width bits (1 to 64) with the given taps, start state and form.
   function new(int unsigned width, longint unsigned taps, longint unsigned seed = 1, kind_e kind = HEXK_LFSR_GALOIS);
      reg_width = width;
      if (width == 0 || width > MAX_WIDTH) begin
         $error("hexk_lfsr::new: width %0d is not in 1..%0d", width, MAX_WIDTH);
         reg_width = MAX_WIDTH;
      end
      state_mask = '1;
      state_mask = state_mask >> (MAX_WIDTH - reg_width);
      tap_mask = taps & state_mask;
      form = kind;
      if (!tap_mask[reg_width-1]) begin
         $error("hexk_lfsr::new: taps 'h%0h do not have bit %0d set, the top term of the polynomial", taps,
                reg_width - 1);
      end
      current = 1;
      set_state(seed);
   endfunction : new

   // Creates a maximal-length register (period 2**width - 1) of 2 to 64 bits from the built-in tap table.
   static function hexk_lfsr maximal(int unsigned width, longint unsigned seed = 1);
      hexk_lfsr result;
      int unsigned legal_width = width;
      if (width < 2 || width > MAX_WIDTH) begin
         $error("hexk_lfsr::maximal: width %0d is not in 2..%0d", width, MAX_WIDTH);
         legal_width = (width < 2) ? 2 : MAX_WIDTH;
      end
      result = new(legal_width, maximal_taps(legal_width), seed);
      return result;
   endfunction : maximal

   // Advances the register by one step and returns the new state.
   function longint unsigned next();
      bit feedback;
      if (form == HEXK_LFSR_GALOIS) begin
         feedback = current[0];
         current  = current >> 1;
         if (feedback) begin
            current = current ^ tap_mask;
         end
      end else begin
         feedback = ^(current & tap_mask);
         current    = (current << 1) & state_mask;
         current[0] = feedback;
      end
      return current;
   endfunction : next

   // Returns the current state.
   function longint unsigned get_state();
      return current;
   endfunction : get_state

   // Sets the state; bits above the width are ignored, and 0 is rejected because the register would stay 0.
   function void set_state(longint unsigned state);
      if ((state & state_mask) == 0) begin
         $error("hexk_lfsr::set_state: state 'h%0h is 0 within %0d bits; the state is not changed", state, reg_width);
         return;
      end
      current = state & state_mask;
   endfunction : set_state

   // Number of steps until the current state repeats, by brute force; for tests, width up to 24 only.
   // With taps that new() reported, the state may never repeat: that is an $error and gives 0.
   function longint unsigned period();
      longint unsigned start = current;
      longint unsigned steps;
      // A state that repeats does so within as many steps as the register has states.
      longint unsigned limit = 64'd1 << reg_width;
      if (reg_width > MAX_PERIOD_WIDTH) begin
         $error("hexk_lfsr::period: width %0d is above %0d; not counted", reg_width, MAX_PERIOD_WIDTH);
         return 0;
      end
      do begin
         void'(next());
         steps++;
      end while (current != start && steps < limit);
      if (current != start) begin
         $error("hexk_lfsr::period: state 'h%0h does not repeat with taps 'h%0h", start, tap_mask);
         return 0;
      end
      return steps;
   endfunction : period

   // Taps of a primitive polynomial of the given degree (2 to 64), with as few terms as possible.
   // The table was computed and checked for primitivity; trinomials are used where one exists.
   local static function longint unsigned maximal_taps(int unsigned width);
      case (width)
         2: return 64'h0000_0000_0000_0003;  // x^2 + x + 1
         3: return 64'h0000_0000_0000_0005;  // x^3 + x + 1
         4: return 64'h0000_0000_0000_0009;  // x^4 + x + 1
         5: return 64'h0000_0000_0000_0012;  // x^5 + x^2 + 1
         6: return 64'h0000_0000_0000_0021;  // x^6 + x + 1
         7: return 64'h0000_0000_0000_0041;  // x^7 + x + 1
         8: return 64'h0000_0000_0000_00C3;  // x^8 + x^7 + x^2 + x + 1
         9: return 64'h0000_0000_0000_0108;  // x^9 + x^4 + 1
         10: return 64'h0000_0000_0000_0204;  // x^10 + x^3 + 1
         11: return 64'h0000_0000_0000_0402;  // x^11 + x^2 + 1
         12: return 64'h0000_0000_0000_0883;  // x^12 + x^8 + x^2 + x + 1
         13: return 64'h0000_0000_0000_1013;  // x^13 + x^5 + x^2 + x + 1
         14: return 64'h0000_0000_0000_2803;  // x^14 + x^12 + x^2 + x + 1
         15: return 64'h0000_0000_0000_4001;  // x^15 + x + 1
         16: return 64'h0000_0000_0000_8805;  // x^16 + x^12 + x^3 + x + 1
         17: return 64'h0000_0000_0001_0004;  // x^17 + x^3 + 1
         18: return 64'h0000_0000_0002_0040;  // x^18 + x^7 + 1
         19: return 64'h0000_0000_0004_0013;  // x^19 + x^5 + x^2 + x + 1
         20: return 64'h0000_0000_0008_0004;  // x^20 + x^3 + 1
         21: return 64'h0000_0000_0010_0002;  // x^21 + x^2 + 1
         22: return 64'h0000_0000_0020_0001;  // x^22 + x + 1
         23: return 64'h0000_0000_0040_0010;  // x^23 + x^5 + 1
         24: return 64'h0000_0000_0080_0043;  // x^24 + x^7 + x^2 + x + 1
         25: return 64'h0000_0000_0100_0004;  // x^25 + x^3 + 1
         26: return 64'h0000_0000_0200_0023;  // x^26 + x^6 + x^2 + x + 1
         27: return 64'h0000_0000_0400_0013;  // x^27 + x^5 + x^2 + x + 1
         28: return 64'h0000_0000_0800_0004;  // x^28 + x^3 + 1
         29: return 64'h0000_0000_1000_0002;  // x^29 + x^2 + 1
         30: return 64'h0000_0000_2040_0003;  // x^30 + x^23 + x^2 + x + 1
         31: return 64'h0000_0000_4000_0004;  // x^31 + x^3 + 1
         32: return 64'h0000_0000_8020_0003;  // x^32 + x^22 + x^2 + x + 1
         33: return 64'h0000_0001_0000_1000;  // x^33 + x^13 + 1
         34: return 64'h0000_0002_0400_0003;  // x^34 + x^27 + x^2 + x + 1
         35: return 64'h0000_0004_0000_0002;  // x^35 + x^2 + 1
         36: return 64'h0000_0008_0000_0400;  // x^36 + x^11 + 1
         37: return 64'h0000_0010_0000_0103;  // x^37 + x^9 + x^2 + x + 1
         38: return 64'h0000_0020_0000_1005;  // x^38 + x^13 + x^3 + x + 1
         39: return 64'h0000_0040_0000_0008;  // x^39 + x^4 + 1
         40: return 64'h0000_0084_0000_0003;  // x^40 + x^35 + x^2 + x + 1
         41: return 64'h0000_0100_0000_0004;  // x^41 + x^3 + 1
         42: return 64'h0000_0200_1000_0003;  // x^42 + x^29 + x^2 + x + 1
         43: return 64'h0000_0400_0000_0803;  // x^43 + x^12 + x^2 + x + 1
         44: return 64'h0000_0820_0000_0005;  // x^44 + x^38 + x^3 + x + 1
         45: return 64'h0000_1000_0000_000D;  // x^45 + x^4 + x^3 + x + 1
         46: return 64'h0000_2000_0000_0105;  // x^46 + x^9 + x^3 + x + 1
         47: return 64'h0000_4000_0000_0010;  // x^47 + x^5 + 1
         48: return 64'h0000_8000_0800_0005;  // x^48 + x^28 + x^3 + x + 1
         49: return 64'h0001_0000_0000_0100;  // x^49 + x^9 + 1
         50: return 64'h0002_0000_0000_8003;  // x^50 + x^16 + x^2 + x + 1
         51: return 64'h0004_0000_0800_0003;  // x^51 + x^28 + x^2 + x + 1
         52: return 64'h0008_0000_0000_0004;  // x^52 + x^3 + 1
         53: return 64'h0010_0000_0000_0023;  // x^53 + x^6 + x^2 + x + 1
         54: return 64'h0020_0000_0001_0003;  // x^54 + x^17 + x^2 + x + 1
         55: return 64'h0040_0000_0080_0000;  // x^55 + x^24 + 1
         56: return 64'h0080_0200_0000_0003;  // x^56 + x^42 + x^2 + x + 1
         57: return 64'h0100_0000_0000_0040;  // x^57 + x^7 + 1
         58: return 64'h0200_0000_0004_0000;  // x^58 + x^19 + 1
         59: return 64'h0400_0000_0080_0003;  // x^59 + x^24 + x^2 + x + 1
         60: return 64'h0800_0000_0000_0001;  // x^60 + x + 1
         61: return 64'h1000_0000_0000_0013;  // x^61 + x^5 + x^2 + x + 1
         62: return 64'h2000_0000_0800_0005;  // x^62 + x^28 + x^3 + x + 1
         63: return 64'h4000_0000_0000_0001;  // x^63 + x + 1
         64: return 64'h8000_0000_0000_0403;  // x^64 + x^11 + x^2 + x + 1
         default: return 0;
      endcase
   endfunction : maximal_taps

endclass : hexk_lfsr

`endif  // HEXK_LFSR_SV
