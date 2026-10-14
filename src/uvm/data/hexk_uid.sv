// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uid.sv
//
// Hierarchical unique ID of a transaction or of anything else that is created at run time,
// such as "seq_wr:000012/item:000003": the third item of the twelfth write sequence.
// An ID is made of a label and a number and hangs below a parent ID. Every ID counts its
// children per label, so the numbers say "which one of its kind under this parent", and a
// message with the ID of an item names the sequence that made it.
// Top-level IDs come from hexk_uid_pool::new_uid(), children from new_child(). An ID is a
// small object without text; convert2string() builds the text when a message needs it.
// An ID that would get longer than hexk_uid_pool::max_length is an error: that happens when
// an object that is reused takes a child of its own old ID again and again.
//
//! @module    hexk_uid
//! @since     0.7.0
//! @stability experimental
//! @serves    MSG-7
//! @emits     HEXK_UID_LENGTH:error HEXK_UID_LABEL:error
//! @plusargs  (none)

`ifndef HEXK_UID_SV
`define HEXK_UID_SV

typedef class hexk_uid_pool;

class hexk_uid;

   // Digits a number is padded to with zeros.
   localparam int unsigned NUMBER_DIGITS = 6;

   local hexk_uid     parent;
   local string       label;
   local int unsigned number;

   // Length of the text of this ID, kept so that the limit can be checked without building text.
   local int unsigned length;

   // Next number per label for the children of this ID.
   local int unsigned child_counts[string];

   // Creates an ID; use hexk_uid_pool::new_uid() and new_child(), which choose the number.
   function new(hexk_uid uid_parent, string uid_label, int unsigned uid_number);
      parent = uid_parent;
      label  = uid_label;
      number = uid_number;
      length = uid_label.len() + 1 + number_digits(uid_number);
      if (uid_parent != null) begin
         length += uid_parent.length + 1;
      end
   endfunction : new

   // Creates the next child ID with this label: the children of one ID are numbered per label, from 0.
   function hexk_uid new_child(string child_label);
      hexk_uid_pool pool = hexk_uid_pool::get();
      hexk_uid      child;
      if (!child_counts.exists(child_label)) begin
         check_label(child_label);
         child_counts[child_label] = 0;
      end
      child = new(this, child_label, child_counts[child_label]);
      child_counts[child_label]++;
      if (child.length > pool.max_length) begin
         `uvm_error(
             "HEXK_UID_LENGTH",
             $sformatf("%s is %0d characters long, the limit is %0d; %s", child.convert2string(), child.length,
                       pool.max_length,
                       "a reused object probably takes a child of its own old ID; take it from the ID of its creator"))
         // The ID that is returned starts a new chain, so that the text cannot grow without limit.
         child = new(null, child_label, child.number);
      end
      return child;
   endfunction : new_child

   // The text of the ID: the text of the parent, a slash, then "<label>:<number>".
   function string convert2string();
      string own = {label, ":", hexk_str::pad($sformatf("%0d", number), NUMBER_DIGITS, 0, "0")};
      if (parent == null) begin
         return own;
      end
      return {parent.convert2string(), "/", own};
   endfunction : convert2string

   // The ID this one was created under; null for a top-level ID.
   function hexk_uid get_parent();
      return parent;
   endfunction : get_parent

   // The label of this ID.
   function string get_label();
      return label;
   endfunction : get_label

   // The number of this ID among the IDs with its label under its parent.
   function int unsigned get_number();
      return number;
   endfunction : get_number

   // Number of characters of convert2string().
   function int unsigned get_length();
      return length;
   endfunction : get_length

   // Reports a label with one of the two characters that the text of an ID puts between its parts.
   // Called for the first ID of a label, so that the IDs after it cost nothing.
   static function void check_label(string uid_label);
      if (hexk_str::contains(uid_label, ":") || hexk_str::contains(uid_label, "/")) begin
         `hexk_static_error("HEXK_UID_LABEL",
                            $sformatf("the label '%s' has a ':' or a '/', which separate the parts of an ID: %s",
                                      uid_label, "the texts of two different IDs can be equal"))
      end
   endfunction : check_label

   // Number of characters a number takes in the text.
   local static function int unsigned number_digits(int unsigned value);
      int unsigned digits = 1;
      int unsigned rest = value / 10;
      while (rest != 0) begin
         digits++;
         rest /= 10;
      end
      return (digits < NUMBER_DIGITS) ? NUMBER_DIGITS : digits;
   endfunction : number_digits

endclass : hexk_uid

`endif  // HEXK_UID_SV
