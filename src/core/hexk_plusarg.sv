// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_plusarg.sv
//
// Command-line plusargs as static functions with a default value: presence test, integer,
// string, bit, real and list. Call them as hexk_plusarg::get_int("my_depth", 16), where
// the name is given without the plus sign. No UVM, so it also works in modules and on Verilator.
// A plusarg is matched exactly: +my_depth_max does not count as +my_depth. Integers accept
// decimal, 0x and 0b prefixes, Verilog bases ('h, 'd, 'o, 'b, with an optional size) and "_".
// A value that cannot be parsed is reported with $error and the default is returned.
// Limit of the language: the form without a value (+name) is not seen when a longer plusarg
// that starts with the same text comes before it on the command line; +name=1 always is.
//
//! @module    hexk_plusarg
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_PLUSARG_SV
`define HEXK_PLUSARG_SV

virtual class hexk_plusarg;

   // How a plusarg appears on the command line: not at all, as +name, or as +name=<value>.
   typedef enum {
      HEXK_PLUSARG_ABSENT,
      HEXK_PLUSARG_BARE,
      HEXK_PLUSARG_VALUE
   } form_e;

   // Number bases that get_int accepts.
   localparam longint unsigned BASE_BINARY = 2;
   localparam longint unsigned BASE_OCTAL = 8;
   localparam longint unsigned BASE_DECIMAL = 10;
   localparam longint unsigned BASE_HEX = 16;

   // True when +name or +name=<value> is on the command line.
   static function bit has(string name);
      // The value is not needed here, which Verilator lint reports as an unused variable.
      // verilator lint_off UNUSEDSIGNAL
      string value;
      // verilator lint_on UNUSEDSIGNAL
      return lookup(name, value) != HEXK_PLUSARG_ABSENT;
   endfunction : has

   // Value of +name=<integer>; default_value when the plusarg is absent or is not an integer.
   static function longint get_int(string name, longint default_value);
      string  value;
      longint result;
      form_e  form = lookup(name, value);
      if (form == HEXK_PLUSARG_ABSENT) begin
         return default_value;
      end
      if (form == HEXK_PLUSARG_BARE || !parse_int(value, result)) begin
         $error("hexk_plusarg::get_int: +%s needs an integer value, got '%s'; using %0d", name, value, default_value);
         return default_value;
      end
      return result;
   endfunction : get_int

   // Value of +name=<text>; default_value when the plusarg is absent or has no value.
   static function string get_str(string name, string default_value);
      string value;
      return (lookup(name, value) == HEXK_PLUSARG_VALUE) ? value : default_value;
   endfunction : get_str

   // 1 for +name, the value for +name=<0, 1, true, false, yes, no, on, off or integer>; else default_value.
   static function bit get_bit(string name, bit default_value);
      string  value;
      string  word;
      longint number;
      form_e  form = lookup(name, value);
      if (form == HEXK_PLUSARG_ABSENT) begin
         return default_value;
      end
      if (form == HEXK_PLUSARG_BARE) begin
         return 1;
      end
      if (parse_int(value, number)) begin
         return number != 0;
      end
      word = value.tolower();
      if (word == "true" || word == "yes" || word == "on") begin
         return 1;
      end
      if (word == "false" || word == "no" || word == "off") begin
         return 0;
      end
      $error("hexk_plusarg::get_bit: +%s=%s is not a bit value; using %0b", name, value, default_value);
      return default_value;
   endfunction : get_bit

   // Value of +name=<real number>; default_value when the plusarg is absent or is not a number.
   static function real get_real(string name, real default_value);
      string value;
      real   result;
      form_e form = lookup(name, value);
      if (form == HEXK_PLUSARG_ABSENT) begin
         return default_value;
      end
      if (form == HEXK_PLUSARG_BARE || !parse_real(value, result)) begin
         $error("hexk_plusarg::get_real: +%s needs a real value, got '%s'; using %g", name, value, default_value);
         return default_value;
      end
      return result;
   endfunction : get_real

   // Fills values (cleared first) with the sep-separated fields of +name=<a,b,c>; empty when there is no value.
   static function void get_list(string name, ref string values[$], input byte sep = ",");
      string value;
      values.delete();
      if (lookup(name, value) == HEXK_PLUSARG_VALUE) begin
         hexk_str::split(value, values, sep);
      end
   endfunction : get_list

   // Finds +name exactly and returns its form; value is the text after "=", or "".
   local static function form_e lookup(string name, output string value);
      string rest;
      value = "";
      if ($value$plusargs({name, "=%s"}, value)) begin
         return HEXK_PLUSARG_VALUE;
      end
      if (!$test$plusargs(name)) begin
         return HEXK_PLUSARG_ABSENT;
      end
      // Some plusarg starts with name. The remainder of the first such plusarg tells which.
      if (!$value$plusargs({name, "%s"}, rest)) begin
         return HEXK_PLUSARG_BARE;
      end
      if (rest.len() == 0) begin
         return HEXK_PLUSARG_BARE;
      end
      if (rest[0] == "=") begin
         value = rest.substr(1, rest.len() - 1);
         return HEXK_PLUSARG_VALUE;
      end
      return HEXK_PLUSARG_ABSENT;
   endfunction : lookup

   // Converts text to an integer; returns 0 when text is not a legal integer of at most 64 bits. A decimal number
   // must fit a longint (-2**63 to 2**63-1); a hexadecimal, binary or Verilog literal may use all 64 bits as a bit
   // pattern, so 0xFFFF_FFFF_FFFF_FFFF is -1.
   local static function bit parse_int(string text, output longint value);
      string           digits = hexk_str::replace(text.tolower(), "_", "");
      longint unsigned magnitude;
      longint unsigned limit;
      longint unsigned digit;
      longint unsigned base = BASE_DECIMAL;
      bit              negative;
      int              quote;
      value = 0;
      if (hexk_str::starts_with(digits, "-") || hexk_str::starts_with(digits, "+")) begin
         negative = (digits[0] == "-");
         digits   = digits.substr(1, digits.len() - 1);
      end
      quote = hexk_str::find(digits, "'");
      if (quote >= 0) begin
         // Verilog literal: an optional decimal size, a quote, a base letter.
         if (quote != 0 && !is_number(digits.substr(0, quote - 1), BASE_DECIMAL)) begin
            return 0;
         end
         base   = base_of(digits.substr(quote + 1, quote + 1));
         digits = digits.substr(quote + 2, digits.len() - 1);
      end else if (hexk_str::starts_with(digits, "0x")) begin
         base   = BASE_HEX;
         digits = digits.substr(2, digits.len() - 1);
      end else if (hexk_str::starts_with(digits, "0b")) begin
         base   = BASE_BINARY;
         digits = digits.substr(2, digits.len() - 1);
      end
      if (base == 0 || !is_number(digits, base)) begin
         return 0;
      end
      limit = '1;
      // A decimal number is a number, not a bit pattern: it must fit a longint with its sign.
      if (base == BASE_DECIMAL && quote < 0) begin
         limit = negative ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF;
      end
      foreach (digits[i]) begin
         digit = digit_of(digits[i]);
         if (magnitude > (limit - digit) / base) begin
            return 0;
         end
         magnitude = magnitude * base + digit;
      end
      value = negative ? -longint'(magnitude) : longint'(magnitude);
      return 1;
   endfunction : parse_int

   // Converts text to a real; returns 0 unless text is [sign] digits [. digits] [e [sign] digits].
   local static function bit parse_real(string text, output real value);
      int position = skip_sign(text, 0);
      int digits_end = skip_digits(text, position);
      int mantissa_digits = digits_end - position;
      int exponent_start;
      value    = 0.0;
      position = digits_end;
      if (position < text.len() && text[position] == ".") begin
         digits_end      = skip_digits(text, position + 1);
         mantissa_digits = mantissa_digits + digits_end - position - 1;
         position        = digits_end;
      end
      if (mantissa_digits == 0) begin
         return 0;
      end
      if (position < text.len() && (text[position] == "e" || text[position] == "E")) begin
         exponent_start = skip_sign(text, position + 1);
         position       = skip_digits(text, exponent_start);
         if (position == exponent_start) begin
            return 0;
         end
      end
      if (position != text.len()) begin
         return 0;
      end
      value = text.atoreal();
      return 1;
   endfunction : parse_real

   // Position after an optional sign at position start of text.
   local static function int skip_sign(string text, int start);
      if (start < text.len() && (text[start] == "-" || text[start] == "+")) begin
         return start + 1;
      end
      return start;
   endfunction : skip_sign

   // Position after the run of decimal digits that begins at position start of text.
   local static function int skip_digits(string text, int start);
      int position = start;
      while (position < text.len()) begin
         if (digit_of(text[position]) >= BASE_DECIMAL) begin
            break;
         end
         position++;
      end
      return position;
   endfunction : skip_digits

   // Base selected by the letter after the quote of a Verilog literal; 0 when the letter is not a base.
   local static function longint unsigned base_of(string letter);
      case (letter)
         "h":     return BASE_HEX;
         "d":     return BASE_DECIMAL;
         "o":     return BASE_OCTAL;
         "b":     return BASE_BINARY;
         default: return 0;
      endcase
   endfunction : base_of

   // True when text is not empty and every character is a digit of the given base.
   local static function bit is_number(string text, longint unsigned base);
      if (text.len() == 0) begin
         return 0;
      end
      foreach (text[i]) begin
         if (digit_of(text[i]) >= base) begin
            return 0;
         end
      end
      return 1;
   endfunction : is_number

   // Value of the digit c (0 to 9, a to f); BASE_HEX, which no digit reaches, for any other character.
   local static function longint unsigned digit_of(byte c);
      if (c >= "0" && c <= "9") begin
         return distance(c, "0");
      end
      if (c >= "a" && c <= "f") begin
         return distance(c, "a") + BASE_DECIMAL;
      end
      return BASE_HEX;
   endfunction : digit_of

   // Number of character codes from first to c.
   local static function longint unsigned distance(byte c, byte first);
      byte unsigned offset = c - first;
      return longint'(offset);
   endfunction : distance

endclass : hexk_plusarg

`endif  // HEXK_PLUSARG_SV
