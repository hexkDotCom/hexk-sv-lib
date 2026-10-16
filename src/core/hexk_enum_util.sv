// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_enum_util.sv
//
// Enum utilities as static functions of a class parameterized with the enum type: name
// lookup in both directions, membership test, list of all members, common name prefix,
// name-to-value map and a printable list of names.
// Call them as hexk_enum_util #(my_mode_e)::from_name("MY_MODE_FAST"); no object is needed.
// E must be an enum type; any other type does not compile. No UVM, runs on Verilator.
// The default of E is a placeholder enum, never a useful choice: some tools elaborate a
// parameterized class with its defaults as soon as it is imported by name.
// An unknown name is reported with $error by from_name only; try_from_name reports nothing.
//
//! @module    hexk_enum_util
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_ENUM_UTIL_SV
`define HEXK_ENUM_UTIL_SV

// Default of the type parameter of hexk_enum_util: a placeholder that keeps the class legal when a
// tool elaborates it without an override. Always give your own enum type.
typedef enum bit {HEXK_ENUM_UTIL_NONE} hexk_enum_util_none_e;

// Waiver for Verilator: it folds enum methods on a type parameter into constants and then reports
// the variables that carried the enum value as partly unused. The waiver ends after the class.
// verilator lint_off UNUSEDSIGNAL

virtual class hexk_enum_util #(
    type E = hexk_enum_util_none_e
);

   // Name of value, or "" when value is not a member of E.
   static function string name(E value);
      E item;
      item = item.first();
      repeat (item.num()) begin
         if (item === value) begin
            return item.name();
         end
         item = item.next();
      end
      return "";
   endfunction : name

   // Sets value to the member called enum_name and returns 1; else returns 0 and the first member.
   static function bit try_from_name(string enum_name, output E value, input bit ignore_case = 0);
      E item;
      string wanted = ignore_case ? enum_name.tolower() : enum_name;
      string candidate;
      item  = item.first();
      value = item;
      repeat (item.num()) begin
         candidate = ignore_case ? lower_name(item) : item.name();
         if (candidate == wanted) begin
            value = item;
            return 1;
         end
         item = item.next();
      end
      return 0;
   endfunction : try_from_name

   // Member called enum_name; an unknown name is reported with $error and gives the first member.
   static function E from_name(string enum_name);
      E value;
      if (!try_from_name(enum_name, value)) begin
         $error("hexk_enum_util::from_name: '%s' is not one of: %s", enum_name, to_list_str());
      end
      return value;
   endfunction : from_name

   // True when a member of E has this value. A member that does not fit 64 bits is never found:
   // for such an enum use name(value) != "".
   static function bit is_member(longint value);
      E item;
      item = item.first();
      repeat (item.num()) begin
         if (longint'(item) == value && item == E'(value)) begin
            return 1;
         end
         item = item.next();
      end
      return 0;
   endfunction : is_member

   // Number of members of E.
   static function int num();
      E item;
      return item.num();
   endfunction : num

   // Fills values (cleared first) with every member of E, in declaration order.
   static function void all(ref E values[$]);
      E item;
      item = item.first();
      values.delete();
      repeat (item.num()) begin
         values.push_back(item);
         item = item.next();
      end
   endfunction : all

   // Longest text that every member name starts with and that ends in "_", for example "MY_MODE_".
   static function string common_prefix();
      E item;
      string prefix;
      string candidate;
      int length;
      item   = item.first();
      prefix = item.name();
      repeat (item.num()) begin
         candidate = item.name();
         length    = 0;
         while (length < prefix.len() && length < candidate.len()) begin
            if (prefix[length] != candidate[length]) begin
               break;
            end
            length++;
         end
         prefix = prefix.substr(0, length - 1);
         item   = item.next();
      end
      return prefix.substr(0, hexk_str::rfind(prefix, "_"));
   endfunction : common_prefix

   // Fills map (cleared first) with name-to-value pairs; strip_prefix removes common_prefix() from the names.
   static function void to_map(ref E map[string], input bit strip_prefix = 0);
      E item;
      string full_name;
      string prefix = strip_prefix ? common_prefix() : "";
      int skip = prefix.len();
      item = item.first();
      map.delete();
      repeat (item.num()) begin
         full_name = item.name();
         map[full_name.substr(skip, full_name.len()-1)] = item;
         item = item.next();
      end
   endfunction : to_map

   // All member names in declaration order, joined with sep; for help and error messages.
   static function string to_list_str(string sep = ", ");
      E item;
      string names[$];
      item = item.first();
      repeat (item.num()) begin
         names.push_back(item.name());
         item = item.next();
      end
      return hexk_str::join_str(names, sep);
   endfunction : to_list_str

   // Lower-case name of item.
   local static function string lower_name(E item);
      string text = item.name();
      return text.tolower();
   endfunction : lower_name

endclass : hexk_enum_util
// verilator lint_on UNUSEDSIGNAL

`endif  // HEXK_ENUM_UTIL_SV
