// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_stream.sv
//
// Seed-stable stream of random numbers: an object that owns its seed and draws from it with
// the seeded system functions $dist_*, so the values do not depend on thread scheduling or on
// the randomization of other objects, and a seed gives the same values on every simulator.
// Create one stream per consumer, give it a seed with seed() when the sequence must be
// reproducible, and draw with next_u32, uniform, normal, exponential, poisson, chance or
// pick_weighted. Without seed() the start value comes from $urandom once, at construction.
// Meant for modules, interfaces and BFMs (random back-pressure, jitter) and for library
// classes; class-based stimulus keeps using rand variables and constraints.
// Illegal arguments are reported with $error; see docs/api/hexk_rand_stream.md.
//
//! @module    hexk_rand_stream
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_RAND_STREAM_SV
`define HEXK_RAND_STREAM_SV

class hexk_rand_stream;

   // The value of percent at which chance() is always true.
   localparam int unsigned PERCENT_MAX = 100;

   // The largest value of one half of next_u32().
   localparam int HALF_MAX = 65535;

   local string label;
   // Waiver for Verilator lint, which does not see that the seeded system functions read the seed.
   // verilator lint_off UNUSEDSIGNAL
   local int    state;
   // verilator lint_on UNUSEDSIGNAL

   // Creates a stream; scope is only a label for messages. The start value is drawn from $urandom.
   function new(string scope = "");
      label = scope;
      state = int'($urandom());
   endfunction : new

   // Restarts the stream from s: the same seed always gives the same sequence of draws.
   function void seed(int unsigned s);
      state = int'(s);
   endfunction : seed

   // Next value, uniformly distributed over all 32-bit values.
   // It is made of two 16-bit draws of $dist_uniform, whose algorithm the standard gives;
   // $random gives other values on some simulators for the same seed.
   function int unsigned next_u32();
      int unsigned high = $unsigned($dist_uniform(state, 0, HALF_MAX));
      int unsigned low = $unsigned($dist_uniform(state, 0, HALF_MAX));
      return (high << 16) | low;
   endfunction : next_u32

   // Value uniformly distributed over lo to hi (inclusive).
   function longint uniform(longint lo, longint hi);
      longint unsigned span;
      longint unsigned draw;
      longint unsigned excess;
      if (lo > hi) begin
         $error("hexk_rand_stream(%s)::uniform: lo (%0d) is greater than hi (%0d)", label, lo, hi);
         return lo;
      end
      // span is 0 when lo..hi covers all 64-bit values.
      span = $unsigned(hi - lo) + 1;
      draw = next_u64();
      if (span != 0) begin
         // 2^64 is a multiple of few spans. The lowest (2^64 modulo span) draws would make the
         // low end of the range more likely than the rest, so such a draw is taken again.
         excess = (-span) % span;
         while (draw < excess) begin
            draw = next_u64();
         end
         draw = draw % span;
      end
      return lo + longint'(draw);
   endfunction : uniform

   // Two values of next_u32() as one 64-bit value, the first one high. The two draws are separate
   // statements: the order in which the operands of a concatenation are evaluated is not defined.
   local function longint unsigned next_u64();
      longint unsigned high = longint'(next_u32());
      return (high << 32) | longint'(next_u32());
   endfunction : next_u64

   // Normally distributed value with the given mean and standard deviation ($dist_normal).
   function int normal(int mean, int std_dev);
      if (std_dev < 0) begin
         $error("hexk_rand_stream(%s)::normal: std_dev (%0d) is negative", label, std_dev);
         return mean;
      end
      return $dist_normal(state, mean, std_dev);
   endfunction : normal

   // Exponentially distributed value with the given mean, which must be positive ($dist_exponential).
   function int exponential(int mean);
      if (mean <= 0) begin
         $error("hexk_rand_stream(%s)::exponential: mean (%0d) is not positive", label, mean);
         return 0;
      end
      return $dist_exponential(state, mean);
   endfunction : exponential

   // Poisson distributed value with the given mean, which must be positive ($dist_poisson).
   function int poisson(int mean);
      if (mean <= 0) begin
         $error("hexk_rand_stream(%s)::poisson: mean (%0d) is not positive", label, mean);
         return 0;
      end
      return $dist_poisson(state, mean);
   endfunction : poisson

   // True with a probability of percent in 100; 0 is never true, 100 or more is always true.
   function bit chance(int unsigned percent);
      int draw = $dist_uniform(state, 0, int'(PERCENT_MAX) - 1);
      return $unsigned(draw) < percent;
   endfunction : chance

   // Index into weights, picked with a probability proportional to its weight.
   function int unsigned pick_weighted(const ref int unsigned weights[$]);
      longint unsigned total;
      longint unsigned draw;
      longint unsigned weight;
      foreach (weights[i]) begin
         weight = $unsigned(longint'(weights[i]));
         total += weight;
      end
      if (total == 0) begin
         $error("hexk_rand_stream(%s)::pick_weighted: no weight is above 0", label);
         return 0;
      end
      draw = $unsigned(uniform(0, longint'(total - 1)));
      foreach (weights[i]) begin
         weight = $unsigned(longint'(weights[i]));
         if (draw < weight) begin
            return $unsigned(i);
         end
         draw -= weight;
      end
      return 0;
   endfunction : pick_weighted

endclass : hexk_rand_stream

`endif  // HEXK_RAND_STREAM_SV
