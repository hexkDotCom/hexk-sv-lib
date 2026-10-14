// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ecc_unit_test.sv
//
// SVUnit tests of hexk_ecc.
// The reference code words come from a separate model of the code that was written from its
// definition in docs/api/hexk_ecc.md (check bit i is the parity of the positions that have
// bit i set). The other tests check the properties of the code without a reference: every
// single flipped bit is corrected, every pair of flipped bits is reported, two code words
// differ in at least four bits. Results are compared as text (see tests/unit/README.md).
// Runs on Verilator: make test SIM=verilator TEST=hexk_ecc.

`include "svunit_defines.svh"

module hexk_ecc_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_ecc;
   import hexk_core_pkg::hexk_math;
   import hexk_core_pkg::hexk_bits_t;

   localparam int unsigned MIN_WIDTH   = hexk_ecc::MIN_DATA_WIDTH;
   localparam int unsigned MAX_WIDTH   = hexk_ecc::MAX_DATA_WIDTH;
   localparam int unsigned NUM_LAYOUTS = 2;

   // Number of random draws in the tests of inject.
   localparam int unsigned NUM_DRAWS   = 600;

   // A bit above every code word.
   localparam int unsigned STRAY_BIT   = 200;

   string          name = "hexk_ecc_ut";
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

   // Hex text of a vector.
   function automatic string hex(hexk_bits_t value);
      return $sformatf("%0h", value);
   endfunction : hex

   // Object for a data width and a layout number, 0 or 1. The layout goes through a variable,
   // because Verilator 5.046 uses the default layout when the argument of new() is a function call.
   function automatic hexk_ecc make_ecc(int unsigned width, int unsigned number);
      hexk_ecc::layout_e layout = hexk_ecc::HEXK_ECC_INTERLEAVED;
      hexk_ecc           result;
      if (number != 0) begin
         layout = hexk_ecc::HEXK_ECC_APPENDED;
      end
      result = new(width, layout);
      return result;
   endfunction : make_ecc

   // Random data word of width bits.
   function automatic hexk_bits_t random_data(int unsigned width);
      hexk_bits_t result = '0;
      for (int unsigned i = 0; i < width; i++) begin
         result[i] = ($urandom_range(1) == 1);
      end
      return result;
   endfunction : random_data

   // "<data width> <check width> <code width>" of the code for a data width.
   function automatic string widths_of(int unsigned width);
      hexk_ecc ecc = new(width);
      return $sformatf("%0d %0d %0d", ecc.get_data_width(), ecc.get_check_width(), ecc.get_code_width());
   endfunction : widths_of

   // Name of the layout of an object made with the default layout, or with layout number.
   function automatic string layout_name(bit use_default, int unsigned number);
      hexk_ecc           plain = new(8);
      hexk_ecc           chosen = make_ecc(8, number);
      hexk_ecc::layout_e layout;
      layout = use_default ? plain.get_layout() : chosen.get_layout();
      return layout.name();
   endfunction : layout_name

   // Code word of data for a data width and a layout number.
   function automatic string code_of(int unsigned width, int unsigned number, hexk_bits_t data);
      hexk_ecc ecc = make_ecc(width, number);
      return hex(ecc.encode(data));
   endfunction : code_of

   // Check bits of data for a data width and a layout number.
   function automatic string check_of(int unsigned width, int unsigned number, hexk_bits_t data);
      hexk_ecc ecc = make_ecc(width, number);
      return hex(ecc.check_bits(data));
   endfunction : check_of

   // What decode says about code: status, data, syndrome and the index the syndrome points at.
   function automatic string decode_text(hexk_ecc ecc, hexk_bits_t code);
      hexk_bits_t        data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      status = ecc.decode(code, data, syndrome);
      return $sformatf("%s data=%0h syndrome=%0h index=%0d", status.name(), data, syndrome, ecc.error_index(syndrome));
   endfunction : decode_text

   // Decodes the code word of data (8 data bits) after flipping the bits of flip_mask.
   function automatic string decode_flipped(int unsigned number, hexk_bits_t data, hexk_bits_t flip_mask);
      hexk_ecc ecc = make_ecc(8, number);
      return decode_text(ecc, ecc.encode(data) ^ flip_mask);
   endfunction : decode_flipped

   // Encodes all ones for a data width: "all ones" when every bit of the code word is 1.
   function automatic string code_of_all_ones(int unsigned width);
      hexk_ecc    ecc = new(width);
      hexk_bits_t code;
      code = ecc.encode(hexk_math::mask(width));
      return (code === hexk_math::mask(ecc.get_code_width())) ? "all ones" : hex(code);
   endfunction : code_of_all_ones

   // Encodes and decodes random data for every data width and layout: "ok" or the first problem.
   function automatic string clean_round_trip();
      hexk_ecc           ecc;
      hexk_bits_t        data;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      for (int unsigned width = MIN_WIDTH; width <= MAX_WIDTH; width++) begin
         for (int unsigned number = 0; number < NUM_LAYOUTS; number++) begin
            ecc    = make_ecc(width, number);
            data   = random_data(width);
            status = ecc.decode(ecc.encode(data), read_data, syndrome);
            if (status != hexk_ecc::HEXK_ECC_NO_ERROR || read_data !== data || syndrome != 0) begin
               return $sformatf("width %0d layout %0d data %0h: %s", width, number, data, status.name());
            end
         end
      end
      return "ok";
   endfunction : clean_round_trip

   // Encodes and decodes every data word of a small data width: "ok" or the first problem.
   function automatic string every_word_round_trip(int unsigned width, int unsigned number);
      hexk_ecc           ecc = make_ecc(width, number);
      hexk_bits_t        data;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      for (int unsigned value = 0; value < (32'd1 << width); value++) begin
         data   = hexk_bits_t'(value);
         status = ecc.decode(ecc.encode(data), read_data, syndrome);
         if (status != hexk_ecc::HEXK_ECC_NO_ERROR || read_data !== data || syndrome != 0) begin
            return $sformatf("data %0h: %s", data, decode_text(ecc, ecc.encode(data)));
         end
      end
      return "ok";
   endfunction : every_word_round_trip

   // Flips every bit of a code word in turn, for the data widths lo to hi and both layouts.
   // Each must be corrected and the syndrome must point at the bit: "ok" or the first problem.
   function automatic string single_flips(int unsigned lo, int unsigned hi);
      hexk_ecc           ecc;
      hexk_bits_t        data;
      hexk_bits_t        code;
      hexk_bits_t        damaged;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      for (int unsigned width = lo; width <= hi; width++) begin
         for (int unsigned number = 0; number < NUM_LAYOUTS; number++) begin
            ecc  = make_ecc(width, number);
            data = random_data(width);
            code = ecc.encode(data);
            for (int unsigned index = 0; index < ecc.get_code_width(); index++) begin
               damaged = ecc.flip(code, index);
               status  = ecc.decode(damaged, read_data, syndrome);
               if (status != hexk_ecc::HEXK_ECC_CORRECTED || read_data !== data || ecc.error_index(
                       syndrome
                   ) != int'(index)) begin
                  return $sformatf("width %0d layout %0d data %0h bit %0d: %s", width, number, data, index,
                                   decode_text(ecc, damaged));
               end
            end
         end
      end
      return "ok";
   endfunction : single_flips

   // Flips every pair of bits of a code word, for one data width and both layouts. Each must be
   // reported as uncorrectable with a syndrome that points at no bit, and in the appended
   // layout the data must come back as it was received: "ok" or the first problem.
   function automatic string double_flips(int unsigned width);
      hexk_ecc           ecc;
      hexk_bits_t        data;
      hexk_bits_t        code;
      hexk_bits_t        damaged;
      hexk_bits_t        received;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      for (int unsigned number = 0; number < NUM_LAYOUTS; number++) begin
         ecc  = make_ecc(width, number);
         data = random_data(width);
         code = ecc.encode(data);
         for (int unsigned first = 0; first < ecc.get_code_width(); first++) begin
            for (int unsigned second = first + 1; second < ecc.get_code_width(); second++) begin
               damaged  = ecc.flip(ecc.flip(code, first), second);
               received = damaged & hexk_math::mask(width);
               status   = ecc.decode(damaged, read_data, syndrome);
               if (status != hexk_ecc::HEXK_ECC_UNCORRECTABLE || ecc.error_index(
                       syndrome
                   ) != -1 || (number == 1 && read_data !== received)) begin
                  return $sformatf(
                      "width %0d layout %0d data %0h bits %0d and %0d: %s",
                      width,
                      number,
                      data,
                      first,
                      second,
                      decode_text(
                          ecc, damaged
                      )
                  );
               end
            end
         end
      end
      return "ok";
   endfunction : double_flips

   // Smallest number of bits in which two code words of a small data width differ.
   function automatic string min_distance(int unsigned width, int unsigned number);
      hexk_ecc     ecc = make_ecc(width, number);
      hexk_bits_t  codes                         [$];
      int unsigned distance;
      int unsigned smallest;
      smallest = ecc.get_code_width();
      for (int unsigned value = 0; value < (32'd1 << width); value++) begin
         codes.push_back(ecc.encode(hexk_bits_t'(value)));
      end
      for (int unsigned first = 0; first < codes.size(); first++) begin
         for (int unsigned second = first + 1; second < codes.size(); second++) begin
            distance = hexk_math::popcount(codes[first] ^ codes[second]);
            if (distance < smallest) begin
               smallest = distance;
            end
         end
      end
      return $sformatf("%0d", smallest);
   endfunction : min_distance

   // Appended layout: the syndrome of a word with up to three random errors must be the received
   // check bits XOR the check bits of the received data, with the parity of the whole word on
   // top: "ok" or the first problem.
   function automatic string syndrome_is_check_difference(int unsigned width);
      hexk_ecc           ecc = new(width, hexk_ecc::HEXK_ECC_APPENDED);
      hexk_bits_t        damaged;
      hexk_bits_t        difference;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      int unsigned       expected;
      int unsigned       parity_bit;
      hexk_ecc::status_e status;
      parity_bit = ecc.get_check_width() - 1;
      repeat (50) begin
         damaged    = ecc.inject(ecc.encode(random_data(width)), $urandom_range(3));
         difference = (damaged >> width) ^ ecc.check_bits(damaged);
         expected   = 0;
         for (int unsigned i = 0; i < parity_bit; i++) begin
            expected[i] = difference[i];
         end
         expected[parity_bit] = hexk_math::parity(damaged);
         status = ecc.decode(damaged, read_data, syndrome);
         if (syndrome != expected) begin
            return $sformatf("code %0h: syndrome %0h, expected %0h (%s)", damaged, syndrome, expected, status.name());
         end
      end
      return "ok";
   endfunction : syndrome_is_check_difference

   // Interleaved layout: the syndrome of a word with one flipped bit must be the index of the
   // bit with the parity bit of the syndrome set: "ok" or the first problem.
   function automatic string syndrome_is_index(int unsigned width);
      hexk_ecc           ecc = new(width, hexk_ecc::HEXK_ECC_INTERLEAVED);
      hexk_bits_t        code;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      int unsigned       parity_flag;
      hexk_ecc::status_e status;
      parity_flag = 32'd1 << (ecc.get_check_width() - 1);
      code = ecc.encode(random_data(width));
      for (int unsigned index = 0; index < ecc.get_code_width(); index++) begin
         status = ecc.decode(ecc.flip(code, index), read_data, syndrome);
         if (syndrome != (parity_flag | index)) begin
            return $sformatf("bit %0d: syndrome %0h (%s)", index, syndrome, status.name());
         end
      end
      return "ok";
   endfunction : syndrome_is_index

   // Code word of 'hA5 (8 data bits, appended) after flipping the bits at first and then at second.
   function automatic string flipped(int unsigned first, int unsigned second, bit twice);
      hexk_ecc    ecc = new(8, hexk_ecc::HEXK_ECC_APPENDED);
      hexk_bits_t code;
      code = ecc.flip(ecc.encode(hexk_bits_t'(8'hA5)), first);
      if (twice) begin
         code = ecc.flip(code, second);
      end
      return hex(code);
   endfunction : flipped

   // Index that error_index gives for a syndrome, with 8 data bits in the interleaved layout.
   function automatic string error_index_of(int unsigned syndrome);
      hexk_ecc ecc = new(8);
      return $sformatf("%0d", ecc.error_index(syndrome));
   endfunction : error_index_of

   // Bits that inject changed in a random code word of 8 data bits, with num_errors errors.
   function automatic hexk_bits_t injected_bits(int unsigned num_errors);
      hexk_ecc    ecc = new(8);
      hexk_bits_t code;
      code = ecc.encode(random_data(8));
      return code ^ ecc.inject(code, num_errors);
   endfunction : injected_bits

   // Number of bits that inject changed for num_errors errors; "outside" when one is above the code word.
   function automatic string inject_count(int unsigned width, int unsigned num_errors);
      hexk_ecc    ecc = new(width);
      hexk_bits_t code;
      hexk_bits_t changed;
      code    = ecc.encode(random_data(width));
      changed = code ^ ecc.inject(code, num_errors);
      if ((changed >> ecc.get_code_width()) != 0) begin
         return "outside";
      end
      return $sformatf("%0d", hexk_math::popcount(changed));
   endfunction : inject_count

   // Number of bits that inject changes without a second argument.
   function automatic string inject_default_count();
      hexk_ecc    ecc = new(32);
      hexk_bits_t code;
      code = ecc.encode(random_data(32));
      return $sformatf("%0d", hexk_math::popcount(code ^ ecc.inject(code)));
   endfunction : inject_default_count

   // All bits that many calls of inject changed; "wrong count" when one call changed another number of bits.
   function automatic string inject_union(int unsigned num_errors);
      hexk_bits_t changed;
      hexk_bits_t all_changed = '0;
      repeat (NUM_DRAWS) begin
         changed = injected_bits(num_errors);
         if (hexk_math::popcount(changed) != num_errors) begin
            return "wrong count";
         end
         all_changed = all_changed | changed;
      end
      return hex(all_changed);
   endfunction : inject_union

   // Injects num_errors errors into random code words of every data width and layout and
   // decodes them; every status must be the wanted one: "ok" or the first problem.
   function automatic string inject_then_decode(int unsigned num_errors, hexk_ecc::status_e wanted);
      hexk_ecc           ecc;
      hexk_bits_t        data;
      hexk_bits_t        damaged;
      hexk_bits_t        read_data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      for (int unsigned width = MIN_WIDTH; width <= MAX_WIDTH; width++) begin
         for (int unsigned number = 0; number < NUM_LAYOUTS; number++) begin
            ecc     = make_ecc(width, number);
            data    = random_data(width);
            damaged = ecc.inject(ecc.encode(data), num_errors);
            status  = ecc.decode(damaged, read_data, syndrome);
            if (status != wanted || (num_errors < 2 && read_data !== data)) begin
               return $sformatf("width %0d layout %0d data %0h: %s", width, number, data, decode_text(ecc, damaged));
            end
         end
      end
      return "ok";
   endfunction : inject_then_decode

   // encode, check_bits and decode with a bit set above the width they use: "ignored" when nothing changes.
   function automatic string stray_bits();
      hexk_ecc    ecc = new(8, hexk_ecc::HEXK_ECC_APPENDED);
      hexk_bits_t data = hexk_bits_t'(8'hA5);
      hexk_bits_t stray = '0;
      stray[STRAY_BIT] = 1'b1;
      stray[8] = 1'b1;
      if (ecc.encode(data | stray) !== ecc.encode(data)) begin
         return "encode differs";
      end
      if (ecc.check_bits(data | stray) !== ecc.check_bits(data)) begin
         return "check_bits differs";
      end
      stray[8] = 1'b0;
      if (decode_text(ecc, ecc.encode(data) | stray) != decode_text(ecc, ecc.encode(data))) begin
         return "decode differs";
      end
      return "ignored";
   endfunction : stray_bits

   // flip and inject with a bit set above the code word: "kept" when the bit comes back.
   function automatic string stray_bit_in_flip();
      hexk_ecc    ecc = new(8);
      hexk_bits_t code = '0;
      hexk_bits_t flipped_code;
      hexk_bits_t injected_code;
      code[STRAY_BIT] = 1'b1;
      flipped_code = ecc.flip(code, 0);
      injected_code = ecc.inject(code, ecc.get_code_width());
      return (flipped_code[STRAY_BIT] === 1'b1 && injected_code[STRAY_BIT] === 1'b1) ? "kept" : "lost";
   endfunction : stray_bit_in_flip

`ifndef VERILATOR
   // encode() and check_bits() of 8-bit data with the given bit replaced by value, as "<code> <check bits>" in binary.
   function automatic string encoded_unknown(int unsigned index, logic value);
      hexk_ecc    ecc = new(8, hexk_ecc::HEXK_ECC_APPENDED);
      hexk_bits_t data = hexk_bits_t'(8'hA4);
      data[index] = value;
      return $sformatf("%b %b", 16'(ecc.encode(data)), 8'(ecc.check_bits(data)));
   endfunction : encoded_unknown

   // decode() of the code word of 8'hA4 with the given bit replaced by value: status, data in binary, syndrome.
   function automatic string decoded_unknown(int unsigned index, logic value);
      hexk_ecc           ecc = new(8, hexk_ecc::HEXK_ECC_APPENDED);
      hexk_bits_t        code = ecc.encode(hexk_bits_t'(8'hA4));
      hexk_bits_t        data;
      int unsigned       syndrome;
      hexk_ecc::status_e status;
      code[index] = value;
      status      = ecc.decode(code, data, syndrome);
      return $sformatf("%s %b %0d", status.name(), 12'(data), syndrome);
   endfunction : decoded_unknown

   // flip() of an X bit: "one" when the bit becomes 1 and the other bits stay.
   function automatic string flipped_unknown();
      hexk_ecc    ecc = new(8, hexk_ecc::HEXK_ECC_APPENDED);
      hexk_bits_t code = ecc.encode(hexk_bits_t'(8'hA4));
      hexk_bits_t expected;
      code[0]     = 1'bx;
      expected    = code;
      expected[0] = 1'b1;
      return (ecc.flip(code, 0) === expected) ? "one" : "another value";
   endfunction : flipped_unknown
