// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_reset_seq.sv
//
// Sequence that resets the DUT: asserts the reset, holds it and releases it.
// Start it on the sequencer of a hexk_clk_rst_agent, usually from the reset phase of the
// test; it ends when the reset is released. The members say how long and how: a plain
// randomize() gives 5 clock cycles, asserted at once and released at a rising edge, so the
// DUT sees the reset at exactly 5 rising edges. hold_cycles needs a running clock.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_CLK_RST_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_RESET_SEQ_SV
`define HEXK_CLK_RST_RESET_SEQ_SV

class hexk_clk_rst_reset_seq extends uvm_sequence #(hexk_clk_rst_item);

   // Rising edges of the clock for which the reset is held.
   rand int unsigned     hold_cycles;

   // Time in picoseconds for which the reset is held after the edges.
   rand longint unsigned hold_ps;

   // 1: asserted at the next rising edge of the clock; 0: asserted at once.
   rand bit              sync_assert;

   // 1: released at a rising edge of the clock; 0: released when the hold is over.
   rand bit              sync_release;

   // What a plain randomize() gives; a test overrides what it wants different.
   constraint default_values_cstr {
      soft hold_cycles == 5;
      soft hold_ps == 0;
      soft sync_assert == 0;
      soft sync_release == 1;
   }

   `uvm_object_utils(hexk_clk_rst_reset_seq)

   // Creates the sequence.
   function new(string name = "hexk_clk_rst_reset_seq");
      super.new(name);
   endfunction : new

   // Sends one reset item; returns when the reset is released.
   task body();
      req = hexk_clk_rst_item::type_id::create("req");
      start_item(req);
      `hexk_randomize_with_or_fatal(req, "HEXK_CLK_RST_RAND", op == HEXK_CLK_RST_RESET;)
      req.hold_cycles  = hold_cycles;
      req.hold_ps      = hold_ps;
      req.sync_assert  = sync_assert;
      req.sync_release = sync_release;
      finish_item(req);
   endtask : body

endclass : hexk_clk_rst_reset_seq

`endif  // HEXK_CLK_RST_RESET_SEQ_SV
