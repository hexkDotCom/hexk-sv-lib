// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_value_wrapper.sv
//
// A packed value inside a uvm_object, so that a plain number, vector or packed struct can
// travel through analysis ports, TLM FIFOs and scoreboards, which carry objects.
// T is the type of the value. compare() is exact by default, X and Z bits included; with a
// tolerance above 0 two values are equal when they differ by no more than the tolerance,
// for data that a model predicts only approximately, such as the output of an ADC or a
// filter. The tolerance is a member, not a type parameter, so one port type serves all.
//
//! @module    hexk_value_wrapper
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_VALUE_WRAPPER_WIDTH:error HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_VALUE_WRAPPER_SV
`define HEXK_VALUE_WRAPPER_SV

class hexk_value_wrapper #(
    type T = logic [63:0]
) extends uvm_object;

   // Signed number that holds the difference of two values of at most HEXK_CHECK_WORD_WIDTH bits, signed or not.
   typedef logic signed [HEXK_CHECK_WORD_WIDTH+1:0] word_difference_t;

   // The wrapped value.
   T                value;

   // Largest difference at which compare() of this object calls two values equal; 0 asks for identical bits.
   longint unsigned tolerance = 0;

   `uvm_object_param_utils(hexk_value_wrapper#(T))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   virtual function string get_type_name();
      return "hexk_value_wrapper";
   endfunction : get_type_name

   // Creates a wrapper; the value is that of an uninitialised T.
   function new(string name = "hexk_value_wrapper");
      super.new(name);
   endfunction : new

   // Creates a wrapper through the factory that holds the given value and tolerance.
   static function hexk_value_wrapper#(T) wrap(T wrapped_value, longint unsigned wrapped_tolerance = 0);
      hexk_value_wrapper #(T) wrapper = type_id::create("hexk_value_wrapper");
      wrapper.value     = wrapped_value;
      wrapper.tolerance = wrapped_tolerance;
      return wrapper;
   endfunction : wrap

   // The value in hexadecimal.
   function string convert2string();
      return $sformatf("0x%0h", value);
   endfunction : convert2string

   // UVM hook of compare(): identical bits, or numbers within the tolerance of this object, the expected side when a
   // scoreboard calls expected.compare(actual): a.compare(b) and b.compare(a) differ when the tolerances do. A
   // mismatch is told to the comparer as a difference of the field value.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      bit same = compare_value(rhs);
      hexk_value_wrapper #(T) other;
      if (!same && $cast(other, rhs)) begin
         void'(comparer.compare_field("value", uvm_bitstream_t'(value), uvm_bitstream_t'(other.value), $bits(T)));
      end
      return same;
   endfunction : do_compare

   // 1 when the value of rhs is that of this object within its tolerance.
   local function bit compare_value(uvm_object rhs);
      hexk_value_wrapper #(T) other;
      hexk_check_num_t        own_number;
      hexk_check_num_t        other_number;
      hexk_check_num_t        difference;
      word_difference_t       own_word;
      word_difference_t       other_word;
      word_difference_t       word_difference;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      if (tolerance == 0) begin
         return value === other.value;
      end
      // The usual case in few bits; the width is a constant, so a simulator keeps one of the two ways.
      if ($bits(value) <= HEXK_CHECK_WORD_WIDTH) begin
         own_word        = word_difference_t'(value);
         other_word      = word_difference_t'(other.value);
         word_difference = (own_word > other_word) ? (own_word - other_word) : (other_word - own_word);
         // A value with an X or Z bit is within no tolerance.
         return !$isunknown(word_difference) && word_difference <= word_difference_t'(tolerance);
      end
      if (!hexk_check_stats::fits($bits(value))) begin
         `uvm_error("HEXK_VALUE_WRAPPER_WIDTH",
                    $sformatf(
                        "%s: a tolerance compares at most %0d bits, the value has %0d: the values count as different",
                        get_name(), HEXK_CHECK_MAX_WIDTH, $bits(value)))
         return 0;
      end
      // Each value counts as the number it stands for in T, so a signed T can go below 0.
      own_number   = hexk_check_num_t'(value);
      other_number = hexk_check_num_t'(other.value);
      difference   = (own_number > other_number) ? (own_number - other_number) : (other_number - own_number);
      // A value with an X or Z bit is within no tolerance.
      if ($isunknown(difference)) begin
         return 0;
      end
      return difference <= hexk_check_num_t'(tolerance);
   endfunction : compare_value

   // UVM hook of print() and sprint(): value in hexadecimal and tolerance.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_field("value", uvm_bitstream_t'(value), $bits(T), UVM_HEX);
      printer.print_field_int("tolerance", tolerance, 64, UVM_DEC);
   endfunction : do_print

   // UVM hook of copy() and clone(): copies value and tolerance.
   function void do_copy(uvm_object rhs);
      hexk_value_wrapper #(T) other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      value     = other.value;
      tolerance = other.tolerance;
   endfunction : do_copy

endclass : hexk_value_wrapper

`endif  // HEXK_VALUE_WRAPPER_SV
