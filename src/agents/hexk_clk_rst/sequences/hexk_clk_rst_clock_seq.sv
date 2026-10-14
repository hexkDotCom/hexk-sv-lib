// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_clock_seq.sv
//
// Sequence that gives the clock a new period, duty cycle and jitter.
// Start it on the sequencer of a hexk_clk_rst_agent; it ends at the rising edge from which
// the new clock holds, at once when the clock is stopped. All three values are applied: a
// plain randomize() gives 100 MHz, half of the period high and no jitter, so a test
// constrains period_ps and repeats a duty cycle or a jitter it wants to keep.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    SEQ-2 SEQ-7 SEQ-9
//! @emits     HEXK_CLK_RST_RAND:fatal
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_CLOCK_SEQ_SV
`define HEXK_CLK_RST_CLOCK_SEQ_SV

class hexk_clk_rst_clock_seq extends uvm_sequence #(hexk_clk_rst_item);

   // Period of the clock in picoseconds.
   rand longint unsigned period_ps;

   // Share of the period in which the clock is high, 1 to 99.
   rand int unsigned     duty_percent;

   // Largest distance of a rising edge from its ideal time, in picoseconds.
   rand longint unsigned jitter_ps;

   // What a plain randomize() gives; a test overrides what it wants different.
   constraint default_values_cstr {
      soft period_ps == hexk_clk_rst_agent_cfg::DEFAULT_PERIOD_PS;
      soft duty_percent == hexk_clk_rst_agent_cfg::DEFAULT_DUTY_PERCENT;
      soft jitter_ps == 0;
   }

   `uvm_object_utils(hexk_clk_rst_clock_seq)

   // Creates the sequence.
   function new(string name = "hexk_clk_rst_clock_seq");
      super.new(name);
   endfunction : new

   // Sends one clock item; returns at the rising edge from which the new clock holds.
   task body();
      req = hexk_clk_rst_item::type_id::create("req");
      start_item(req);
      `hexk_randomize_with_or_fatal(req, "HEXK_CLK_RST_RAND", op == HEXK_CLK_RST_CLOCK;)
      req.period_ps    = period_ps;
      req.duty_percent = duty_percent;
      req.jitter_ps    = jitter_ps;
      finish_item(req);
   endtask : body

endclass : hexk_clk_rst_clock_seq

`endif  // HEXK_CLK_RST_CLOCK_SEQ_SV
