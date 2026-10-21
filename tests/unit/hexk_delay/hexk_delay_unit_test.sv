// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_unit_test.sv
//
// SVUnit tests of hexk_delay and hexk_delay_cfg.
// Every test gets a fresh cfg and builds its generator with a fixed seed, so the delays it
// sees are the same in every run. Tests of a distribution draw a few hundred delays and look
// at their smallest, largest and average value. The knob perf_mode is defined and locked by
// the tests that need it, and the knobs are reset after every test. The error for an illegal
// cfg is demoted by a report catcher and counted.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_delay.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_delay_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_delay_cfg;
   import hexk_uvm_pkg::hexk_delay_mode_e;
   import hexk_uvm_pkg::HEXK_DELAY_NONE;
   import hexk_uvm_pkg::HEXK_DELAY_CONSTANT;
   import hexk_uvm_pkg::HEXK_DELAY_UNIFORM;
   import hexk_uvm_pkg::HEXK_DELAY_NORMAL;
   import hexk_uvm_pkg::HEXK_DELAY_EXPONENTIAL;
   import hexk_uvm_pkg::HEXK_DELAY_BURSTY;
   import hexk_uvm_pkg::HEXK_DELAY_WEIGHTED;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   localparam int unsigned SEED = 20261012;

   string              name = "hexk_delay_ut";
   svunit_testcase     svunit_ut;

   hexk_report_catcher catcher;
   hexk_delay_cfg      cfg;
   hexk_delay          delay;
   event               clock_tick;
   realtime            start_time;
   string              outcome;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_DELAY_CFG$", UVM_ERROR, "", 0, -1, UVM_INFO);
      hexk_knobs::reset_for_test();
      cfg        = hexk_delay_cfg::type_id::create("cfg");
      delay      = new(cfg, "ut_delay", SEED);
      start_time = $realtime;
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_knobs::reset_for_test();
      catcher.clear();
   endtask : teardown

   // Sets the mode of the cfg.
   function automatic void set_mode(hexk_delay_mode_e mode);
      cfg.mode = mode;
   endfunction : set_mode

   // Sets the limits of uniform delays.
   function automatic void set_range(int unsigned lo, int unsigned hi);
      cfg.lo = lo;
      cfg.hi = hi;
   endfunction : set_range

   // Sets mean and standard deviation.
   function automatic void set_mean(int unsigned mean, int unsigned std_dev = 0);
      cfg.mean    = mean;
      cfg.std_dev = std_dev;
   endfunction : set_mean

   // Sets the limits of the bursts and of the delays between them.
   function automatic void set_bursts(int unsigned on_min, int unsigned on_max, int unsigned off_min,
                                      int unsigned off_max);
      cfg.burst_on_min  = on_min;
      cfg.burst_on_max  = on_max;
      cfg.burst_off_min = off_min;
      cfg.burst_off_max = off_max;
   endfunction : set_bursts

   // Gives a delay value a weight.
   function automatic void set_weight(int unsigned value, int unsigned weight);
      cfg.weights[value] = weight;
   endfunction : set_weight

   // The illegal reason of every mode of hexk_delay_mode_e with the default values and one weight, as
   // "<mode>=<reason>" separated by blanks; a legal mode has an empty reason.
   function automatic string reasons_of_all_modes();
      hexk_delay_mode_e mode = mode.first();
      string            text = "";
      cfg.weights[1] = 1;
      do begin
         cfg.mode = mode;
         text     = {text, mode.name(), "=", cfg.illegal_reason(), " "};
         mode     = mode.next();
      end while (mode != mode.first());
      return text;
   endfunction : reasons_of_all_modes

   // Why a cfg whose mode is no value of hexk_delay_mode_e is illegal.
   function automatic string unknown_mode_reason();
      cfg.mode = hexk_delay_mode_e'(7);
      return cfg.illegal_reason();
   endfunction : unknown_mode_reason

   // The next count delays, separated by blanks.
   function automatic string sequence_of(int unsigned count, hexk_delay source = null);
      string       text;
      hexk_delay   from = (source == null) ? delay : source;
      int unsigned value;
      repeat (count) begin
         value = from.next();
         text  = {text, $sformatf("%0d ", value)};
      end
      return text;
   endfunction : sequence_of

   // Smallest and largest of the next count delays, as "<min> <max>".
   function automatic string extremes_of(int unsigned count);
      int unsigned smallest = '1;
      int unsigned largest = 0;
      int unsigned value;
      repeat (count) begin
         value = delay.next();
         if (value < smallest) begin
            smallest = value;
         end
         if (value > largest) begin
            largest = value;
         end
      end
      return $sformatf("%0d %0d", smallest, largest);
   endfunction : extremes_of

   // "yes" when the average of the next count delays is within lo to hi, otherwise the average.
   function automatic string average_within(int unsigned count, int unsigned lo, int unsigned hi);
      longint unsigned total = 0;
      int unsigned     average;
      repeat (count) begin
         total += 64'(delay.next());
      end
      average = 32'(total / count);
      return (average >= lo && average <= hi) ? "yes" : $sformatf("average is %0d", average);
   endfunction : average_within

   // How often each of three values comes up in the next count delays, and how often anything else.
   function automatic string histogram_of(int unsigned count, int unsigned a, int unsigned b, int unsigned c);
      int unsigned hits_a;
      int unsigned hits_b;
      int unsigned hits_c;
      int unsigned others;
      int unsigned value;
      repeat (count) begin
         value = delay.next();
         if (value == a) begin
            hits_a++;
         end else if (value == b) begin
            hits_b++;
         end else if (value == c) begin
            hits_c++;
         end else begin
            others++;
         end
      end
      // A conditional operator on string literals of different lengths would pad the shorter one.
      return $sformatf("%s %s %s others=%0d", seen_text(hits_a), seen_text(hits_b), most_text(hits_c > hits_a), others);
   endfunction : histogram_of

   // "yes" when value comes up lo to hi times in the next count delays, otherwise the number of times.
   function automatic string hits_within(int unsigned count, int unsigned value, int unsigned lo, int unsigned hi);
      int unsigned hits = 0;
      repeat (count) begin
         if (delay.next() == value) begin
            hits++;
         end
      end
      return (hits >= lo && hits <= hi) ? "yes" : $sformatf("%0d hits", hits);
   endfunction : hits_within

   // The next count delays of mode bursty, taken as runs of zeros that each end with a gap; the run after the last
   // gap is left out. Gives "runs <shortest>..<longest> gaps <smallest>..<largest>".
   function automatic string burst_shape(int unsigned count);
      int unsigned zeros = 0;
      int unsigned zeros_min = '1;
      int unsigned zeros_max = 0;
      int unsigned gap_min = '1;
      int unsigned gap_max = 0;
      int unsigned value;
      repeat (count) begin
         value = delay.next();
         if (value == 0) begin
            zeros++;
            continue;
         end
         if (zeros < zeros_min) begin
            zeros_min = zeros;
         end
         if (zeros > zeros_max) begin
            zeros_max = zeros;
         end
         if (value < gap_min) begin
            gap_min = value;
         end
         if (value > gap_max) begin
            gap_max = value;
         end
         zeros = 0;
      end
      return $sformatf("runs %0d..%0d gaps %0d..%0d", zeros_min, zeros_max, gap_min, gap_max);
   endfunction : burst_shape

   // Draws the next count delays and ignores them.
   function automatic void skip(int unsigned count);
      repeat (count) begin
         void'(delay.next());
      end
   endfunction : skip

   // "seen" for a count above 0, otherwise "never".
   function automatic string seen_text(int unsigned hits);
      if (hits == 0) begin
         return "never";
      end
      return "seen";
   endfunction : seen_text

   // "most" or "fewer".
   function automatic string most_text(bit is_most);
      if (is_most) begin
         return "most";
      end
      return "fewer";
   endfunction : most_text

   // Makes the cfg one for constant delays of the given value.
   function automatic void set_constant(int unsigned value);
      cfg.mode        = HEXK_DELAY_CONSTANT;
      cfg.fixed_value = value;
   endfunction : set_constant

   // Makes the cfg ignore the knob perf_mode.
   function automatic void ignore_perf_knob();
      cfg.honor_perf_knob = 0;
   endfunction : ignore_perf_knob

   // "same" when two generators with these seeds and names produce the same 20 delays.
   function automatic string compare_streams(int unsigned seed_a, string name_a, int unsigned seed_b, string name_b);
      hexk_delay first = new(cfg, name_a, seed_a);
      hexk_delay second = new(cfg, name_b, seed_b);
      cfg.lo = 0;
      cfg.hi = 1000;
      return (sequence_of(20, first) == sequence_of(20, second)) ? "same" : "different";
   endfunction : compare_streams

   // Defines the knob perf_mode with a value and locks the knobs.
   function automatic void lock_perf_knob(bit value);
      hexk_knobs knobs = hexk_knobs::get();
      knobs.add_bit("perf_mode", value, "performance mode: no delays");
      knobs.lock();
   endfunction : lock_perf_knob

   // Replaces the generator by one without a cfg.
   function automatic void use_null_cfg();
      delay = new(null, "ut_no_cfg", SEED);
   endfunction : use_null_cfg

   // Number of HEXK_DELAY_CFG errors in this test.
   function automatic string cfg_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_DELAY_CFG$"));
   endfunction : cfg_errors

   // Time since the start of the test in nanoseconds.
   function automatic string elapsed();
      return $sformatf("%0.0fns", ($realtime - start_time) / 1ns);
   endfunction : elapsed

   // wait_time(unit_ps), given 100 ns: outcome is "returned" or "waiting".
   task automatic wait_time_for_100ns(longint unsigned unit_ps);
      outcome = "waiting";
      fork
         begin
            fork
               begin
                  delay.wait_time(unit_ps);
                  outcome = "returned";
               end
               #100ns;
            join_any
            disable fork;
         end
      join
   endtask : wait_time_for_100ns

   // Triggers clock_tick every 10 ns for a while.
   task automatic start_clock();
      fork
         repeat (20) begin
            #10ns;
            ->clock_tick;
         end
      join_none
   endtask : start_clock

   // The mode and limits after randomize(), as "<ok> <mode> <lo> <hi>".
   function automatic string randomized(bit constant_nine);
      int ok;
      if (constant_nine) begin
         ok = cfg.randomize() with {
            mode == HEXK_DELAY_CONSTANT;
            fixed_value == 9;
         };
         return $sformatf("%0d %s %0d", ok, cfg.mode.name(), cfg.fixed_value);
      end
      ok = cfg.randomize();
      return $sformatf("%0d %s %0d %0d", ok, cfg.mode.name(), cfg.lo, cfg.hi);
   endfunction : randomized

   // Every member of a clone of the cfg, after each member of the cfg got a value that is not its default:
   // "<mode> <fixed_value> <lo> <hi> <mean> <std_dev> <burst limits, four> {<weights>} <honor_perf_knob>".
   function automatic string clone_text();
      uvm_object     copied;
      hexk_delay_cfg clone;
      string         weights;
      cfg.mode            = HEXK_DELAY_WEIGHTED;
      cfg.fixed_value     = 11;
      cfg.lo              = 12;
      cfg.hi              = 13;
      cfg.mean            = 14;
      cfg.std_dev         = 15;
      cfg.burst_on_min    = 16;
      cfg.burst_on_max    = 17;
      cfg.burst_off_min   = 18;
      cfg.burst_off_max   = 19;
      cfg.weights[0]      = 5;
      cfg.weights[7]      = 1;
      cfg.honor_perf_knob = 0;
      copied              = cfg.clone();
      if (!$cast(clone, copied) || clone == null) begin
         return "not a clone";
      end
      // The clone must not follow later changes of the original.
      cfg.weights[9] = 3;
      cfg.lo         = 99;
      foreach (clone.weights[value]) begin
         weights = {weights, $sformatf(" %0d:%0d", value, clone.weights[value])};
      end
      return $sformatf(
          "%s %0d %0d %0d %0d %0d %0d %0d %0d %0d {%s } %0d",
          clone.mode.name(),
          clone.fixed_value,
          clone.lo,
          clone.hi,
          clone.mean,
          clone.std_dev,
          clone.burst_on_min,
          clone.burst_on_max,
          clone.burst_off_min,
          clone.burst_off_max,
          weights,
          clone.honor_perf_knob
      );
   endfunction : clone_text

   // compare() of a clone, and of the clone after a change, and whether print() names weights:
   // "<equal> <equal after the change> <named>".
   function automatic string compared_cfg();
      hexk_delay_cfg original = hexk_delay_cfg::type_id::create("ut_compared");
      hexk_delay_cfg copy;
      bit equal_before;
      original.weights[2] = 1;
      if (!$cast(copy, original.clone()) || copy == null) begin
         return "not a clone";
      end
      equal_before = original.compare(copy);
      copy.weights[5] = 4;
      return $sformatf(
          "%0b %0b %0b", equal_before, original.compare(copy), hexk_str::contains(original.sprint(), "weights")
      );
   endfunction : compared_cfg

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(a_new_cfg_gives_uniform_delays_of_0_to_4)
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(), "mode=HEXK_DELAY_UNIFORM lo=0 hi=4")
      `FAIL_UNLESS_STR_EQUAL(extremes_of(200), "0 4")
   `SVTEST_END

   `SVTEST(mode_none_is_always_0)
      set_mode(HEXK_DELAY_NONE);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(5), "0 0 0 0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(every_mode_of_the_enum_is_legal_with_its_default_values)
      `FAIL_UNLESS_STR_EQUAL(reasons_of_all_modes(), {
                             "HEXK_DELAY_NONE= HEXK_DELAY_CONSTANT= HEXK_DELAY_UNIFORM= HEXK_DELAY_NORMAL= ",
                             "HEXK_DELAY_EXPONENTIAL= HEXK_DELAY_BURSTY= HEXK_DELAY_WEIGHTED= "})
   `SVTEST_END

   `SVTEST(mode_constant_is_always_the_fixed_value)
      set_constant(7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(4), "7 7 7 7 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(mode_uniform_covers_lo_to_hi_and_nothing_else)
      set_range(10, 13);
      `FAIL_UNLESS_STR_EQUAL(extremes_of(300), "10 13")
      set_range(6, 6);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "6 6 6 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(mode_normal_is_centred_on_the_mean)
      set_mode(HEXK_DELAY_NORMAL);
      set_mean(100, 10);
      `FAIL_UNLESS_STR_EQUAL(average_within(500, 97, 103), "yes")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(mode_normal_has_no_negative_delays)
      set_mode(HEXK_DELAY_NORMAL);
      set_mean(0, 20);
      `FAIL_UNLESS_STR_EQUAL(average_within(500, 4, 12), "yes")
   `SVTEST_END

   `SVTEST(mode_exponential_has_the_mean)
      set_mode(HEXK_DELAY_EXPONENTIAL);
      set_mean(20);
      `FAIL_UNLESS_STR_EQUAL(average_within(1000, 17, 23), "yes")
      set_mean(0);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "0 0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(mode_bursty_is_a_burst_of_zeros_then_one_delay)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(3, 3, 7, 7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(9), "0 0 0 7 0 0 0 7 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(mode_bursty_with_empty_bursts_is_one_delay_per_call)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(0, 0, 5, 5);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "5 5 5 ")
   `SVTEST_END

   `SVTEST(mode_bursty_draws_burst_length_and_gap_from_their_limits)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(1, 2, 20, 30);
      `FAIL_UNLESS_STR_EQUAL(extremes_of(300), "0 30")
      `FAIL_UNLESS_STR_EQUAL(histogram_of(300, 1, 19, 31), "never never fewer others=300")
   `SVTEST_END

   `SVTEST(mode_bursty_keeps_every_burst_length_and_gap_within_their_limits)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(1, 2, 20, 30);
      `FAIL_UNLESS_STR_EQUAL(burst_shape(300), "runs 1..2 gaps 20..30")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(a_burst_ends_when_the_mode_changes)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(3, 3, 7, 7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(1), "0 ")
      set_constant(9);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(1), "9 ")
      set_mode(HEXK_DELAY_BURSTY);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(5), "0 0 0 7 0 ")
   `SVTEST_END

   `SVTEST(a_burst_ends_when_the_burst_limits_change)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(5, 5, 7, 7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "0 0 ")
      set_bursts(1, 1, 3, 3);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "0 3 0 ")
      set_bursts(1, 1, 4, 4);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "0 4 0 ")
      set_bursts(0, 0, 6, 6);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "6 6 ")
   `SVTEST_END

   `SVTEST(a_burst_ends_when_the_cfg_becomes_illegal)
      set_mode(HEXK_DELAY_BURSTY);
      set_bursts(3, 3, 7, 7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(1), "0 ")
      set_bursts(5, 3, 7, 7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(1), "0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "1")
      set_bursts(3, 3, 7, 7);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(4), "0 0 0 7 ")
   `SVTEST_END

   `SVTEST(mode_weighted_picks_values_by_their_weight)
      set_mode(HEXK_DELAY_WEIGHTED);
      set_weight(2, 1);
      set_weight(5, 0);
      set_weight(9, 6);
      `FAIL_UNLESS_STR_EQUAL(histogram_of(400, 2, 5, 9), "seen never most others=0")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   // The bands are about six standard deviations of the binomial distribution wide on each side of the expected
   // count, so a correct generator does not leave them by chance; the seed is fixed in any case.
   `SVTEST(mode_weighted_picks_values_in_proportion_to_their_weights)
      set_mode(HEXK_DELAY_WEIGHTED);
      set_weight(2, 1);
      set_weight(9, 6);
      // Expected 342.9 of 400, standard deviation 7.0.
      `FAIL_UNLESS_STR_EQUAL(hits_within(400, 9, 300, 385), "yes")
      set_weight(2, 32'hFFFF_FFFF);
      set_weight(9, 32'h5555_5555);
      // A quarter of the weight, in a sum above 32 bits: expected 100 of 400, standard deviation 8.7.
      `FAIL_UNLESS_STR_EQUAL(hits_within(400, 9, 50, 150), "yes")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(weights_whose_sum_does_not_fit_32_bits_are_legal)
      set_mode(HEXK_DELAY_WEIGHTED);
      set_weight(2, 32'h8000_0000);
      set_weight(5, 0);
      set_weight(9, 32'h8000_0000);
      `FAIL_UNLESS_STR_EQUAL(extremes_of(200), "2 9")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
   `SVTEST_END

   `SVTEST(total_weight_adds_the_weights_in_64_bits)
      set_weight(2, 32'hFFFF_FFFF);
      set_weight(9, 2);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", cfg.total_weight()), "4294967297")
   `SVTEST_END

   `SVTEST(a_mode_that_is_no_value_of_the_enum_is_illegal)
      `FAIL_UNLESS_STR_EQUAL(unknown_mode_reason(), "mode (7) is not a value of hexk_delay_mode_e")
   `SVTEST_END

   `SVTEST(the_same_seed_gives_the_same_delays)
      `FAIL_UNLESS_STR_EQUAL(compare_streams(11, "a", 11, "b"), "same")
   `SVTEST_END

   `SVTEST(different_seeds_give_different_delays)
      `FAIL_UNLESS_STR_EQUAL(compare_streams(11, "a", 12, "a"), "different")
   `SVTEST_END

   `SVTEST(a_seed_of_0_is_derived_from_the_name)
      `FAIL_UNLESS_STR_EQUAL(compare_streams(0, "driver_a", 0, "driver_b"), "different")
   `SVTEST_END

   `SVTEST(the_perf_mode_knob_makes_every_delay_0)
      set_range(3, 9);
      lock_perf_knob(1);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(4), "0 0 0 0 ")
   `SVTEST_END

   `SVTEST(a_cfg_can_ignore_the_perf_mode_knob)
      set_range(3, 9);
      ignore_perf_knob();
      lock_perf_knob(1);
      `FAIL_UNLESS_STR_EQUAL(extremes_of(200), "3 9")
   `SVTEST_END

   `SVTEST(a_perf_mode_knob_that_is_0_or_missing_changes_nothing)
      set_range(3, 9);
      `FAIL_UNLESS_STR_EQUAL(extremes_of(200), "3 9")
      lock_perf_knob(0);
      `FAIL_UNLESS_STR_EQUAL(extremes_of(200), "3 9")
   `SVTEST_END

   `SVTEST(an_illegal_cfg_is_reported_once_and_gives_0)
      set_range(9, 3);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "0 0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "1")
      set_range(3, 3);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "3 3 ")
      set_mode(HEXK_DELAY_WEIGHTED);
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "2")
   `SVTEST_END

   `SVTEST(mode_normal_with_a_mean_or_std_dev_above_the_largest_int_is_illegal)
      set_mode(HEXK_DELAY_NORMAL);
      set_mean(32'h7FFF_FFFF, 32'h7FFF_FFFF);
      `FAIL_UNLESS_STR_EQUAL(cfg.illegal_reason(), "")
      skip(3);
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
      set_mean(32'h8000_0000, 1);
      `FAIL_UNLESS_STR_EQUAL(cfg.illegal_reason(), "mean (2147483648) or std_dev (1) is above 2147483647")
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "0 0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "1")
      set_mean(100, 10);
      `FAIL_UNLESS_STR_EQUAL(average_within(200, 95, 105), "yes")
      set_mean(100, 32'hFFFF_FFFF);
      `FAIL_UNLESS_STR_EQUAL(cfg.illegal_reason(), "mean (100) or std_dev (4294967295) is above 2147483647")
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "2")
      set_mean(100, 10);
      `FAIL_UNLESS_STR_EQUAL(average_within(200, 95, 105), "yes")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "2")
   `SVTEST_END

   `SVTEST(mode_exponential_with_a_mean_above_the_largest_int_is_illegal)
      set_mode(HEXK_DELAY_EXPONENTIAL);
      set_mean(32'h7FFF_FFFF);
      `FAIL_UNLESS_STR_EQUAL(cfg.illegal_reason(), "")
      skip(3);
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "0")
      set_mean(32'h8000_0000);
      `FAIL_UNLESS_STR_EQUAL(cfg.illegal_reason(), "mean (2147483648) or std_dev (0) is above 2147483647")
      `FAIL_UNLESS_STR_EQUAL(sequence_of(3), "0 0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "1")
      set_mean(20);
      `FAIL_UNLESS_STR_EQUAL(average_within(1000, 17, 23), "yes")
      set_mean(32'hFFFF_FFFF);
      `FAIL_UNLESS_STR_EQUAL(cfg.illegal_reason(), "mean (4294967295) or std_dev (0) is above 2147483647")
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "2")
      set_mean(20);
      `FAIL_UNLESS_STR_EQUAL(average_within(1000, 17, 23), "yes")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "2")
   `SVTEST_END

   `SVTEST(a_null_cfg_is_an_error_and_gives_0)
      use_null_cfg();
      `FAIL_UNLESS_STR_EQUAL(sequence_of(2), "0 0 ")
      `FAIL_UNLESS_STR_EQUAL(cfg_errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(delay.convert2string(), "ut_no_cfg: no cfg")
   `SVTEST_END

   `SVTEST(wait_time_waits_for_the_delay_times_the_unit)
      set_constant(5);
      delay.wait_time(`hexk_ps(2ns));
      `FAIL_UNLESS_STR_EQUAL(elapsed(), "10ns")
      set_mode(HEXK_DELAY_NONE);
      delay.wait_time(`hexk_ps(2ns));
      `FAIL_UNLESS_STR_EQUAL(elapsed(), "10ns")
   `SVTEST_END

   `SVTEST(a_wait_time_past_the_largest_number_does_not_wrap_around)
      set_constant(4);
      wait_time_for_100ns(64'h4000_0000_0000_0000);
      `FAIL_UNLESS_STR_EQUAL(outcome, "waiting")
   `SVTEST_END

   `SVTEST(wait_cycles_waits_for_that_many_events)
      set_constant(3);
      start_clock();
      delay.wait_cycles(clock_tick);
      `FAIL_UNLESS_STR_EQUAL(elapsed(), "30ns")
      set_mode(HEXK_DELAY_NONE);
      delay.wait_cycles(clock_tick);
      `FAIL_UNLESS_STR_EQUAL(elapsed(), "30ns")
   `SVTEST_END

   `SVTEST(convert2string_shows_the_values_of_the_mode)
      `FAIL_UNLESS_STR_EQUAL(delay.convert2string(), "ut_delay: mode=HEXK_DELAY_UNIFORM lo=0 hi=4")
      set_mode(HEXK_DELAY_NONE);
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(), "mode=HEXK_DELAY_NONE")
      set_mode(HEXK_DELAY_CONSTANT);
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(), "mode=HEXK_DELAY_CONSTANT fixed_value=1")
      set_mode(HEXK_DELAY_NORMAL);
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(), "mode=HEXK_DELAY_NORMAL mean=2 std_dev=1")
      set_mode(HEXK_DELAY_EXPONENTIAL);
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(), "mode=HEXK_DELAY_EXPONENTIAL mean=2")
      set_mode(HEXK_DELAY_BURSTY);
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(), "mode=HEXK_DELAY_BURSTY burst_on=1..4 burst_off=1..8")
   `SVTEST_END

   `SVTEST(a_clone_of_the_cfg_has_its_own_copy_of_every_value)
      `FAIL_UNLESS_STR_EQUAL(clone_text(), "HEXK_DELAY_WEIGHTED 11 12 13 14 15 16 17 18 19 { 0:5 7:1 } 0")
   `SVTEST_END

   `SVTEST(randomize_without_constraints_gives_the_defaults)
      set_range(50, 60);
      `FAIL_UNLESS_STR_EQUAL(randomized(0), "1 HEXK_DELAY_UNIFORM 0 4")
   `SVTEST_END

   // On Verilator 5.046 a soft constraint is a hard one, so a constraint of the caller that
   // contradicts a default makes randomize() fail there. The test is compiled, and runs on
   // the other simulators.
`ifndef VERILATOR
   `SVTEST(randomize_with_constraints_overrides_the_defaults)
      `FAIL_UNLESS_STR_EQUAL(randomized(1), "1 HEXK_DELAY_CONSTANT 9")
   `SVTEST_END
`endif

   `SVTEST(compare_and_print_cover_every_member)
      `FAIL_UNLESS_STR_EQUAL(compared_cfg(), "1 0 1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_delay_unit_test
