// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_math_unit_test.sv
//
// SVUnit tests of hexk_math.
// Integer helpers are checked at 0, 1 and the 64-bit limits; bit-vector helpers at widths
// 1, 63, 64, 65 and HEXK_MAX_WIDTH. Results are compared as text (see tests/unit/README.md).
// Illegal arguments make the library call $error on purpose; those tests check the value
// that is returned. Runs on Verilator: make test SIM=verilator TEST=hexk_math.

`include "svunit_defines.svh"

module hexk_math_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_math;
   import hexk_core_pkg::hexk_str;
   import hexk_core_pkg::hexk_bits_t;

   localparam int unsigned MAX_WIDTH  = hexk_math::MAX_WIDTH;
   localparam int unsigned HEX_DIGITS = MAX_WIDTH / 4;

   string          name = "hexk_math_ut";
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

   // Decimal text of a signed 64-bit result.
   function automatic string s64(longint value);
      return $sformatf("%0d", value);
   endfunction : s64

   // Decimal text of an unsigned 64-bit result.
   function automatic string u64(longint unsigned value);
      return $sformatf("%0d", value);
   endfunction : u64

   // Decimal text of an unsigned 32-bit result.
   function automatic string u32(int unsigned value);
      return $sformatf("%0d", value);
   endfunction : u32

   // "1" or "0" for a bit result.
   function automatic string bit_text(bit value);
      return value ? "1" : "0";
   endfunction : bit_text

   // Hex text of a full-width vector, without leading zeros.
   function automatic string hex(hexk_bits_t value);
      return $sformatf("%0h", value);
   endfunction : hex

   // digit followed by count zeros, the hex text of a vector with only high bits set.
   function automatic string high_hex(string digit, int unsigned count);
      return {digit, hexk_str::repeat_str("0", count)};
   endfunction : high_hex

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(clamp_limits_a_signed_value)
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(5, 0, 10)), "5")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(-5, 0, 10)), "0")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(15, 0, 10)), "10")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(-20, -10, -5)), "-10")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(7, 7, 7)), "7")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(64'sh8000_0000_0000_0000, -1, 1)), "-1")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(64'sh7FFF_FFFF_FFFF_FFFF, -1, 1)), "1")
   `SVTEST_END

   `SVTEST(clamp_u_limits_an_unsigned_value)
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::clamp_u(5, 10, 20)), "10")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::clamp_u(15, 10, 20)), "15")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::clamp_u(64'hFFFF_FFFF_FFFF_FFFF, 0, 100)), "100")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::clamp_u(0, 0, 0)), "0")
   `SVTEST_END

   `SVTEST(clamp_with_reversed_limits_returns_lo)
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::clamp(5, 10, 0)), "10")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::clamp_u(5, 10, 0)), "10")
   `SVTEST_END

   `SVTEST(is_pow2_accepts_single_bit_values_only)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(0)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(1)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(2)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(3)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(4096)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(64'h8000_0000_0000_0000)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_pow2(64'hFFFF_FFFF_FFFF_FFFF)), "0")
   `SVTEST_END

   `SVTEST(log2_ceil_rounds_up)
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(0)), "0")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(1)), "0")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(2)), "1")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(3)), "2")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(4)), "2")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(5)), "3")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(1024)), "10")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(64'h8000_0000_0000_0000)), "63")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(64'h8000_0000_0000_0001)), "64")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::log2_ceil(64'hFFFF_FFFF_FFFF_FFFF)), "64")
   `SVTEST_END

   `SVTEST(align_down_and_align_up_move_to_a_multiple)
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_down(17, 8)), "16")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_down(16, 8)), "16")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_down(7, 8)), "0")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_down(17, 5)), "15")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(17, 8)), "24")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(16, 8)), "16")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(1, 4096)), "4096")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(17, 5)), "20")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(0, 8)), "0")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_down(64'hFFFF_FFFF_FFFF_FFFF, 16)), "18446744073709551600")
   `SVTEST_END

   `SVTEST(is_aligned_tests_for_a_multiple)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_aligned(16, 8)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_aligned(17, 8)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_aligned(0, 3)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_aligned(15, 5)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_aligned(15, 1)), "1")
   `SVTEST_END

   `SVTEST(align_up_beyond_64_bits_is_rejected_and_returns_the_value)
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(64'hFFFF_FFFF_FFFF_FFFF, 8)), "18446744073709551615")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(64'hFFFF_FFFF_FFFF_FFF9, 8)), "18446744073709551609")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(64'hFFFF_FFFF_FFFF_FFF1, 8)), "18446744073709551608")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(64'hFFFF_FFFF_FFFF_FFF8, 8)), "18446744073709551608")
   `SVTEST_END

   `SVTEST(alignment_of_zero_is_rejected)
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_down(17, 0)), "17")
      `FAIL_UNLESS_STR_EQUAL(u64(hexk_math::align_up(17, 0)), "17")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::is_aligned(17, 0)), "0")
   `SVTEST_END

   `SVTEST(ranges_overlap_compares_inclusive_ranges)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(0, 9, 10, 19)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(0, 10, 10, 19)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(10, 19, 0, 10)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(5, 6, 0, 100)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(0, 100, 5, 6)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(0, 0, 0, 0)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(0, 0, 1, 1)), "0")
   `SVTEST_END

   `SVTEST(ranges_overlap_treats_reversed_limits_as_empty)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(10, 5, 0, 100)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::ranges_overlap(0, 100, 10, 5)), "0")
   `SVTEST_END

   `SVTEST(popcount_counts_ones)
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount('0)), "0")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount('h1)), "1")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount('hF0F0)), "8")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount(hexk_math::mask(63))), "63")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount(hexk_math::mask(64))), "64")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount(hexk_math::mask(65))), "65")
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount(hexk_math::mask(MAX_WIDTH))), u32(MAX_WIDTH))
   `SVTEST_END

   `SVTEST(popcount_does_not_count_x_and_z)
      `FAIL_UNLESS_STR_EQUAL(u32(hexk_math::popcount(hexk_bits_t'(4'b1x1z))), "2")
   `SVTEST_END

   `SVTEST(parity_makes_the_number_of_ones_even_or_odd)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity('b011)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity('b111)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity('b0)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity('b011, 1)), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity('b111, 1)), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity(hexk_math::mask(65))), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_math::parity(hexk_math::mask(MAX_WIDTH))), "0")
   `SVTEST_END

   `SVTEST(reverse_bits_mirrors_the_low_bits)
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('b0000_0001, 8)), "80")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('b0011, 4)), "c")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('b1101, 4)), "b")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('h1, 1)), "1")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('h1, 63)), "4000000000000000")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('h1, 64)), "8000000000000000")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('h1, 65)), "10000000000000000")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('h1, MAX_WIDTH)), high_hex("8", HEX_DIGITS - 1))
   `SVTEST_END

   `SVTEST(reverse_bits_drops_the_bits_above_width)
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('hF1, 4)), "8")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('hFF, 0)), "0")
   `SVTEST_END

   `SVTEST(swap_bytes_reverses_the_byte_order)
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h1122_3344, 4)), "44332211")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('hAABB, 2)), "bbaa")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h5A, 1)), "5a")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h01, 8)), "100000000000000")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h01, MAX_WIDTH / 8)), high_hex("1", HEX_DIGITS - 2))
   `SVTEST_END

   `SVTEST(swap_bytes_drops_the_bytes_above_num_bytes)
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h1122_3344, 2)), "4433")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h1122_3344, 0)), "0")
   `SVTEST_END

   `SVTEST(sign_extend_reads_a_twos_complement_field)
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'hFF, 8)), "-1")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h7F, 8)), "127")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h80, 8)), "-128")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h1, 1)), "-1")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h0, 1)), "0")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h4000_0000_0000_0000, 63)), "-4611686018427387904")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h3FFF_FFFF_FFFF_FFFF, 63)), "4611686018427387903")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h8000_0000_0000_0000, 64)), "-9223372036854775808")
   `SVTEST_END

   `SVTEST(sign_extend_ignores_the_bits_above_width)
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'h17F, 8)), "127")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'hFFFF_FF00_0000_0080, 8)), "-128")
   `SVTEST_END

   `SVTEST(sign_extend_rejects_an_illegal_width)
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'hFF, 0)), "255")
      `FAIL_UNLESS_STR_EQUAL(s64(hexk_math::sign_extend(64'hFF, 65)), "255")
   `SVTEST_END

   `SVTEST(mask_sets_the_low_bits)
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(0)), "0")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(1)), "1")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(8)), "ff")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(63)), "7fffffffffffffff")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(64)), "ffffffffffffffff")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(65)), "1ffffffffffffffff")
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(MAX_WIDTH)), hexk_str::repeat_str("f", HEX_DIGITS))
   `SVTEST_END

   `SVTEST(widths_above_the_vector_width_are_rejected)
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::mask(MAX_WIDTH + 1)), hexk_str::repeat_str("f", HEX_DIGITS))
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::reverse_bits('h1, MAX_WIDTH + 1)), high_hex("8", HEX_DIGITS - 1))
      `FAIL_UNLESS_STR_EQUAL(hex(hexk_math::swap_bytes('h01, MAX_WIDTH / 8 + 1)), high_hex("1", HEX_DIGITS - 2))
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_math_unit_test
