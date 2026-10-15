// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_enum_knob.sv
//
// A knob of hexk_knobs whose value is a member of an enumeration, so that the code that
// reads the knob gets the enumeration and not a string.
// hexk_enum_knob #(my_mode_e)::add("mode", MY_MODE_FAST, "help") defines the knob and
// hexk_enum_knob #(my_mode_e)::get("mode") returns its member after hexk_knobs::lock().
// On the command line the value is the member name in lower case without the text that all
// member names start with: +mode=slow for MY_MODE_SLOW.
// The knob is an enumerated string knob of hexk_knobs: the table, +hexk_knobs_help, the
// strict check and the rule "a plusarg wins over set" work as for every other knob.
//
//! @module    hexk_knobs
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_KNOBS_VALUE:error HEXK_KNOBS_TYPE:error HEXK_KNOBS_ENUM:error
//! @plusargs  (none)

`ifndef HEXK_ENUM_KNOB_SV
`define HEXK_ENUM_KNOB_SV

virtual class hexk_enum_knob #(
    type E = hexk_core_pkg::hexk_enum_util_none_e
);

   // The member of E for each command-line text; filled when first needed.
   local static E values[string];

   // Defines the knob; its legal values are the texts of all members of E. Two members with the same text, such
   // as MODE_A and MODE_a, could not be told apart on the command line: the error HEXK_KNOBS_ENUM, and the knob
   // is not defined.
   static function void add(string name, E default_value, string help_text);
      hexk_knobs knobs = hexk_knobs::get();
      E          members                   [$];
      string     legal                     [$];
      bit        seen                      [string];
      hexk_enum_util#(E)::all(members);
      foreach (members[i]) begin
         string text = text_of(members[i]);
         if (seen.exists(text)) begin
            `hexk_static_error(
                "HEXK_KNOBS_ENUM",
                $sformatf("knob '%s' is not defined: two members of %s have the text '%s' on the command line", name,
                          $typename(E), text))
            return;
         end
         seen[text] = 1;
         legal.push_back(text);
      end
      knobs.add_enum_str(name, text_of(default_value), legal, help_text, $typename(E));
   endfunction : add

   // Sets the knob before hexk_knobs::lock(); a value from the command line is kept.
   static function void set(string name, E value);
      hexk_knobs knobs = hexk_knobs::get();
      if (!is_own_knob(knobs, name, "set")) begin
         return;
      end
      knobs.set_str(name, text_of(value));
   endfunction : set

   // Value of the knob; fatal like hexk_knobs::get_str, and an error when the knob was not defined with add().
   static function E get(string name);
      hexk_knobs knobs = hexk_knobs::get();
      string     text;
      E          members                   [$];
      E          fallback;
      if (!is_own_knob(knobs, name, "read")) begin
         return fallback.first();
      end
      text = knobs.get_str(name);
      if (values.size() == 0) begin
         hexk_enum_util#(E)::all(members);
         foreach (members[i]) begin
            values[text_of(members[i])] = members[i];
         end
      end
      if (!values.exists(text)) begin
         `hexk_static_error("HEXK_KNOBS_VALUE",
                            $sformatf("knob '%s' holds '%s', which is no member of the enumeration it is read as",
                                      name, text))
         return fallback.first();
      end
      return values[text];
   endfunction : get

   // 1 when the knob does not exist (get_str and set_str report that) or add() of this E defined it; otherwise
   // 0 and the error HEXK_KNOBS_TYPE, because another enumeration with the same texts would read it silently.
   local static function bit is_own_knob(hexk_knobs knobs, string name, string action);
      string defined_as = knobs.enum_type_of(name);
      string holds = {"it was defined as ", defined_as};
      if (!knobs.has(name) || defined_as == $typename(E)) begin
         return 1;
      end
      // An if and not ?: of two texts: ?: of two literals is a packed value, in which the shorter one is padded
      // with NULs.
      if (defined_as.len() == 0) begin
         holds = "it holds a plain string";
      end
      `hexk_static_error("HEXK_KNOBS_TYPE", $sformatf("knob '%s' is %s as %s, but %s", name, action, $typename(E), holds
                         ))
      return 0;
   endfunction : is_own_knob

   // Text of a member on the command line: its name in lower case without the common prefix; "" for no member.
   static function string text_of(E value);
      string full_name = hexk_enum_util#(E)::name(value);
      string prefix = hexk_enum_util#(E)::common_prefix();
      string short_name = full_name.substr(prefix.len(), full_name.len() - 1);
      return short_name.tolower();
   endfunction : text_of

endclass : hexk_enum_knob

`endif  // HEXK_ENUM_KNOB_SV
