// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_random_seq.sv
//
// Sequence that sends num_items transfers of random data.
// Start it on the sequencer of an initiator hexk_valid_ready_agent; it ends at the transfer
// of the last word. The delays come from the cfg of the agent. On a responder it stands for
// num_items transfers to accept, whose words it does not keep. A plain randomize() gives
// one item.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_VALID_READY_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_RANDOM_SEQ_SV
`define HEXK_VALID_READY_RANDOM_SEQ_SV

class hexk_valid_ready_random_seq #(
    int DATA_WIDTH = 32
) extends uvm_sequence #(hexk_valid_ready_item #(DATA_WIDTH));

   // Number of transfers.
   rand int unsigned num_items = 1;

   `uvm_object_param_utils(hexk_valid_ready_random_seq#(DATA_WIDTH))

   // What a plain randomize() gives; a test overrides it.
   constraint default_values_cstr {soft num_items == 1;}

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_valid_ready_random_seq";
   endfunction : get_type_name

   // Creates the sequence.
   function new(string name = "hexk_valid_ready_random_seq");
      super.new(name);
   endfunction : new

   // Sends num_items items with random words; returns at the transfer of the last one.
   task body();
      repeat (num_items) begin
         // Under the name of the sequencer, so that a factory override of one agent's items can name its path.
         req = hexk_valid_ready_item#(DATA_WIDTH)::type_id::create("req", null, get_sequencer().get_full_name());
         start_item(req);
         `hexk_randomize_or_fatal(req, "HEXK_VALID_READY_RAND")
         finish_item(req);
      end
   endtask : body

endclass : hexk_valid_ready_random_seq

`endif  // HEXK_VALID_READY_RANDOM_SEQ_SV
