// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_lfsr_unit_test.sv
//
// SVUnit tests of hexk_lfsr.
// The built-in tap table is checked by counting the period of every width from 2 to 20,
// which must be 2**width - 1. Short sequences are compared with values worked out by hand
// for both forms. The other tests cover state access and illegal arguments. Results are
// compared as text (see tests/unit/README.md).
// Runs on Verilator: make test SIM=verilator TEST=hexk_lfsr.

`include "svunit_defines.svh"

module hexk_lfsr_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_lfsr;

   localparam int unsigned FIRST_WIDTH = 2;
   localparam int unsigned LAST_WIDTH  = 20;

   string          name = "hexk_lfsr_ut";
   svunit_testcase svunit_ut;

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // Hex text of a state.
   function automatic string hex(longint unsigned value);
      return $sformatf("%0h", value);
   endfunction : hex

   // Decimal text of a step count.
   function automatic string dec(longint unsigned value);
      return $sformatf("%0d", value);
   endfunction : dec

   // The next count states of lfsr, in decimal, joined with ",".
   function automatic string sequence_text(hexk_lfsr lfsr, int unsigned count);
      string text;
      for (int unsigned i = 0; i < count; i++) begin
         text = {text, (i == 0) ? "" : ",", $sformatf("%0d", lfsr.next())};
      end
      return text;
   endfunction : sequence_text

   // Widths from FIRST_WIDTH to LAST_WIDTH whose maximal() register does not have period 2**width - 1.
   function automatic string widths_with_wrong_period();
      string text;
      hexk_lfsr lfsr;
      longint unsigned expected;
      for (int unsigned width = FIRST_WIDTH; width <= LAST_WIDTH; width++) begin
         lfsr     = hexk_lfsr::maximal(width);
         expected = (64'd1 << width) - 1;
         if (lfsr.period() != expected) begin
            text = {text, $sformatf(" %0d", width)};
         end
      end
      return text;
   endfunction : widths_with_wrong_period

   // Period of a register built with new().
   function automatic string period_of(int unsigned width, longint unsigned taps, hexk_lfsr::kind_e kind);
      hexk_lfsr lfsr = new(width, taps, 64'h1, kind);
      return dec(lfsr.period());
   endfunction : period_of

   // First five states of a 4-bit register with taps for x^4 + x + 1 and seed 1.
   function automatic string first_states(hexk_lfsr::kind_e kind);
      hexk_lfsr lfsr = new(4, 64'h9, 64'h1, kind);
      return sequence_text(lfsr, 5);
   endfunction : first_states

   // State of an 8-bit maximal register after seeding it with seed.
   function automatic string seeded_state(longint unsigned seed);
      hexk_lfsr lfsr = hexk_lfsr::maximal(8, seed);
      return hex(lfsr.get_state());
   endfunction : seeded_state

   // State of an 8-bit maximal register (seed 'h5A) after set_state(value).
   function automatic string state_after_set(longint unsigned value);
      hexk_lfsr lfsr = hexk_lfsr::maximal(8, 64'h5A);
      lfsr.set_state(value);
      return hex(lfsr.get_state());
   endfunction : state_after_set

   // "same" when two registers with the same width and seed produce the same 100 states.
   function automatic string two_registers(longint unsigned seed_a, longint unsigned seed_b);
      hexk_lfsr first = hexk_lfsr::maximal(32, seed_a);
      hexk_lfsr second = hexk_lfsr::maximal(32, seed_b);
      return (sequence_text(first, 100) == sequence_text(second, 100)) ? "same" : "different";
   endfunction : two_registers

   // "yes" when next() returns the value that get_state() then reports.
   function automatic string next_matches_state();
      hexk_lfsr lfsr = hexk_lfsr::maximal(16);
      longint unsigned returned = lfsr.next();
      return (returned == lfsr.get_state()) ? "yes" : "no";
   endfunction : next_matches_state

   // First state after seed 1 of a maximal register of the given width.
   function automatic string first_of_maximal(int unsigned width);
      hexk_lfsr lfsr = hexk_lfsr::maximal(width);
      return hex(lfsr.next());
   endfunction : first_of_maximal

   // Period reported for a maximal register of the given width.
   function automatic string period_of_maximal(int unsigned width);
      hexk_lfsr lfsr = hexk_lfsr::maximal(width);
      return dec(lfsr.period());
   endfunction : period_of_maximal

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(maximal_registers_have_the_full_period)
      `FAIL_UNLESS_STR_EQUAL(widths_with_wrong_period(), "")
   `SVTEST_END

   `SVTEST(fibonacci_form_has_the_full_period_with_the_same_taps)
      `FAIL_UNLESS_STR_EQUAL(period_of(4, 64'h9, hexk_lfsr::HEXK_LFSR_FIBONACCI), "15")
      `FAIL_UNLESS_STR_EQUAL(period_of(8, 64'hC3, hexk_lfsr::HEXK_LFSR_FIBONACCI), "255")
      `FAIL_UNLESS_STR_EQUAL(period_of(13, 64'h1013, hexk_lfsr::HEXK_LFSR_FIBONACCI), "8191")
      `FAIL_UNLESS_STR_EQUAL(period_of(16, 64'h8805, hexk_lfsr::HEXK_LFSR_FIBONACCI), "65535")
      `FAIL_UNLESS_STR_EQUAL(period_of(20, 64'h8_0004, hexk_lfsr::HEXK_LFSR_FIBONACCI), "1048575")
   `SVTEST_END

   `SVTEST(taps_that_are_not_primitive_give_a_shorter_period)
      `FAIL_UNLESS_STR_EQUAL(period_of(4, 64'hF, hexk_lfsr::HEXK_LFSR_GALOIS), "5")
   `SVTEST_END

   `SVTEST(galois_form_steps_as_worked_out_by_hand)
      `FAIL_UNLESS_STR_EQUAL(first_states(hexk_lfsr::HEXK_LFSR_GALOIS), "9,13,15,14,7")
   `SVTEST_END

   `SVTEST(fibonacci_form_steps_as_worked_out_by_hand)
      `FAIL_UNLESS_STR_EQUAL(first_states(hexk_lfsr::HEXK_LFSR_FIBONACCI), "3,7,15,14,13")
   `SVTEST_END

   `SVTEST(next_returns_the_new_state)
      `FAIL_UNLESS_STR_EQUAL(next_matches_state(), "yes")
   `SVTEST_END

   `SVTEST(the_same_seed_gives_the_same_sequence)
      `FAIL_UNLESS_STR_EQUAL(two_registers(64'h1234, 64'h1234), "same")
      `FAIL_UNLESS_STR_EQUAL(two_registers(64'h1234, 64'h1235), "different")
   `SVTEST_END

   `SVTEST(the_seed_is_limited_to_the_width)
      `FAIL_UNLESS_STR_EQUAL(seeded_state(64'h5A), "5a")
      `FAIL_UNLESS_STR_EQUAL(seeded_state(64'h1FF), "ff")
   `SVTEST_END

   `SVTEST(a_zero_seed_is_replaced_by_one)
      `FAIL_UNLESS_STR_EQUAL(seeded_state(64'h0), "1")
      `FAIL_UNLESS_STR_EQUAL(seeded_state(64'h100), "1")
   `SVTEST_END

   `SVTEST(set_state_changes_the_state)
      `FAIL_UNLESS_STR_EQUAL(state_after_set(64'h3C), "3c")
      `FAIL_UNLESS_STR_EQUAL(state_after_set(64'hA3C), "3c")
   `SVTEST_END

   `SVTEST(set_state_rejects_zero)
      `FAIL_UNLESS_STR_EQUAL(state_after_set(64'h0), "5a")
      `FAIL_UNLESS_STR_EQUAL(state_after_set(64'hF00), "5a")
   `SVTEST_END

   `SVTEST(the_widest_register_uses_all_64_bits)
      `FAIL_UNLESS_STR_EQUAL(first_of_maximal(64), "8000000000000403")
      `FAIL_UNLESS_STR_EQUAL(first_of_maximal(32), "80200003")
   `SVTEST_END

   `SVTEST(maximal_replaces_an_illegal_width)
      `FAIL_UNLESS_STR_EQUAL(period_of_maximal(1), "3")
      `FAIL_UNLESS_STR_EQUAL(first_of_maximal(65), "8000000000000403")
   `SVTEST_END

   `SVTEST(period_of_a_state_that_never_repeats_is_rejected_and_gives_0)
      // Without the top tap the state runs into 0 and stays there.
      `FAIL_UNLESS_STR_EQUAL(period_of(4, 64'h0, hexk_lfsr::HEXK_LFSR_GALOIS), "0")
      `FAIL_UNLESS_STR_EQUAL(period_of(4, 64'h0, hexk_lfsr::HEXK_LFSR_FIBONACCI), "0")
      `FAIL_UNLESS_STR_EQUAL(period_of(16, 64'h2, hexk_lfsr::HEXK_LFSR_FIBONACCI), "0")
   `SVTEST_END

   `SVTEST(period_is_not_counted_above_24_bits)
      `FAIL_UNLESS_STR_EQUAL(period_of_maximal(25), "0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_lfsr_unit_test
