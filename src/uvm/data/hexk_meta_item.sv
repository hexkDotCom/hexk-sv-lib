// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_meta_item.sv
//
// An item together with what the testbench knows about it: when it was seen, which ID it
// has and where it came from. T is the class of the item; it is not changed and not copied.
// A monitor or predictor wraps an item with wrap() before it writes it to an analysis port;
// the receiver uses the timestamp for latency, the ID for messages and the source to tell
// streams apart. compare() compares the two wrapped items and nothing else, so a scoreboard
// for meta items checks the same as a scoreboard for the items.
//
//! @module    hexk_meta_item
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_COPY_TYPE:fatal
//! @plusargs  (none)

`ifndef HEXK_META_ITEM_SV
`define HEXK_META_ITEM_SV

class hexk_meta_item #(
    type T = uvm_object
) extends uvm_object;

   // The wrapped item.
   T                item;

   // Simulation time in picoseconds at which the item was wrapped, or whatever the creator stores.
   longint unsigned timestamp_ps;

   // ID of the item for messages; may be null.
   hexk_uid         uid;

   // Where the item came from, such as the full name of a monitor.
   string           source;

   `uvm_object_param_utils(hexk_meta_item#(T))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_meta_item";
   endfunction : get_type_name

   // Creates an empty meta item.
   function new(string name = "hexk_meta_item");
      super.new(name);
   endfunction : new

   // Creates a meta item through the factory for the given item, stamped with the current simulation time.
   static function hexk_meta_item#(T) wrap(T wrapped_item, string item_source = "", hexk_uid item_uid = null);
      hexk_meta_item #(T) meta = type_id::create("meta");
      meta.item         = wrapped_item;
      meta.timestamp_ps = hexk_wait_util::now_ps();
      meta.uid          = item_uid;
      meta.source       = item_source;
      return meta;
   endfunction : wrap

   // ID, time, source and the text of the item, on one line.
   function string convert2string();
      string text = (uid == null) ? "" : {uid.convert2string(), " "};
      text = {text, "@", hexk_wait_util::format_ps(timestamp_ps)};
      if (source.len() != 0) begin
         text = {text, " from ", source};
      end
      return {text, ": ", (item == null) ? "null" : item.convert2string()};
   endfunction : convert2string

   // UVM hook of compare(): compares the wrapped items; timestamp, ID and source are not compared.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_meta_item #(T) other;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      if (item == null || other.item == null) begin
         return item == null && other.item == null;
      end
      return item.compare(other.item, comparer);
   endfunction : do_compare

   // UVM hook of print() and sprint(): ID, time, source and the item with its own fields.
   function void do_print(uvm_printer printer);
      string uid_text;
      super.do_print(printer);
      if (uid != null) begin
         uid_text = uid.convert2string();
      end
      printer.print_string("uid", uid_text);
      printer.print_field_int("timestamp_ps", timestamp_ps, 64, UVM_DEC);
      printer.print_string("source", source);
      printer.print_object("item", item);
   endfunction : do_print

   // UVM hook of copy() and clone(): the copy refers to the same item and ID.
   function void do_copy(uvm_object rhs);
      hexk_meta_item #(T) other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      item         = other.item;
      timestamp_ps = other.timestamp_ps;
      uid          = other.uid;
      source       = other.source;
   endfunction : do_copy

endclass : hexk_meta_item

`endif  // HEXK_META_ITEM_SV
