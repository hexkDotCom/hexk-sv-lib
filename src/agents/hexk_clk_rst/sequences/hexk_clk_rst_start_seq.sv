// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_start_seq.sv
//
// Sequence that starts a clock that is stopped.
// Start it on the sequencer of a hexk_clk_rst_agent, after hexk_clk_rst_stop_seq or when the
// cfg has start_clock 0. It ends at the first rising edge, which comes one low time of the
// period after the start; on a clock that runs it ends at once.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_CLK_RST_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_START_SEQ_SV
`define HEXK_CLK_RST_START_SEQ_SV

class hexk_clk_rst_start_seq extends uvm_sequence #(hexk_clk_rst_item);

   `uvm_object_utils(hexk_clk_rst_start_seq)

   // Creates the sequence.
   function new(string name = "hexk_clk_rst_start_seq");
      super.new(name);
   endfunction : new

   // Sends one start item; returns at the first rising edge of the clock.
   task body();
      // Under the name of the sequencer, so that a factory override of one agent's items can name its path.
      req = hexk_clk_rst_item::type_id::create("req", null, get_sequencer().get_full_name());
      start_item(req);
      `hexk_randomize_with_or_fatal(req, "HEXK_CLK_RST_RAND", op == HEXK_CLK_RST_START;)
      finish_item(req);
   endtask : body

endclass : hexk_clk_rst_start_seq

`endif  // HEXK_CLK_RST_START_SEQ_SV
