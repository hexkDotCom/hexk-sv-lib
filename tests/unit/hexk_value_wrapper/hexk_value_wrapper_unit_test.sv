// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_value_wrapper_unit_test.sv
//
// SVUnit tests of hexk_value_wrapper, with an unsigned 12-bit type, a signed 8-bit type and
// a packed struct as T. Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_value_wrapper.

`include "svunit_defines.svh"
`include "uvm_macros.svh"

module hexk_value_wrapper_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_value_wrapper;
   import hexk_uvm_pkg::hexk_report_catcher;

   typedef logic [11:0] hexk_ut_sample_t;
   typedef logic signed [7:0] hexk_ut_level_t;
   typedef struct packed {
      logic [3:0] kind;
      logic [7:0] payload;
   } hexk_ut_header_t;
   typedef logic [1100:0] hexk_ut_wide_t;
   // One bit wider than a word of 64 bits, so that a tolerance takes the way of the wide values.
   typedef logic [64:0] hexk_ut_u65_t;
   typedef logic signed [64:0] hexk_ut_s65_t;
   // A type that only the factory test wraps, so that its type override changes no other test.
   typedef logic [5:0] hexk_ut_code_t;

   // A wrapper of codes that the factory test puts in place of hexk_value_wrapper #(hexk_ut_code_t).
   class hexk_ut_code_wrapper extends hexk_value_wrapper #(hexk_ut_code_t);
      `uvm_object_utils(hexk_ut_code_wrapper)

      function new(string object_name = "hexk_ut_code_wrapper");
         super.new(object_name);
      endfunction : new
   endclass : hexk_ut_code_wrapper

   string              name = "hexk_value_wrapper_ut";
   svunit_testcase     svunit_ut;
   hexk_report_catcher catcher;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_VALUE_WRAPPER_WIDTH$", UVM_ERROR, "", 0, -1, UVM_INFO);
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Two values of 1101 bits that differ in bit 1090 only when differ is set, compared with a
   // tolerance: "equal" or "different", then the number of HEXK_VALUE_WRAPPER_WIDTH errors.
   function automatic string compare_wide(bit differ, longint unsigned tolerance);
      hexk_ut_wide_t                       expected = hexk_ut_wide_t'(1000);
      hexk_ut_wide_t                       actual = hexk_ut_wide_t'(1000);
      hexk_value_wrapper #(hexk_ut_wide_t) expected_wrapper;
      hexk_value_wrapper #(hexk_ut_wide_t) actual_wrapper;
      bit                                  equal;
      string                               verdict = "different";
      actual[1090]     = differ;
      expected_wrapper = hexk_value_wrapper#(hexk_ut_wide_t)::wrap(expected, tolerance);
      actual_wrapper   = hexk_value_wrapper#(hexk_ut_wide_t)::wrap(actual);
      equal            = expected_wrapper.compare(actual_wrapper);
      // An if and not ?:, which pads the shorter of two string literals.
      if (equal) begin
         verdict = "equal";
      end
      return $sformatf("%s %0d", verdict, catcher.get_count("^HEXK_VALUE_WRAPPER_WIDTH$", UVM_ERROR));
   endfunction : compare_wide

   // "equal" or "different" for two samples, compared by the wrapper of the first with a tolerance.
   function automatic string compare_samples(hexk_ut_sample_t expected, hexk_ut_sample_t actual,
                                             longint unsigned tolerance = 0);
      hexk_value_wrapper #(hexk_ut_sample_t) expected_wrapper = hexk_value_wrapper#(hexk_ut_sample_t)::wrap(
          expected, tolerance
      );
      hexk_value_wrapper #(hexk_ut_sample_t) actual_wrapper = hexk_value_wrapper#(hexk_ut_sample_t)::wrap(actual);
      if (expected_wrapper.compare(actual_wrapper)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_samples

   // The same for signed levels.
   function automatic string compare_levels(hexk_ut_level_t expected, hexk_ut_level_t actual,
                                            longint unsigned tolerance = 0);
      hexk_value_wrapper #(hexk_ut_level_t) expected_wrapper = hexk_value_wrapper#(hexk_ut_level_t)::wrap(
          expected, tolerance
      );
      hexk_value_wrapper #(hexk_ut_level_t) actual_wrapper = hexk_value_wrapper#(hexk_ut_level_t)::wrap(actual);
      if (expected_wrapper.compare(actual_wrapper)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_levels

   // The same for unsigned values of 65 bits.
   function automatic string compare_u65(hexk_ut_u65_t expected, hexk_ut_u65_t actual, longint unsigned tolerance);
      hexk_value_wrapper #(hexk_ut_u65_t) expected_wrapper = hexk_value_wrapper#(hexk_ut_u65_t)::wrap(
          expected, tolerance
      );
      hexk_value_wrapper #(hexk_ut_u65_t) actual_wrapper = hexk_value_wrapper#(hexk_ut_u65_t)::wrap(actual);
      if (expected_wrapper.compare(actual_wrapper)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_u65

   // The same for signed values of 65 bits.
   function automatic string compare_s65(hexk_ut_s65_t expected, hexk_ut_s65_t actual, longint unsigned tolerance);
      hexk_value_wrapper #(hexk_ut_s65_t) expected_wrapper = hexk_value_wrapper#(hexk_ut_s65_t)::wrap(
          expected, tolerance
      );
      hexk_value_wrapper #(hexk_ut_s65_t) actual_wrapper = hexk_value_wrapper#(hexk_ut_s65_t)::wrap(actual);
      if (expected_wrapper.compare(actual_wrapper)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_s65

   // Number of HEXK_VALUE_WRAPPER_WIDTH errors in this test.
   function automatic string width_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_VALUE_WRAPPER_WIDTH$", UVM_ERROR));
   endfunction : width_errors

   // Text of a wrapped packed struct, and of a clone of it after the original was changed.
   function automatic string struct_texts();
      hexk_ut_header_t                       header = '{kind: 4'hA, payload: 8'h5C};
      hexk_value_wrapper #(hexk_ut_header_t) wrapper = hexk_value_wrapper#(hexk_ut_header_t)::wrap(header, 3);
      hexk_value_wrapper #(hexk_ut_header_t) cloned;
      uvm_object                             copied = wrapper.clone();
      if (!$cast(cloned, copied) || cloned == null) begin
         return "not a clone";
      end
      wrapper.value.payload = 8'h00;
      return $sformatf("%s %s tolerance=%0d", wrapper.convert2string(), cloned.convert2string(), cloned.tolerance);
   endfunction : struct_texts

   // What a comparer like that of hexk_scoreboard noted when expected.compare(actual) found a difference; the lines
   // are joined with " | ".
   function automatic string miscompares(uvm_object expected, uvm_object actual);
      uvm_comparer comparer = new();
      comparer.show_max  = 0;
      comparer.verbosity = UVM_DEBUG;
      void'(expected.compare(actual, comparer));
      return hexk_core_pkg::hexk_str::replace(hexk_core_pkg::hexk_str::strip(comparer.miscompares), "\n", " | ");
   endfunction : miscompares

   // The type name of an object and its fields as the line printer shows them, from the opening brace on; the
   // instance number before it differs from run to run.
   function automatic string printed_fields(uvm_object object);
      uvm_line_printer printer = new();
      string           text = object.sprint(printer);
      int              brace = hexk_core_pkg::hexk_str::find(text, "{");
      return {object.get_type_name(), " ", hexk_core_pkg::hexk_str::strip(text.substr(brace, text.len() - 1))};
   endfunction : printed_fields

   // The difference that the comparer notes when a wrapper with a tolerance compares a value outside of it.
   function automatic string sample_difference(hexk_ut_sample_t expected, hexk_ut_sample_t actual,
                                               longint unsigned tolerance);
      return miscompares(
          hexk_value_wrapper#(hexk_ut_sample_t)::wrap(
              expected, tolerance
          ),
          hexk_value_wrapper#(hexk_ut_sample_t)::wrap(
              actual)
      );
   endfunction : sample_difference

   // The class of the wrapper that wrap() creates while a type override replaces the wrapper of codes.
   function automatic string wrapped_class();
      hexk_value_wrapper#(hexk_ut_code_t)::type_id::set_type_override(hexk_ut_code_wrapper::get_type());
      return hexk_value_wrapper#(hexk_ut_code_t)::wrap(6'h2A, 1).get_type_name();
   endfunction : wrapped_class

   // "equal" or "different" for a wrapper compared with an object of another class.
   function automatic string compare_with_other_type();
      hexk_value_wrapper #(hexk_ut_sample_t) wrapper = hexk_value_wrapper#(hexk_ut_sample_t)::wrap(12'h123);
      hexk_value_wrapper #(hexk_ut_level_t)  other = hexk_value_wrapper#(hexk_ut_level_t)::wrap(8'sh23);
      // UVM reports the type mismatch itself; only the result matters here.
      uvm_comparer                           comparer = new();
      comparer.show_max = 0;
      if (wrapper.do_compare(other, comparer)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_with_other_type

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(without_a_tolerance_the_bits_must_be_identical)
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'h5A5, 12'h5A5), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'h5A5, 12'h5A4), "different")
   `SVTEST_END

   `SVTEST(with_a_tolerance_values_within_it_are_equal)
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd100, 12'd103, 3), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd100, 12'd97, 3), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd100, 12'd104, 3), "different")
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd100, 12'd96, 3), "different")
   `SVTEST_END

   `SVTEST(an_unsigned_value_does_not_wrap_around_within_the_tolerance)
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd0, 12'hFFF, 2), "different")
   `SVTEST_END

   `SVTEST(a_signed_value_is_compared_as_a_signed_number)
      `FAIL_UNLESS_STR_EQUAL(compare_levels(-8'sd1, 8'sd1, 2), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_levels(-8'sd2, 8'sd1, 2), "different")
      `FAIL_UNLESS_STR_EQUAL(compare_levels(-8'sd128, 8'sd127, 254), "different")
      `FAIL_UNLESS_STR_EQUAL(compare_levels(-8'sd128, 8'sd127, 255), "equal")
   `SVTEST_END

   `SVTEST(a_packed_struct_is_printed_in_hex_and_a_clone_keeps_value_and_tolerance)
      `FAIL_UNLESS_STR_EQUAL(struct_texts(), "0xa00 0xa5c tolerance=3")
   `SVTEST_END

   `SVTEST(an_unsigned_value_of_65_bits_is_compared_with_a_tolerance)
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h1_0000_0000_0000_0000, 65'h1_0000_0000_0000_0005, 5), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h1_0000_0000_0000_0000, 65'h1_0000_0000_0000_0006, 5), "different")
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h1_0000_0000_0000_0005, 65'h1_0000_0000_0000_0000, 5), "equal")
      // A difference of 1 across bit 64, and one of 2**64 in bit 64 only.
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h1_0000_0000_0000_0000, 65'h0_FFFF_FFFF_FFFF_FFFF, 1), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h1_0000_0000_0000_0003, 65'h0_0000_0000_0000_0003,
                                         64'hFFFF_FFFF_FFFF_FFFF), "different")
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h0_FFFF_FFFF_FFFF_FFFF, 65'h0_0000_0000_0000_0000,
                                         64'hFFFF_FFFF_FFFF_FFFF), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_u65(65'h0, 65'h1_FFFF_FFFF_FFFF_FFFF, 2), "different")
      `FAIL_UNLESS_STR_EQUAL(width_errors(), "0")
   `SVTEST_END

   `SVTEST(a_signed_value_of_65_bits_is_compared_as_a_signed_number_with_a_tolerance)
      // -1 and 1.
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h1_FFFF_FFFF_FFFF_FFFF, 65'h0_0000_0000_0000_0001, 2), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h1_FFFF_FFFF_FFFF_FFFF, 65'h0_0000_0000_0000_0001, 1), "different")
      // The smallest value, -2**64, and 3 above it.
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h1_0000_0000_0000_0000, 65'h1_0000_0000_0000_0003, 3), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h1_0000_0000_0000_0000, 65'h1_0000_0000_0000_0003, 2), "different")
      // The largest value, 2**64 - 1, and 4 below it.
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h0_FFFF_FFFF_FFFF_FFFF, 65'h0_FFFF_FFFF_FFFF_FFFB, 4), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h0_FFFF_FFFF_FFFF_FFFF, 65'h0_FFFF_FFFF_FFFF_FFFA, 4), "different")
      // The smallest and the largest value are 2**65 - 1 apart, more than any tolerance.
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h1_0000_0000_0000_0000, 65'h0_FFFF_FFFF_FFFF_FFFF,
                                         64'hFFFF_FFFF_FFFF_FFFF), "different")
      // -2**63 and 2**63 - 1 are 2**64 - 1 apart.
      `FAIL_UNLESS_STR_EQUAL(compare_s65(65'h1_8000_0000_0000_0000, 65'h0_7FFF_FFFF_FFFF_FFFF,
                                         64'hFFFF_FFFF_FFFF_FFFF), "equal")
      `FAIL_UNLESS_STR_EQUAL(width_errors(), "0")
   `SVTEST_END

   `SVTEST(a_value_wider_than_the_vector_width_is_compared_exactly_without_a_tolerance)
      `FAIL_UNLESS_STR_EQUAL(compare_wide(0, 0), "equal 0")
      `FAIL_UNLESS_STR_EQUAL(compare_wide(1, 0), "different 0")
   `SVTEST_END

   `SVTEST(a_value_wider_than_the_vector_width_cannot_be_compared_with_a_tolerance)
      `FAIL_UNLESS_STR_EQUAL(compare_wide(1, 5), "different 1")
   `SVTEST_END

   `SVTEST(the_tolerance_is_that_of_the_object_whose_compare_is_called)
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd100, 12'd103, 3), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'd103, 12'd100), "different")
   `SVTEST_END

   `SVTEST(a_difference_is_noted_in_the_comparer_as_one_of_the_field_value)
      `FAIL_UNLESS_STR_EQUAL(sample_difference(12'd100, 12'd104, 3),
         "wrapper.value: lhs = 'h64 : rhs = 'h68")
      `FAIL_UNLESS_STR_EQUAL(sample_difference(12'd100, 12'd103, 3), "")
   `SVTEST_END

   `SVTEST(a_wrapper_prints_its_value_and_tolerance)
      `FAIL_UNLESS_STR_EQUAL(printed_fields(hexk_value_wrapper#(hexk_ut_sample_t)::wrap(12'h5A5, 3)),
         "hexk_value_wrapper { value: 'h5a5  tolerance: 'd3  }")
   `SVTEST_END

   `SVTEST(wrap_creates_the_wrapper_through_the_factory)
      `FAIL_UNLESS_STR_EQUAL(wrapped_class(), "hexk_ut_code_wrapper")
   `SVTEST_END

   `SVTEST(an_object_of_another_class_is_different)
      `FAIL_UNLESS_STR_EQUAL(compare_with_other_type(), "different")
   `SVTEST_END

   // Variables have two states on Verilator, so the tests with X bits run on four-state
   // simulators only.
`ifndef VERILATOR
   `SVTEST(without_a_tolerance_x_bits_must_match)
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'h5Ax, 12'h5Ax), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'h5Ax, 12'h5A0), "different")
   `SVTEST_END

   `SVTEST(with_a_tolerance_a_value_with_x_bits_is_different)
      `FAIL_UNLESS_STR_EQUAL(compare_samples(12'h5Ax, 12'h5Ax, 4), "different")
   `SVTEST_END
`endif

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_value_wrapper_unit_test
