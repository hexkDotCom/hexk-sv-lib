// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_stream_unit_test.sv
//
// SVUnit tests of hexk_rand_stream.
// Reproducibility: the same seed gives the same draws, different seeds and unseeded streams
// do not, and a seed gives the same values on every simulator (checksums of the values that
// Questa 2024.1, VCS X-2025.06 and Verilator 5.046 gave, 2026-10-14). Distributions: 10000
// draws each, with the observed mean or share inside a band that a correct generator misses
// with negligible probability. Illegal arguments make the
// library call $error on purpose; those tests check the returned value. Results are
// compared as text (see tests/unit/README.md).
// Runs on Verilator: make test SIM=verilator TEST=hexk_rand_stream.

`include "svunit_defines.svh"

module hexk_rand_stream_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_rand_stream;

   // Number of draws per distribution test, as a repeat count and as a 64-bit operand.
   localparam int unsigned DRAWS = 10000;
   localparam longint DRAW_COUNT = 10000;

   string          name = "hexk_rand_stream_ut";
   svunit_testcase svunit_ut;

   int unsigned    weights                      [$];

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // "inside" when lo <= value <= hi, otherwise the value, so that a failure shows it.
   function automatic string band(longint value, longint lo, longint hi);
      return (value >= lo && value <= hi) ? "inside" : $sformatf("%0d", value);
   endfunction : band

   // Checksums of 1000 draws for fixed seeds, as "<first four next_u32> <next_u32> <uniform> <normal>
   // <pick_weighted>"; a checksum is sum * 31 + value over the draws, in 64 bits.
   function automatic string golden_draws();
      hexk_rand_stream stream = new("golden");
      int unsigned     picks                  [$] = '{1, 0, 5, 20, 3};
      longint unsigned sums                   [4];
      int unsigned     value;
      string           first;
      stream.seed(12345);
      for (int i = 0; i < 1000; i++) begin
         value   = stream.next_u32();
         sums[0] = sums[0] * 64'd31 + 64'(value);
         if (i < 4) begin
            first = {first, $sformatf("%0d ", value)};
         end
      end
      stream.seed(12345);
      for (int i = 0; i < 1000; i++) begin
         sums[1] = sums[1] * 64'd31 + $unsigned(stream.uniform(-1000, 1000000));
      end
      stream.seed(99);
      for (int i = 0; i < 1000; i++) begin
         sums[2] = sums[2] * 64'd31 + $unsigned(64'(stream.normal(100, 15)));
      end
      stream.seed(3);
      for (int i = 0; i < 1000; i++) begin
         sums[3] = sums[3] * 64'd31 + 64'(stream.pick_weighted(picks));
      end
      return $sformatf("%s%0d %0d %0d %0d", first, sums[0], sums[1], sums[2], sums[3]);
   endfunction : golden_draws

   // One draw of every kind from stream, as text.
   function automatic string mixed_draws(hexk_rand_stream stream);
      string text;
      repeat (4) begin
         text = {
            text,
            $sformatf(
                "%0d %0d %0d %0d %0d %0b;",
                stream.next_u32(),
                stream.uniform(
                    -1000, 1000
                ),
                stream.normal(
                    50, 5
                ),
                stream.exponential(
                    20
                ),
                stream.poisson(
                    7
                ),
                stream.chance(
                    50
                )
            )
         };
      end
      return text;
   endfunction : mixed_draws

   // "same" when two streams seeded with seed_a and seed_b draw the same values.
   function automatic string compare_seeds(int unsigned seed_a, int unsigned seed_b);
      hexk_rand_stream first = new("first");
      hexk_rand_stream second = new("second");
      first.seed(seed_a);
      second.seed(seed_b);
      return (mixed_draws(first) == mixed_draws(second)) ? "same" : "different";
   endfunction : compare_seeds

   // "same" when two streams that were never seeded draw the same values.
   function automatic string compare_unseeded();
      hexk_rand_stream first = new("first");
      hexk_rand_stream second = new("second");
      return (mixed_draws(first) == mixed_draws(second)) ? "same" : "different";
   endfunction : compare_unseeded

   // "same" when a stream repeats its draws after being seeded again with the same value.
   function automatic string reseed();
      hexk_rand_stream stream = new("reseed");
      string first_draws;
      stream.seed(77);
      first_draws = mixed_draws(stream);
      stream.seed(77);
      return (mixed_draws(stream) == first_draws) ? "same" : "different";
   endfunction : reseed

   // Number of distinct values in 100 draws of next_u32.
   function automatic string distinct_u32();
      hexk_rand_stream stream = new("u32");
      bit seen[int unsigned];
      stream.seed(1);
      repeat (100) begin
         seen[stream.next_u32()] = 1;
      end
      return $sformatf("%0d", seen.size());
   endfunction : distinct_u32

   // Smallest and largest bucket count of DRAWS draws of uniform(lo, lo + 9), and whether all draws were in range.
   function automatic string uniform_buckets(longint lo);
      hexk_rand_stream stream = new("uniform");
      longint count[10];
      longint smallest = DRAW_COUNT;
      longint largest;
      longint value;
      stream.seed(2);
      repeat (DRAWS) begin
         value = stream.uniform(lo, lo + 9);
         if (value < lo || value > lo + 9) begin
            return $sformatf("out of range: %0d", value);
         end
         count[int'(value-lo)]++;
      end
      foreach (count[i]) begin
         smallest = (count[i] < smallest) ? count[i] : smallest;
         largest  = (count[i] > largest) ? count[i] : largest;
      end
      return {band(smallest, 850, 1150), " ", band(largest, 850, 1150)};
   endfunction : uniform_buckets

   // uniform(value, value) for a few draws: always value.
   function automatic string uniform_point(longint value);
      hexk_rand_stream stream = new("point");
      repeat (20) begin
         if (stream.uniform(value, value) != value) begin
            return "moved";
         end
      end
      return "fixed";
   endfunction : uniform_point

   // Whether DRAWS draws over the full 64-bit range hit both halves of the range.
   function automatic string uniform_full_range();
      hexk_rand_stream stream = new("full");
      longint negative;
      stream.seed(3);
      repeat (DRAWS) begin
         if (stream.uniform(64'sh8000_0000_0000_0000, 64'sh7FFF_FFFF_FFFF_FFFF) < 0) begin
            negative++;
         end
      end
      return band(negative, 4700, 5300);
   endfunction : uniform_full_range

   // DRAWS draws over a range of 3 * 2^62 values, which 2^64 is not a multiple of: how many
   // fall into the lowest third of the range. A plain modulo of a 64-bit draw puts half of
   // the draws there.
   function automatic string uniform_lowest_third();
      hexk_rand_stream stream = new("third");
      longint lowest;
      stream.seed(4);
      repeat (DRAWS) begin
         if (stream.uniform(64'sh8000_0000_0000_0000, 64'sh3FFF_FFFF_FFFF_FFFF) < 64'shC000_0000_0000_0000) begin
            lowest++;
         end
      end
      return band(lowest, 3100, 3570);
   endfunction : uniform_lowest_third

   // Mean of DRAWS draws of normal(100, 10), exponential(50) or poisson(8), selected by kind.
   function automatic longint mean_of(string kind);
      hexk_rand_stream stream = new(kind);
      longint sum;
      stream.seed(4);
      repeat (DRAWS) begin
         case (kind)
            "normal":      sum += longint'(stream.normal(100, 10));
            "exponential": sum += longint'(stream.exponential(50));
            default:       sum += longint'(stream.poisson(8));
         endcase
      end
      return sum / DRAW_COUNT;
   endfunction : mean_of

   // Share of DRAWS draws of normal(100, 10) within one standard deviation, in percent.
   function automatic longint normal_within_one_sigma();
      hexk_rand_stream stream = new("sigma");
      longint hits;
      int value;
      stream.seed(5);
      repeat (DRAWS) begin
         value = stream.normal(100, 10);
         if (value >= 90 && value <= 110) begin
            hits++;
         end
      end
      return (hits * 100) / DRAW_COUNT;
   endfunction : normal_within_one_sigma

   // Number of true results in DRAWS calls of chance(percent).
   function automatic longint chance_count(int unsigned percent);
      hexk_rand_stream stream = new("chance");
      longint hits;
      stream.seed(6);
      repeat (DRAWS) begin
         if (stream.chance(percent)) begin
            hits++;
         end
      end
      return hits;
   endfunction : chance_count

   // Fills the module-level weights queue.
   function automatic void set_weights(int unsigned w0, int unsigned w1, int unsigned w2, int unsigned w3);
      weights = '{w0, w1, w2, w3};
   endfunction : set_weights

   // How often index was picked in DRAWS calls of pick_weighted with the module-level weights.
   function automatic longint picks_of(int unsigned index);
      hexk_rand_stream stream = new("weights");
      longint hits;
      stream.seed(7);
      repeat (DRAWS) begin
         if (stream.pick_weighted(weights) == index) begin
            hits++;
         end
      end
      return hits;
   endfunction : picks_of

   // Values returned for illegal arguments, as text.
   function automatic string illegal_arguments();
      hexk_rand_stream stream = new("illegal");
      int unsigned none[$];
      set_weights(0, 0, 0, 0);
      return $sformatf(
          "%0d %0d %0d %0d %0d %0d",
          stream.uniform(
              5, 1
          ),
          stream.normal(
              9, -1
          ),
          stream.exponential(
              0
          ),
          stream.poisson(
              -3
          ),
          stream.pick_weighted(
              weights
          ),
          stream.pick_weighted(
              none
          )
      );
   endfunction : illegal_arguments

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(the_same_seed_gives_the_same_draws)
      `FAIL_UNLESS_STR_EQUAL(compare_seeds(12345, 12345), "same")
      `FAIL_UNLESS_STR_EQUAL(compare_seeds(0, 0), "same")
   `SVTEST_END

   `SVTEST(a_seed_gives_the_same_values_on_every_simulator)
      `FAIL_UNLESS_STR_EQUAL(golden_draws(),
         {"852682203 1023434292 1639445438 1989295849 2221845630432473268 8759893763229480754 ",
          "16604679718721442830 7924385867600444351"})
   `SVTEST_END

   `SVTEST(different_seeds_give_different_draws)
      `FAIL_UNLESS_STR_EQUAL(compare_seeds(12345, 12346), "different")
   `SVTEST_END

   `SVTEST(seeding_again_restarts_the_sequence)
      `FAIL_UNLESS_STR_EQUAL(reseed(), "same")
   `SVTEST_END

   `SVTEST(unseeded_streams_differ_from_each_other)
      `FAIL_UNLESS_STR_EQUAL(compare_unseeded(), "different")
   `SVTEST_END

   `SVTEST(next_u32_keeps_changing)
      `FAIL_UNLESS_STR_EQUAL(distinct_u32(), "100")
   `SVTEST_END

   `SVTEST(uniform_covers_the_range_evenly)
      `FAIL_UNLESS_STR_EQUAL(uniform_buckets(0), "inside inside")
      `FAIL_UNLESS_STR_EQUAL(uniform_buckets(-5), "inside inside")
      `FAIL_UNLESS_STR_EQUAL(uniform_buckets(64'sh7FFF_FFFF_FFFF_FFF6), "inside inside")
   `SVTEST_END

   `SVTEST(uniform_of_a_single_value_returns_it)
      `FAIL_UNLESS_STR_EQUAL(uniform_point(42), "fixed")
      `FAIL_UNLESS_STR_EQUAL(uniform_point(-42), "fixed")
   `SVTEST_END

   `SVTEST(uniform_handles_the_full_64_bit_range)
      `FAIL_UNLESS_STR_EQUAL(uniform_full_range(), "inside")
   `SVTEST_END

   `SVTEST(uniform_is_even_over_a_range_that_does_not_divide_the_64_bit_range)
      `FAIL_UNLESS_STR_EQUAL(uniform_lowest_third(), "inside")
   `SVTEST_END

   `SVTEST(normal_has_the_requested_mean_and_spread)
      `FAIL_UNLESS_STR_EQUAL(band(mean_of("normal"), 99, 101), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(normal_within_one_sigma(), 64, 76), "inside")
   `SVTEST_END

   `SVTEST(exponential_has_the_requested_mean)
      `FAIL_UNLESS_STR_EQUAL(band(mean_of("exponential"), 46, 54), "inside")
   `SVTEST_END

   `SVTEST(poisson_has_the_requested_mean)
      `FAIL_UNLESS_STR_EQUAL(band(mean_of("poisson"), 7, 9), "inside")
   `SVTEST_END

   `SVTEST(chance_is_true_in_the_requested_share_of_calls)
      `FAIL_UNLESS_STR_EQUAL(band(chance_count(25), 2300, 2700), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(chance_count(90), 8800, 9200), "inside")
   `SVTEST_END

   `SVTEST(chance_of_zero_is_never_true_and_of_100_always)
      `FAIL_UNLESS_STR_EQUAL(band(chance_count(0), 0, 0), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(chance_count(100), DRAW_COUNT, DRAW_COUNT), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(chance_count(250), DRAW_COUNT, DRAW_COUNT), "inside")
   `SVTEST_END

   `SVTEST(pick_weighted_follows_the_weights)
      set_weights(1, 3, 0, 6);
      `FAIL_UNLESS_STR_EQUAL(band(picks_of(0), 850, 1150), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(picks_of(1), 2750, 3250), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(picks_of(2), 0, 0), "inside")
      `FAIL_UNLESS_STR_EQUAL(band(picks_of(3), 5700, 6300), "inside")
   `SVTEST_END

   `SVTEST(pick_weighted_with_one_weight_always_picks_it)
      set_weights(0, 0, 9, 0);
      `FAIL_UNLESS_STR_EQUAL(band(picks_of(2), DRAW_COUNT, DRAW_COUNT), "inside")
   `SVTEST_END

   `SVTEST(illegal_arguments_return_the_documented_values)
      `FAIL_UNLESS_STR_EQUAL(illegal_arguments(), "5 9 0 0 0 0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_rand_stream_unit_test
