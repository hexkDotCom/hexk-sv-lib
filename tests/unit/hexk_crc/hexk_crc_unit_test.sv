// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_crc_unit_test.sv
//
// SVUnit tests of hexk_crc.
// Every preset and a few custom models are checked against the catalogue check value, the
// CRC of the nine ASCII characters "123456789". The other tests cover incremental feeding,
// get() and reset(), the serial bit interface and illegal arguments. Results are compared
// as text (see tests/unit/README.md). Runs on Verilator: make test SIM=verilator TEST=hexk_crc.

`include "svunit_defines.svh"

module hexk_crc_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_crc;
   import hexk_core_pkg::hexk_bits_t;

   // Width of the vector of update_bits (HEXK_MAX_WIDTH).
   localparam int unsigned VECTOR_WIDTH = hexk_crc::VECTOR_WIDTH;

   localparam string CHECK_MESSAGE = "123456789";
   localparam int unsigned BYTE_WIDTH = 8;

   string          name = "hexk_crc_ut";
   svunit_testcase svunit_ut;

   byte unsigned   data                 [$];

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // Fills the module-level data queue with the characters of text.
   function automatic void set_data(string text);
      data.delete();
      foreach (text[i]) begin
         data.push_back(text[i]);
      end
   endfunction : set_data

   // Hex text of a CRC value.
   function automatic string hex(longint unsigned value);
      return $sformatf("%0h", value);
   endfunction : hex

   // CRC of text with model, through hexk_crc::compute.
   function automatic string crc_of(hexk_crc model, string text);
      set_data(text);
      return hex(hexk_crc::compute(model, data));
   endfunction : crc_of

   // CRC of the check message with a model built from the six parameters.
   function automatic string custom_check(int unsigned width, longint unsigned poly, longint unsigned init, bit refin,
                                          bit refout, longint unsigned xorout);
      hexk_crc model = new(width, poly, init, refin, refout, xorout);
      return crc_of(model, CHECK_MESSAGE);
   endfunction : custom_check

   // CRC of text fed one byte at a time, reading get() after every byte.
   function automatic string bytewise(hexk_crc model, string text);
      longint unsigned running;
      model.reset();
      foreach (text[i]) begin
         model.update_byte(text[i]);
         running = model.get();
      end
      return hex(running);
   endfunction : bytewise

   // CRC of text fed through update_bits, eight bits per call; mirror reverses the bits of each byte first.
   function automatic string bitwise(hexk_crc model, string text, bit mirror);
      hexk_bits_t   bits;
      byte unsigned character;
      model.reset();
      foreach (text[i]) begin
         character = text[i];
         bits      = '0;
         for (int unsigned b = 0; b < BYTE_WIDTH; b++) begin
            bits[b] = mirror ? character[BYTE_WIDTH-1-b] : character[b];
         end
         model.update_bits(bits, BYTE_WIDTH);
      end
      return hex(model.get());
   endfunction : bitwise

   // CRC-32 of the check message fed as one 72-bit vector plus extra bits that must be ignored.
   function automatic string one_vector();
      hexk_crc model = hexk_crc::crc32();
      hexk_bits_t bits = '1;
      bits[71:0] = 72'h39_38_37_36_35_34_33_32_31;
      model.update_bits(bits, 72);
      model.update_bits(bits, 0);
      return hex(model.get());
   endfunction : one_vector

   // CRC-32 of "1234" then, after reset(), of the check message.
   function automatic string after_reset();
      hexk_crc model = hexk_crc::crc32();
      set_data("1234");
      model.update_bytes(data);
      model.reset();
      set_data(CHECK_MESSAGE);
      model.update_bytes(data);
      return hex(model.get());
   endfunction : after_reset

   // compute() with a null model.
   function automatic string null_model();
      hexk_crc model;
      set_data(CHECK_MESSAGE);
      return hex(hexk_crc::compute(model, data));
   endfunction : null_model

   // update_bits with more bits than the vector holds: all-ones vector, CRC-8.
   function automatic string too_many_bits();
      hexk_crc limited = hexk_crc::crc8();
      hexk_crc exact = hexk_crc::crc8();
      hexk_bits_t bits = '1;
      limited.update_bits(bits, VECTOR_WIDTH + 1);
      exact.update_bits(bits, VECTOR_WIDTH);
      return (limited.get() == exact.get()) ? "same" : "different";
   endfunction : too_many_bits

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(presets_give_the_catalogue_check_values)
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc8(), CHECK_MESSAGE), "f4")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc16_ccitt(), CHECK_MESSAGE), "29b1")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc16_ibm(), CHECK_MESSAGE), "bb3d")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc32(), CHECK_MESSAGE), "cbf43926")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc32c(), CHECK_MESSAGE), "e3069283")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc64_ecma(), CHECK_MESSAGE), "6c40df5f0b497347")
   `SVTEST_END

   `SVTEST(custom_models_give_the_catalogue_check_values)
      `FAIL_UNLESS_STR_EQUAL(custom_check(5, 64'h05, 64'h1F, 1, 1, 64'h1F), "19")
      `FAIL_UNLESS_STR_EQUAL(custom_check(7, 64'h09, 64'h00, 0, 0, 64'h00), "75")
      `FAIL_UNLESS_STR_EQUAL(custom_check(16, 64'h1021, 64'h0000, 1, 1, 64'h0000), "2189")
      `FAIL_UNLESS_STR_EQUAL(custom_check(16, 64'h1021, 64'h0000, 0, 0, 64'h0000), "31c3")
      `FAIL_UNLESS_STR_EQUAL(custom_check(64, 64'h42F0_E1EB_A9EA_3693, 64'hFFFF_FFFF_FFFF_FFFF, 1, 1,
                                          64'hFFFF_FFFF_FFFF_FFFF), "995dc9bbdf1939fa")
   `SVTEST_END

   `SVTEST(crc_of_an_empty_message_is_init_xor_xorout)
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc8(), ""), "0")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc16_ccitt(), ""), "ffff")
      `FAIL_UNLESS_STR_EQUAL(crc_of(hexk_crc::crc32(), ""), "0")
   `SVTEST_END

   `SVTEST(feeding_byte_by_byte_gives_the_same_crc)
      `FAIL_UNLESS_STR_EQUAL(bytewise(hexk_crc::crc32(), CHECK_MESSAGE), "cbf43926")
      `FAIL_UNLESS_STR_EQUAL(bytewise(hexk_crc::crc16_ccitt(), CHECK_MESSAGE), "29b1")
   `SVTEST_END

   `SVTEST(reset_starts_a_new_message)
      `FAIL_UNLESS_STR_EQUAL(after_reset(), "cbf43926")
   `SVTEST_END

   `SVTEST(update_bits_takes_bit_0_first)
      `FAIL_UNLESS_STR_EQUAL(bitwise(hexk_crc::crc32(), CHECK_MESSAGE, 0), "cbf43926")
      `FAIL_UNLESS_STR_EQUAL(bitwise(hexk_crc::crc16_ibm(), CHECK_MESSAGE, 0), "bb3d")
   `SVTEST_END

   `SVTEST(update_bits_needs_mirrored_bytes_for_an_unreflected_crc)
      `FAIL_UNLESS_STR_EQUAL(bitwise(hexk_crc::crc8(), CHECK_MESSAGE, 1), "f4")
      `FAIL_UNLESS_STR_EQUAL(bitwise(hexk_crc::crc64_ecma(), CHECK_MESSAGE, 1), "6c40df5f0b497347")
   `SVTEST_END

   `SVTEST(update_bits_reads_num_bits_bits_of_one_vector)
      `FAIL_UNLESS_STR_EQUAL(one_vector(), "cbf43926")
   `SVTEST_END

   `SVTEST(a_width_of_one_gives_a_parity_bit)
      `FAIL_UNLESS_STR_EQUAL(custom_check(1, 64'h1, 64'h0, 0, 0, 64'h0), "1")
   `SVTEST_END

   `SVTEST(an_illegal_width_is_replaced_by_64)
      `FAIL_UNLESS_STR_EQUAL(custom_check(0, 64'h42F0_E1EB_A9EA_3693, 64'h0, 0, 0, 64'h0), "6c40df5f0b497347")
      `FAIL_UNLESS_STR_EQUAL(custom_check(65, 64'h42F0_E1EB_A9EA_3693, 64'h0, 0, 0, 64'h0), "6c40df5f0b497347")
   `SVTEST_END

   `SVTEST(compute_with_a_null_model_returns_zero)
      `FAIL_UNLESS_STR_EQUAL(null_model(), "0")
   `SVTEST_END

   `SVTEST(update_bits_limits_num_bits_to_the_vector_width)
      `FAIL_UNLESS_STR_EQUAL(too_many_bits(), "same")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_crc_unit_test
