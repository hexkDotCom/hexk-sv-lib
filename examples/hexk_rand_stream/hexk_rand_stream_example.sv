// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_stream_example.sv
//
// Minimal use of hexk_rand_stream in a module: a ready pattern for random back-pressure, a
// weighted choice and a gap length, all from one stream with its own seed, so the pattern
// does not change when other random code in the testbench does.
// Needs only src/core/hexk_core.f.

module hexk_rand_stream_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_rand_stream;

   localparam int unsigned STREAM_SEED = 2026;
   localparam int unsigned READY_PERCENT = 70;
   localparam int unsigned CYCLES = 8;

   string           ready_pattern;
   int unsigned     burst_weights [$];
   int unsigned     burst_kind;
   longint          gap_cycles;
   hexk_rand_stream backpressure;

   initial begin
      backpressure = new("ready");
      backpressure.seed(STREAM_SEED);
      burst_weights = '{6, 3, 1};

      repeat (CYCLES) begin
         ready_pattern = {ready_pattern, backpressure.chance(READY_PERCENT) ? "1" : "0"};
      end
      $info("ready for the next %0d cycles: %s", CYCLES, ready_pattern);
      // One draw per statement: the order of the arguments of one call differs between simulators.
      burst_kind = backpressure.pick_weighted(burst_weights);
      gap_cycles = backpressure.uniform(1, 4);
      $info("burst kind %0d, then a gap of %0d cycles", burst_kind, gap_cycles);
   end

endmodule : hexk_rand_stream_example
