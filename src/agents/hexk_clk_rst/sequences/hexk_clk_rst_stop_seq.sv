// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_stop_seq.sv
//
// Sequence that stops the clock, for a time or until hexk_clk_rst_start_seq.
// Start it on the sequencer of a hexk_clk_rst_agent. The clock finishes the high time that
// is going on and then stays 0. With stop_ps above 0 the sequence starts the clock again
// after that time and ends at its first rising edge; with 0, the default, it ends when the
// clock is 0.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_CLK_RST_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_STOP_SEQ_SV
`define HEXK_CLK_RST_STOP_SEQ_SV

class hexk_clk_rst_stop_seq extends uvm_sequence #(hexk_clk_rst_item);

   // Time in picoseconds after which the clock starts again; 0 leaves it stopped.
   rand longint unsigned stop_ps;

   // What a plain randomize() gives; a test overrides what it wants different.
   constraint default_values_cstr {soft stop_ps == 0;}

   `uvm_object_utils(hexk_clk_rst_stop_seq)

   // Creates the sequence.
   function new(string name = "hexk_clk_rst_stop_seq");
      super.new(name);
   endfunction : new

   // Sends one stop item; returns when the clock is 0, or runs again after stop_ps.
   task body();
      req = hexk_clk_rst_item::type_id::create("req");
      start_item(req);
      `hexk_randomize_with_or_fatal(req, "HEXK_CLK_RST_RAND", op == HEXK_CLK_RST_STOP;)
      req.hold_ps = stop_ps;
      finish_item(req);
   endtask : body

endclass : hexk_clk_rst_stop_seq

`endif  // HEXK_CLK_RST_STOP_SEQ_SV
