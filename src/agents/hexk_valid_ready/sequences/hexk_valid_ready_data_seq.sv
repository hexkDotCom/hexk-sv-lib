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

   // What a plain randomize() gives; a test overrides it.
   constraint default_values_cstr {soft delay_cycles == -1;}

   `uvm_object_param_utils(hexk_valid_ready_data_seq#(DATA_WIDTH))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   virtual function string get_type_name();
      return "hexk_valid_ready_data_seq";
   endfunction : get_type_name

   // Creates the sequence without words.
   function new(string name = "hexk_valid_ready_data_seq");
      super.new(name);
      delay_cycles = -1;
   endfunction : new

   // Sends one item per word; returns at the transfer of the last one.
   task body();
      foreach (words[i]) begin
         req = hexk_valid_ready_item#(DATA_WIDTH)::type_id::create("req");
         start_item(req);
         `hexk_randomize_or_fatal(req, "HEXK_VALID_READY_RAND")
         req.data         = words[i];
         req.delay_cycles = delay_cycles;
         finish_item(req);
      end
   endtask : body

endclass : hexk_valid_ready_data_seq

`endif  // HEXK_VALID_READY_DATA_SEQ_SV
