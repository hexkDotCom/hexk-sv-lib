// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_release_seq.sv
//
// Sequence that releases the reset that hexk_clk_rst_assert_seq asserted.
// Start it on the sequencer of a hexk_clk_rst_agent. With sync_release, the default, the
// reset is released at the next rising edge of the clock, otherwise at once; the sequence
// ends when the reset is released.
//
//! @module    hexk_clk_rst
//! @since     0.9.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_CLK_RST_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_RELEASE_SEQ_SV
`define HEXK_CLK_RST_RELEASE_SEQ_SV

class hexk_clk_rst_release_seq extends uvm_sequence #(hexk_clk_rst_item);

   // 1: the reset is released at the next rising edge of the clock; 0: at once.
   rand bit sync_release = 1;

   `uvm_object_utils(hexk_clk_rst_release_seq)

   // What a plain randomize() gives; a test overrides what it wants different.
   constraint default_values_cstr {soft sync_release == 1;}

   // Creates the sequence.
   function new(string name = "hexk_clk_rst_release_seq");
      super.new(name);
   endfunction : new

   // Sends one release item; returns when the reset is released.
   task body();
      // Under the name of the sequencer, so that a factory override of one agent's items can name its path.
      req = hexk_clk_rst_item::type_id::create("req", null, get_sequencer().get_full_name());
      start_item(req);
      `hexk_randomize_with_or_fatal(req, "HEXK_CLK_RST_RAND", op == HEXK_CLK_RST_RELEASE;)
      req.sync_release = sync_release;
      finish_item(req);
   endtask : body

endclass : hexk_clk_rst_release_seq

`endif  // HEXK_CLK_RST_RELEASE_SEQ_SV
