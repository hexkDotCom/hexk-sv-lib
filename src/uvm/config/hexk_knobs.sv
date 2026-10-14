// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_knobs.sv
//
// Global test knobs: a singleton that holds the few test-wide switches of a testbench, such
// as "coverage on", "gate-level run" or "performance mode", with a default, a help text and
// a plusarg for each.
// The testbench defines its knobs with add_int/add_bit/add_str/add_enum_str, a test may
// change them with set_int/set_str, and +<name>=<value> on the command line wins over both.
// lock() ends the definition phase; hexk_base_test calls it at the end of build_phase. From
// then on the values cannot change and get_int/get_bit/get_str may read them; code outside
// the UVM phases waits with wait_locked(). help() is a table of all knobs with value and
// source. +hexk_knobs_help prints it and ends the simulation; +hexk_knobs_strict reports
// plusargs that look like misspelled knob names.
// Knobs are not a replacement for cfg objects: what configures one component stays in its
// cfg object.
//
//! @module    hexk_knobs
//! @since     0.7.0
//! @stability experimental
//! @serves    TST-4
//! @emits     HEXK_KNOBS_TABLE:info HEXK_KNOBS_HELP:info HEXK_KNOBS_KEPT:info HEXK_KNOBS_DEFINE:error
//! @emits     HEXK_KNOBS_LOCKED:error HEXK_KNOBS_VALUE:error HEXK_KNOBS_STRICT:error HEXK_KNOBS_READ:fatal
//! @plusargs  +hexk_knobs_help +hexk_knobs_strict

`ifndef HEXK_KNOBS_SV
`define HEXK_KNOBS_SV

