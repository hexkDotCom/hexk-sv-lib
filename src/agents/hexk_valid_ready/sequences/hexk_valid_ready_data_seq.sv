// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_data_seq.sv
//
// Sequence that sends the words of a queue, one transfer each, in order.
// The starter fills words and starts the sequence on the sequencer of an initiator
// hexk_valid_ready_agent; it ends at the transfer of the last word. delay_cycles is the
// delay of every item: below 0, which a plain randomize() gives, the driver takes the
// delays from the cfg of the agent; 0 sends the words back to back.
// An item is randomized before data and delay are assigned only when the factory gives a
// class derived from hexk_valid_ready_item, whose own random fields then get values; a plain
// item is not, since every random field of it is assigned (a randomization costs several
// times the rest of the item). The factory is asked once per start of the sequence, and every
// item of that start is made of the class it gave.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_VALID_READY_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_DATA_SEQ_SV
`define HEXK_VALID_READY_DATA_SEQ_SV

class hexk_valid_ready_data_seq #(
    int DATA_WIDTH = 32
) extends uvm_sequence #(hexk_valid_ready_item #(DATA_WIDTH));

   // The words to send, the first one first; set by the starter.
   logic    [DATA_WIDTH-1:0] words        [$];

   // The delay of every item in clock cycles; below 0 the driver takes the delays of the cfg.
   rand int                  delay_cycles;

   `uvm_object_param_utils(hexk_valid_ready_data_seq#(DATA_WIDTH))

   // What a plain randomize() gives; a test overrides it.
   constraint default_values_cstr {soft delay_cycles == -1;}

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_valid_ready_data_seq";
   endfunction : get_type_name

   // Creates the sequence without words.
   function new(string name = "hexk_valid_ready_data_seq");
      super.new(name);
      delay_cycles = -1;
   endfunction : new

   // Sends one item per word; returns at the transfer of the last one.
   task body();
      // The class the factory gives for "<sequencer path>.req", asked once, the way create() asks it, and every item
      // is made of that class: an override set while the sequence runs counts from its next start.
      // get_object_type() would not do: a derived class without macros of its own gives the type of its base class
      // there.
      uvm_factory        factory = uvm_factory::get();
      uvm_object_wrapper plain = hexk_valid_ready_item#(DATA_WIDTH)::get_type();
      uvm_object_wrapper item_type = factory.find_override_by_type(plain, {get_sequencer().get_full_name(), ".req"});
      bit                derived = item_type != plain;
      uvm_object         made;
      foreach (words[i]) begin
         made = item_type.create_object("req");
         `hexk_cast_or_fatal(req, made, "HEXK_VALID_READY_RAND")
         start_item(req);
         // SEQ-2 waived: a plain item is not randomized, since every random field of it is assigned below and a
         // randomization costs several times the rest of the item.
         if (derived) begin
            `hexk_randomize_or_fatal(req, "HEXK_VALID_READY_RAND")
         end
         req.data         = words[i];
         req.delay_cycles = delay_cycles;
         finish_item(req);
      end
   endtask : body

endclass : hexk_valid_ready_data_seq

`endif  // HEXK_VALID_READY_DATA_SEQ_SV