`endif

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(widths_follow_the_hamming_bound)
      `FAIL_UNLESS_STR_EQUAL(widths_of(4), "4 4 8")
      `FAIL_UNLESS_STR_EQUAL(widths_of(8), "8 5 13")
      `FAIL_UNLESS_STR_EQUAL(widths_of(11), "11 5 16")
      `FAIL_UNLESS_STR_EQUAL(widths_of(12), "12 6 18")
      `FAIL_UNLESS_STR_EQUAL(widths_of(16), "16 6 22")
      `FAIL_UNLESS_STR_EQUAL(widths_of(26), "26 6 32")
      `FAIL_UNLESS_STR_EQUAL(widths_of(27), "27 7 34")
      `FAIL_UNLESS_STR_EQUAL(widths_of(32), "32 7 39")
      `FAIL_UNLESS_STR_EQUAL(widths_of(57), "57 7 64")
      `FAIL_UNLESS_STR_EQUAL(widths_of(58), "58 8 66")
      `FAIL_UNLESS_STR_EQUAL(widths_of(64), "64 8 72")
      `FAIL_UNLESS_STR_EQUAL(widths_of(120), "120 8 128")
      `FAIL_UNLESS_STR_EQUAL(widths_of(121), "121 9 130")
      `FAIL_UNLESS_STR_EQUAL(widths_of(128), "128 9 137")
   `SVTEST_END

   `SVTEST(the_default_layout_is_interleaved)
      `FAIL_UNLESS_STR_EQUAL(layout_name(1, 0), "HEXK_ECC_INTERLEAVED")
      `FAIL_UNLESS_STR_EQUAL(layout_name(0, 0), "HEXK_ECC_INTERLEAVED")
      `FAIL_UNLESS_STR_EQUAL(layout_name(0, 1), "HEXK_ECC_APPENDED")
   `SVTEST_END

   `SVTEST(interleaved_code_words_match_the_reference)
      `FAIL_UNLESS_STR_EQUAL(code_of(4, 0, hexk_bits_t'(4'hD)), "cc")
      `FAIL_UNLESS_STR_EQUAL(code_of(8, 0, hexk_bits_t'(8'hA5)), "144e")
      `FAIL_UNLESS_STR_EQUAL(code_of(16, 0, hexk_bits_t'(16'hBEEF)), "2eddfc")
      `FAIL_UNLESS_STR_EQUAL(code_of(32, 0, hexk_bits_t'(32'hDEAD_BEEF)), "6fab6edcef")
      `FAIL_UNLESS_STR_EQUAL(code_of(64, 0, hexk_bits_t'(64'h0123_4567_89AB_CDEF)), "91a2b3c46af3bdf9")
      `FAIL_UNLESS_STR_EQUAL(code_of(128, 0, hexk_bits_t'(128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210)),
                             "323456789abcdeffe6e5d4c3b950c4205")
      `FAIL_UNLESS_STR_EQUAL(code_of(128, 0, hexk_math::mask(128)), "1fefffffffffffffffffffffffffffffefe")
   `SVTEST_END

   `SVTEST(appended_code_words_match_the_reference)
      `FAIL_UNLESS_STR_EQUAL(code_of(4, 1, hexk_bits_t'(4'hD)), "2d")
      `FAIL_UNLESS_STR_EQUAL(code_of(8, 1, hexk_bits_t'(8'hA5)), "3a5")
      `FAIL_UNLESS_STR_EQUAL(code_of(16, 1, hexk_bits_t'(16'hBEEF)), "ebeef")
      `FAIL_UNLESS_STR_EQUAL(code_of(32, 1, hexk_bits_t'(32'hDEAD_BEEF)), "63deadbeef")
      `FAIL_UNLESS_STR_EQUAL(code_of(64, 1, hexk_bits_t'(64'h0123_4567_89AB_CDEF)), "9c0123456789abcdef")
      `FAIL_UNLESS_STR_EQUAL(code_of(128, 1, hexk_bits_t'(128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210)),
                             "1a20123456789abcdeffedcba9876543210")
      `FAIL_UNLESS_STR_EQUAL(code_of(128, 1, hexk_math::mask(128)), "77ffffffffffffffffffffffffffffffff")
   `SVTEST_END

   `SVTEST(check_bits_are_the_same_in_both_layouts)
      `FAIL_UNLESS_STR_EQUAL(check_of(8, 0, hexk_bits_t'(8'hA5)), "3")
      `FAIL_UNLESS_STR_EQUAL(check_of(8, 1, hexk_bits_t'(8'hA5)), "3")
      `FAIL_UNLESS_STR_EQUAL(check_of(32, 0, hexk_bits_t'(32'hDEAD_BEEF)), "63")
      `FAIL_UNLESS_STR_EQUAL(check_of(32, 1, hexk_bits_t'(32'hDEAD_BEEF)), "63")
      `FAIL_UNLESS_STR_EQUAL(check_of(64, 1, hexk_bits_t'(64'h0123_4567_89AB_CDEF)), "9c")
      `FAIL_UNLESS_STR_EQUAL(check_of(128, 0, hexk_bits_t'(128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210)), "1a2")
   `SVTEST_END

   `SVTEST(data_zero_gives_code_word_zero)
      `FAIL_UNLESS_STR_EQUAL(code_of(4, 0, '0), "0")
      `FAIL_UNLESS_STR_EQUAL(code_of(64, 1, '0), "0")
      `FAIL_UNLESS_STR_EQUAL(code_of(128, 0, '0), "0")
      `FAIL_UNLESS_STR_EQUAL(check_of(128, 1, '0), "0")
   `SVTEST_END

   `SVTEST(all_ones_gives_all_ones_when_the_code_uses_every_position)
      `FAIL_UNLESS_STR_EQUAL(code_of_all_ones(4), "all ones")
      `FAIL_UNLESS_STR_EQUAL(code_of_all_ones(11), "all ones")
      `FAIL_UNLESS_STR_EQUAL(code_of_all_ones(26), "all ones")
      `FAIL_UNLESS_STR_EQUAL(code_of_all_ones(57), "all ones")
      `FAIL_UNLESS_STR_EQUAL(code_of_all_ones(120), "all ones")
   `SVTEST_END

   `SVTEST(a_code_word_without_errors_decodes_to_its_data)
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), '0),
                             "HEXK_ECC_NO_ERROR data=a5 syndrome=0 index=-1")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), '0),
                             "HEXK_ECC_NO_ERROR data=a5 syndrome=0 index=-1")
      `FAIL_UNLESS_STR_EQUAL(clean_round_trip(), "ok")
      `FAIL_UNLESS_STR_EQUAL(every_word_round_trip(4, 0), "ok")
      `FAIL_UNLESS_STR_EQUAL(every_word_round_trip(8, 0), "ok")
      `FAIL_UNLESS_STR_EQUAL(every_word_round_trip(8, 1), "ok")
   `SVTEST_END

   `SVTEST(one_flipped_bit_is_corrected_in_the_interleaved_layout)
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0008)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=13 index=3")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h1000)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=1c index=12")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0004)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=12 index=2")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0001)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=10 index=0")
   `SVTEST_END

   `SVTEST(one_flipped_bit_is_corrected_in_the_appended_layout)
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0001)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=13 index=0")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0080)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=1c index=7")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0100)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=11 index=8")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h1000)),
                             "HEXK_ECC_CORRECTED data=a5 syndrome=10 index=12")
   `SVTEST_END

   `SVTEST(every_single_flip_is_corrected_for_every_width)
      `FAIL_UNLESS_STR_EQUAL(single_flips(MIN_WIDTH, MAX_WIDTH), "ok")
   `SVTEST_END

   `SVTEST(two_flipped_bits_are_reported_and_the_data_stays_as_received)
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0003)),
                             "HEXK_ECC_UNCORRECTABLE data=a6 syndrome=6 index=-1")
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0003)),
                             "HEXK_ECC_UNCORRECTABLE data=a5 syndrome=1 index=-1")
   `SVTEST_END

   `SVTEST(every_double_flip_is_reported)
      `FAIL_UNLESS_STR_EQUAL(double_flips(4), "ok")
      `FAIL_UNLESS_STR_EQUAL(double_flips(8), "ok")
      `FAIL_UNLESS_STR_EQUAL(double_flips(11), "ok")
      `FAIL_UNLESS_STR_EQUAL(double_flips(16), "ok")
      `FAIL_UNLESS_STR_EQUAL(double_flips(32), "ok")
      `FAIL_UNLESS_STR_EQUAL(double_flips(64), "ok")
      `FAIL_UNLESS_STR_EQUAL(double_flips(128), "ok")
   `SVTEST_END

   `SVTEST(two_code_words_differ_in_at_least_four_bits)
      `FAIL_UNLESS_STR_EQUAL(min_distance(4, 0), "4")
      `FAIL_UNLESS_STR_EQUAL(min_distance(4, 1), "4")
      `FAIL_UNLESS_STR_EQUAL(min_distance(8, 0), "4")
      `FAIL_UNLESS_STR_EQUAL(min_distance(8, 1), "4")
   `SVTEST_END

   `SVTEST(a_syndrome_above_the_code_word_is_uncorrectable)
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(0, hexk_bits_t'(8'hA5), hexk_bits_t'(13'h0112)),
                             "HEXK_ECC_UNCORRECTABLE data=a5 syndrome=1d index=-1")
   `SVTEST_END

   `SVTEST(the_syndrome_is_the_difference_of_the_check_bits)
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_check_difference(8), "ok")
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_check_difference(32), "ok")
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_check_difference(64), "ok")
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_check_difference(128), "ok")
   `SVTEST_END

   `SVTEST(the_interleaved_syndrome_is_the_index_of_the_flipped_bit)
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_index(8), "ok")
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_index(64), "ok")
      `FAIL_UNLESS_STR_EQUAL(syndrome_is_index(128), "ok")
   `SVTEST_END

   `SVTEST(bits_above_the_width_are_ignored)
      `FAIL_UNLESS_STR_EQUAL(stray_bits(), "ignored")
   `SVTEST_END

   `SVTEST(flip_inverts_one_bit)
      `FAIL_UNLESS_STR_EQUAL(flipped(0, 0, 0), "3a4")
      `FAIL_UNLESS_STR_EQUAL(flipped(12, 0, 0), "13a5")
      `FAIL_UNLESS_STR_EQUAL(flipped(12, 4, 1), "13b5")
      `FAIL_UNLESS_STR_EQUAL(flipped(7, 7, 1), "3a5")
      `FAIL_UNLESS_STR_EQUAL(stray_bit_in_flip(), "kept")
   `SVTEST_END

   `SVTEST(flip_with_an_index_above_the_code_word_changes_nothing)
      `FAIL_UNLESS_STR_EQUAL(flipped(13, 0, 0), "3a5")
      `FAIL_UNLESS_STR_EQUAL(flipped(1000, 0, 0), "3a5")
   `SVTEST_END

   `SVTEST(inject_flips_the_number_of_bits_asked_for)
      `FAIL_UNLESS_STR_EQUAL(inject_default_count(), "1")
      `FAIL_UNLESS_STR_EQUAL(inject_count(8, 0), "0")
      `FAIL_UNLESS_STR_EQUAL(inject_count(8, 1), "1")
      `FAIL_UNLESS_STR_EQUAL(inject_count(8, 2), "2")
      `FAIL_UNLESS_STR_EQUAL(inject_count(8, 12), "12")
      `FAIL_UNLESS_STR_EQUAL(inject_count(8, 13), "13")
      `FAIL_UNLESS_STR_EQUAL(inject_count(64, 3), "3")
      `FAIL_UNLESS_STR_EQUAL(inject_count(128, 2), "2")
      `FAIL_UNLESS_STR_EQUAL(inject_count(128, 137), "137")
   `SVTEST_END

   `SVTEST(inject_reaches_every_bit_of_the_code_word)
      `FAIL_UNLESS_STR_EQUAL(inject_union(1), "1fff")
      `FAIL_UNLESS_STR_EQUAL(inject_union(2), "1fff")
   `SVTEST_END

   `SVTEST(inject_with_more_errors_than_bits_flips_every_bit)
      `FAIL_UNLESS_STR_EQUAL(inject_count(8, 14), "13")
      `FAIL_UNLESS_STR_EQUAL(inject_count(128, 1000), "137")
   `SVTEST_END

   `SVTEST(one_injected_error_is_corrected_and_two_are_reported)
      `FAIL_UNLESS_STR_EQUAL(inject_then_decode(0, hexk_ecc::HEXK_ECC_NO_ERROR), "ok")
      `FAIL_UNLESS_STR_EQUAL(inject_then_decode(1, hexk_ecc::HEXK_ECC_CORRECTED), "ok")
      `FAIL_UNLESS_STR_EQUAL(inject_then_decode(2, hexk_ecc::HEXK_ECC_UNCORRECTABLE), "ok")
   `SVTEST_END

   `SVTEST(error_index_is_minus_one_for_a_syndrome_that_names_no_bit)
      `FAIL_UNLESS_STR_EQUAL(decode_flipped(1, hexk_bits_t'(8'hA5), '0),
                             "HEXK_ECC_NO_ERROR data=a5 syndrome=0 index=-1")
      `FAIL_UNLESS_STR_EQUAL(error_index_of(32'h0000_0003), "-1")
      `FAIL_UNLESS_STR_EQUAL(error_index_of(32'h0000_001D), "-1")
      `FAIL_UNLESS_STR_EQUAL(error_index_of(32'h0000_0033), "-1")
      `FAIL_UNLESS_STR_EQUAL(error_index_of(32'hFFFF_FFFF), "-1")
      `FAIL_UNLESS_STR_EQUAL(error_index_of(32'h0000_0013), "3")
   `SVTEST_END

   `SVTEST(an_illegal_data_width_is_replaced_by_the_nearest_legal_one)
      `FAIL_UNLESS_STR_EQUAL(widths_of(0), "4 4 8")
      `FAIL_UNLESS_STR_EQUAL(widths_of(3), "4 4 8")
      `FAIL_UNLESS_STR_EQUAL(widths_of(129), "128 9 137")
      `FAIL_UNLESS_STR_EQUAL(widths_of(1000), "128 9 137")
   `SVTEST_END

`ifndef VERILATOR
   `SVTEST(an_x_or_z_bit_in_the_data_makes_the_code_word_unknown)
      `FAIL_UNLESS_STR_EQUAL(encoded_unknown(0, 1'bx), "000xxxxxxxxxxxxx 000xxxxx")
      `FAIL_UNLESS_STR_EQUAL(encoded_unknown(7, 1'bz), "000xxxxxxxxxxxxx 000xxxxx")
      // Only the eight data bits are used: an X above them changes nothing.
      `FAIL_UNLESS_STR_EQUAL(encoded_unknown(8, 1'bx), encoded_unknown(8, 1'b0))
   `SVTEST_END

   `SVTEST(a_code_word_with_an_x_or_z_bit_is_uncorrectable)
      `FAIL_UNLESS_STR_EQUAL(decoded_unknown(0, 1'bx), "HEXK_ECC_UNCORRECTABLE 0000xxxxxxxx 0")
      `FAIL_UNLESS_STR_EQUAL(decoded_unknown(12, 1'bz), "HEXK_ECC_UNCORRECTABLE 0000xxxxxxxx 0")
      // The code word has 13 bits: an X above them is ignored.
      `FAIL_UNLESS_STR_EQUAL(decoded_unknown(13, 1'bx), "HEXK_ECC_NO_ERROR 000010100100 0")
   `SVTEST_END

   `SVTEST(flip_turns_an_x_bit_into_one)
      `FAIL_UNLESS_STR_EQUAL(flipped_unknown(), "one")
   `SVTEST_END
`endif

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_ecc_unit_test