class hexk_knobs extends uvm_object;

   local static hexk_knobs knobs;

   // The knobs by name, and their names in the order of definition.
   local hexk_knob         entries[string];
   local string            order           [$];

   // Set by lock(): the values are final and may be read.
   local bit               locked;

   `uvm_object_utils(hexk_knobs)

   // Creates a set of knobs; use get(), which returns the one set of the simulation.
   function new(string name = "hexk_knobs");
      super.new(name);
   endfunction : new

   // The one set of knobs of the simulation.
   static function hexk_knobs get();
      if (knobs == null) begin
         knobs = hexk_knobs::type_id::create("knobs");
      end
      return knobs;
   endfunction : get

   // Defines an integer knob; values outside lo..hi are rejected when hi is not below lo.
   function void add_int(string name, longint default_value, string help_text, longint lo = 0, longint hi = -1);
      hexk_knob knob = add_knob(name, hexk_knob::HEXK_KNOB_INT, help_text);
      if (knob == null) begin
         return;
      end
      knob.lo        = lo;
      knob.hi        = hi;
      knob.int_value = default_value;
      if (!is_legal_int(knob, default_value)) begin
         `uvm_error("HEXK_KNOBS_DEFINE", $sformatf("knob '%s': the default %0d is not in %0d..%0d", name,
                                                   default_value, lo, hi))
      end
      if (hexk_plusarg::has(name)) begin
         void'(assign_int(knob, hexk_plusarg::get_int(name, default_value), hexk_knob::HEXK_KNOB_FROM_PLUSARG));
      end
   endfunction : add_int

   // Defines a knob that is 0 or 1; +<name> without a value sets it to 1.
   function void add_bit(string name, bit default_value, string help_text);
      hexk_knob knob = add_knob(name, hexk_knob::HEXK_KNOB_BIT, help_text);
      if (knob == null) begin
         return;
      end
      knob.int_value = longint'(default_value);
      if (hexk_plusarg::has(name)) begin
         void'(
             assign_int(knob, longint'(hexk_plusarg::get_bit(name, default_value)), hexk_knob::HEXK_KNOB_FROM_PLUSARG));
      end
   endfunction : add_bit

   // Defines a knob that holds any string.
   function void add_str(string name, string default_value, string help_text);
      hexk_knob knob = add_knob(name, hexk_knob::HEXK_KNOB_STR, help_text);
      if (knob == null) begin
         return;
      end
      knob.str_value = default_value;
      if (hexk_plusarg::has(name)) begin
         void'(assign_str(knob, hexk_plusarg::get_str(name, default_value), hexk_knob::HEXK_KNOB_FROM_PLUSARG));
      end
   endfunction : add_str

   // Defines a knob that holds one of the strings in legal; enum_type is set by hexk_enum_knob, which checks it.
   function void add_enum_str(string name, string default_value, const ref string legal[$], input string help_text,
                              input string enum_type = "");
      hexk_knob knob = add_knob(name, hexk_knob::HEXK_KNOB_ENUM_STR, help_text);
      if (knob == null) begin
         return;
      end
      knob.legal     = legal;
      knob.str_value = default_value;
      knob.enum_type = enum_type;
      if (!is_one_of(default_value, legal)) begin
         `uvm_error("HEXK_KNOBS_DEFINE", $sformatf("knob '%s': the default '%s' is not one of: %s", name,
                                                   default_value, hexk_str::join_str(legal, ", ")))
      end
      if (hexk_plusarg::has(name)) begin
         void'(assign_str(knob, hexk_plusarg::get_str(name, default_value), hexk_knob::HEXK_KNOB_FROM_PLUSARG));
      end
   endfunction : add_enum_str

   // Sets an integer or bit knob before lock(); a value from the command line is kept.
   function void set_int(string name, longint value);
      hexk_knob knob = find_for_set(name, 1);
      if (knob != null) begin
         void'(assign_int(knob, value, hexk_knob::HEXK_KNOB_FROM_SET));
      end
   endfunction : set_int

   // Sets a string or enumerated string knob before lock(); a value from the command line is kept.
   function void set_str(string name, string value);
      hexk_knob knob = find_for_set(name, 0);
      if (knob != null) begin
         void'(assign_str(knob, value, hexk_knob::HEXK_KNOB_FROM_SET));
      end
   endfunction : set_str

   // Makes the values final and readable, prints the table, and handles +hexk_knobs_help and +hexk_knobs_strict.
   function void lock();
      if (locked) begin
         return;
      end
      locked = 1;
      if (hexk_plusarg::has("hexk_knobs_strict")) begin
         uvm_cmdline_processor cmdline = uvm_cmdline_processor::get_inst();
         string                plusargs                                    [$];
         cmdline.get_plusargs(plusargs);
         void'(check_plusargs(plusargs));
      end
      if (hexk_plusarg::has("hexk_knobs_help")) begin
         `uvm_info("HEXK_KNOBS_HELP", {"+hexk_knobs_help: the simulation ends here\n", help()}, UVM_NONE)
         $finish;
      end
      if (order.size() != 0) begin
         `uvm_info("HEXK_KNOBS_TABLE", {"\n", help()}, UVM_LOW)
      end
   endfunction : lock

   // Value of an integer knob; fatal for an unknown name, another kind of knob, or a read before lock().
   function longint get_int(string name);
      hexk_knob knob = find_for_read(name, hexk_knob::HEXK_KNOB_INT);
      return (knob == null) ? 0 : knob.int_value;
   endfunction : get_int

   // Value of a bit knob; fatal for an unknown name, another kind of knob, or a read before lock().
   function bit get_bit(string name);
      hexk_knob knob = find_for_read(name, hexk_knob::HEXK_KNOB_BIT);
      return (knob == null) ? 0 : (knob.int_value != 0);
   endfunction : get_bit

   // The $typename of the enumeration that hexk_enum_knob defined the knob with; "" for any other or no knob.
   function string enum_type_of(string name);
      return entries.exists(name) ? entries[name].enum_type : "";
   endfunction : enum_type_of

   // Value of a string or enumerated string knob; fatal like get_int.
   function string get_str(string name);
      hexk_knob knob = find_for_read(name, hexk_knob::HEXK_KNOB_STR);
      return (knob == null) ? "" : knob.str_value;
   endfunction : get_str

   // 1 when a knob with this name is defined; may be called at any time.
   function bit has(string name);
      return entries.exists(name) != 0;
   endfunction : has

   // Table of all knobs in the order of definition: name, value, source, help text.
   function string help();
      string       lines           [$];
      int unsigned name_width = 4;
      int unsigned value_width = 5;
      hexk_knob    knob;
      if (order.size() == 0) begin
         return "no knobs are defined";
      end
      foreach (order[i]) begin
         knob = entries[order[i]];
         if (knob.label.len() > name_width) begin
            name_width = knob.label.len();
         end
         if (value_text(knob).len() > value_width) begin
            value_width = value_text(knob).len();
         end
      end
      lines.push_back(table_row("name", name_width, "value", value_width, "source", "help"));
      foreach (order[i]) begin
         knob = entries[order[i]];
         lines.push_back(table_row(
                         knob.label, name_width, value_text(knob), value_width, source_text(knob.source), knob.help_text
                         ));
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : help

   // Waits until lock() has been called; for code outside the UVM phases, such as initial blocks.
   static task wait_locked();
      hexk_knobs the_knobs = get();
      wait (the_knobs.locked);
   endtask : wait_locked

   // Reports every plusarg that is no knob but is one or two characters away from a knob name; returns their number.
   function int unsigned check_plusargs(const ref string plusargs[$]);
      int unsigned findings;
      string       parts     [$];
      string       candidate;
      int unsigned distance;
      foreach (plusargs[i]) begin
         hexk_str::split(plusargs[i], parts, "=", 2);
         candidate = (parts.size() == 0) ? "" : hexk_str::lstrip(parts[0], "+");
         if (candidate.len() == 0 || entries.exists(candidate)) begin
            continue;
         end
         foreach (order[k]) begin
            distance = edit_distance(candidate, order[k]);
            // A short name is within two changes of almost anything: the changes must be few for its length.
            if (distance <= 2 && 2 * distance < order[k].len()) begin
               `uvm_error("HEXK_KNOBS_STRICT", $sformatf("plusarg +%s is not a knob, but it looks like the knob '%s'",
                                                         candidate, order[k]))
               findings++;
               break;
            end
         end
      end
      return findings;
   endfunction : check_plusargs

   // Removes every knob and the lock; for unit tests, which run many tests in one simulation.
   static function void reset_for_test();
      if (knobs != null) begin
         knobs.entries.delete();
         knobs.order.delete();
         knobs.locked = 0;
      end
   endfunction : reset_for_test

   // Creates a knob whose value counts as its default; null and an error when that is not possible.
   local function hexk_knob add_knob(string name, hexk_knob::kind_e kind, string help_text);
      hexk_knob knob;
      if (locked) begin
         `uvm_error("HEXK_KNOBS_LOCKED", $sformatf("knob '%s' is defined after lock(); not defined", name))
         return null;
      end
      if (name.len() == 0) begin
         `uvm_error("HEXK_KNOBS_DEFINE", "a knob needs a name; not defined")
         return null;
      end
      if (entries.exists(name)) begin
         `uvm_error("HEXK_KNOBS_DEFINE", $sformatf("knob '%s' is defined twice; the first definition is kept", name))
         return null;
      end
      knob           = new();
      knob.label     = name;
      knob.kind      = kind;
      knob.source    = hexk_knob::HEXK_KNOB_FROM_DEFAULT;
      knob.help_text = help_text;
      entries[name]  = knob;
      order.push_back(name);
      return knob;
   endfunction : add_knob

   // The knob for a set function, or null with a message when it cannot be set.
   local function hexk_knob find_for_set(string name, bit as_int);
      hexk_knob knob;
      if (locked) begin
         `uvm_error("HEXK_KNOBS_LOCKED", $sformatf("knob '%s' is set after lock(); the value is not changed", name))
         return null;
      end
      if (!entries.exists(name)) begin
         `uvm_error("HEXK_KNOBS_VALUE", $sformatf("there is no knob '%s' to set", name))
         return null;
      end
      knob = entries[name];
      if (as_int != (knob.kind inside {hexk_knob::HEXK_KNOB_INT, hexk_knob::HEXK_KNOB_BIT})) begin
         `uvm_error("HEXK_KNOBS_VALUE", $sformatf("knob '%s' is %s; use %s", name, kind_text(knob),
                                                  as_int ? "set_str()" : "set_int()"))
         return null;
      end
      if (knob.source == hexk_knob::HEXK_KNOB_FROM_PLUSARG) begin
         `uvm_info("HEXK_KNOBS_KEPT", $sformatf("knob '%s' keeps the value %s from the command line", name, value_text(
                                                knob)), UVM_MEDIUM)
         return null;
      end
      return knob;
   endfunction : find_for_set

   // The knob for a get function, or null with a fatal when it cannot be read.
   local function hexk_knob find_for_read(string name, hexk_knob::kind_e kind);
      hexk_knob knob;
      bit       kind_fits;
      if (!entries.exists(name)) begin
         `uvm_fatal("HEXK_KNOBS_READ", $sformatf("there is no knob '%s'", name))
         return null;
      end
      knob = entries[name];
      kind_fits = (knob.kind == kind) ||
          (kind == hexk_knob::HEXK_KNOB_STR && knob.kind == hexk_knob::HEXK_KNOB_ENUM_STR);
      if (!kind_fits) begin
         `uvm_fatal("HEXK_KNOBS_READ", $sformatf("knob '%s' is %s and is read with the wrong get function", name,
                                                 kind_text(knob)))
         return null;
      end
      if (!locked) begin
         `uvm_fatal(
             "HEXK_KNOBS_READ",
             $sformatf("knob '%s' is read before lock(): knobs can be read only once hexk_knobs::lock() made them %s",
                       name, {
                       "final. hexk_base_test locks them in its build_phase; create the components that read a knob, ",
                       "such as one whose covergroup hexk_cg_new creates, after that"}))
         return null;
      end
      return knob;
   endfunction : find_for_read

   // Gives an integer or bit knob a value from the given source; 0 and an error when the value is not legal.
   local function bit assign_int(hexk_knob knob, longint value, hexk_knob::source_e source);
      if (!is_legal_int(knob, value)) begin
         `uvm_error("HEXK_KNOBS_VALUE", $sformatf("knob '%s': %0d from %s is not in %0d..%0d; keeping %0d", knob.label,
                                                  value, source_text(source), knob.lo, knob.hi, knob.int_value))
         return 0;
      end
      knob.int_value = value;
      knob.source    = source;
      return 1;
   endfunction : assign_int

   // Gives a string knob a value from the given source; 0 and an error when the value is not legal.
   local function bit assign_str(hexk_knob knob, string value, hexk_knob::source_e source);
      if (knob.kind == hexk_knob::HEXK_KNOB_ENUM_STR && !is_one_of(value, knob.legal)) begin
         `uvm_error("HEXK_KNOBS_VALUE", $sformatf("knob '%s': '%s' from %s is not one of: %s; keeping '%s'",
                                                  knob.label, value, source_text(source), hexk_str::join_str(
                                                  knob.legal, ", "), knob.str_value))
         return 0;
      end
      knob.str_value = value;
      knob.source    = source;
      return 1;
   endfunction : assign_str

   // 1 when the value is allowed for the knob: 0 or 1 for a bit, within the limits for an integer.
   local function bit is_legal_int(hexk_knob knob, longint value);
      if (knob.kind == hexk_knob::HEXK_KNOB_BIT) begin
         return value inside {0, 1};
      end
      return (knob.hi < knob.lo) || (value >= knob.lo && value <= knob.hi);
   endfunction : is_legal_int

   // The value of a knob as text, as the table of knobs prints it.
   local function string value_text(hexk_knob knob);
      if (knob.kind inside {hexk_knob::HEXK_KNOB_INT, hexk_knob::HEXK_KNOB_BIT}) begin
         return $sformatf("%0d", knob.int_value);
      end
      return knob.str_value;
   endfunction : value_text

   // The kind of a knob as text, for messages.
   local function string kind_text(hexk_knob knob);
      case (knob.kind)
         hexk_knob::HEXK_KNOB_INT: return "an integer";
         hexk_knob::HEXK_KNOB_BIT: return "a bit";
         hexk_knob::HEXK_KNOB_STR: return "a string";
         default:                  return "an enumerated string";
      endcase
   endfunction : kind_text

   // A source as the word that the table of knobs and the messages use.
   local function string source_text(hexk_knob::source_e source);
      case (source)
         hexk_knob::HEXK_KNOB_FROM_PLUSARG: return "plusarg";
         hexk_knob::HEXK_KNOB_FROM_SET:     return "set";
         default:                           return "default";
      endcase
   endfunction : source_text

   // 1 when the value is one of the strings in the list.
   local function bit is_one_of(string value, const ref string list[$]);
      foreach (list[i]) begin
         if (list[i] == value) begin
            return 1;
         end
      end
      return 0;
   endfunction : is_one_of

   // One line of the table of knobs.
   local function string table_row(string name, int unsigned name_width, string value, int unsigned value_width,
                                   string source, string help_text);
      return hexk_str::rstrip(
          $sformatf(
              "  %s  %s  %s  %s",
              hexk_str::pad(
                  name, name_width, 1
              ),
              hexk_str::pad(
                  value, value_width, 1
              ),
              hexk_str::pad(
                  source, 7, 1
              ),
              help_text
          ),
          " "
      );
   endfunction : table_row

   // Number of single-character insertions, deletions and replacements that turn a into b.
   local static function int unsigned edit_distance(string a, string b);
      int unsigned previous[$];
      int unsigned current [$];
      int unsigned cost;
      for (int unsigned j = 0; j <= b.len(); j++) begin
         previous.push_back(j);
         current.push_back(0);
      end
      for (int unsigned i = 1; i <= a.len(); i++) begin
         current[0] = i;
         for (int unsigned j = 1; j <= b.len(); j++) begin
            cost       = (a[i-1] == b[j-1]) ? 0 : 1;
            current[j] = previous[j-1] + cost;
            if (previous[j] + 1 < current[j]) begin
               current[j] = previous[j] + 1;
            end
            if (current[j-1] + 1 < current[j]) begin
               current[j] = current[j-1] + 1;
            end
         end
         previous = current;
      end
      return previous[b.len()];
   endfunction : edit_distance

endclass : hexk_knobs

`endif  // HEXK_KNOBS_SV
