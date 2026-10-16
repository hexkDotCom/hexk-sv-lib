// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_control_vseq.sv
//
// The control of the DUT, in four steps, each a packet that is collected as usual:
// - CTRL.EN gates the input: a word offered with EN 0 is not taken, until EN is set;
// - STATUS.BUSY is 1 while a packet is half received and 0 when all is done;
// - LEN counts as it is at each word: lowered from 4 to 3 after two words, the third word ends
//   the packet;
// - DONE comes at the edge after the last commit of a packet (irq is low at the edge after the
//   commit and high at the next one, with IRQ_EN set); IRQ_EN masks irq without touching DONE; and
//   only a write of 1 to IRQ.DONE with its byte enabled clears DONE: a write of 0, and a write of
//   1 with byte 0 disabled, leave it set.
// The edges are counted on the clocking block of the bus monitor (env.cfg.bus_cfg.vif.mon_cb).
// SEQ-13 waived: these are checks of the DUT's timing to the clock edge, which the sequence makes
// at the edges it counts; the rest of the testbench leaves timing to the monitors.

`ifndef HEXK_REF_CONTROL_VSEQ_SV
`define HEXK_REF_CONTROL_VSEQ_SV

class hexk_ref_control_vseq extends hexk_ref_vseq_base;

   // Edges that a word waits while CTRL.EN is 0, to show that it is not taken.
   localparam int unsigned GATE_EDGES = 20;

   `uvm_object_utils(hexk_ref_control_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_control_vseq");
      super.new(name);
   endfunction : new

   // The four steps.
   task body();
      check_enable_gate(6'd8);
      check_busy(6'd16);
      check_len_change(6'd32);
      check_done_and_irq(6'd24);
   endtask : body

   // A word offered with CTRL.EN 0 waits, untaken, until EN is set; then it is taken as a one-word packet. The
   // input agent offers it within its largest delay, well inside GATE_EDGES.
   task check_enable_gate(bit [5:0] base);
      bit          [31:0] words                                  [$];
      int unsigned        words_before = env.predictor.num_words;
      int unsigned        offered = 0;
      env.csr.write(env.regs.base, base, this);
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(0, 1, use_irq), this);
      random_words(1, words);
      fork
         send_words(words);
      join_none
      repeat (GATE_EDGES) begin
         @(env.cfg.in_cfg.vif.mon_cb);
         offered += (env.cfg.in_cfg.vif.mon_cb.valid === 1'b1);
      end
      `hexk_check_ne(offered, 0, "REF_CTRL_EN", "edges at which a word was offered while CTRL.EN is 0")
      `hexk_check_eq(env.predictor.num_words, words_before, "REF_CTRL_EN", "words taken while CTRL.EN is 0")
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 1, use_irq), this);
      wait fork;
      env.packets_sent++;
      finish(1, base);
   endtask : check_enable_gate

   // STATUS.BUSY is 1 with two of four words received, and 0 when the packet is done.
   task check_busy(bit [5:0] base);
      bit [31:0] words[$];
      program_packet(4, 0, base);
      random_words(2, words);
      send_words(words);
      env.csr.read_field_check(env.regs.status_busy, 1, "REF_STATUS_BUSY", this);
      words.delete();
      random_words(2, words);
      send_words(words);
      env.packets_sent++;
      finish(4, base);
      env.csr.read_field_check(env.regs.status_busy, 0, "REF_STATUS_BUSY", this);
   endtask : check_busy

   // LEN lowered from 4 to 3 after two words: the third word ends the packet.
   task check_len_change(bit [5:0] base);
      bit [31:0] words[$];
      program_packet(4, 0, base);
      random_words(2, words);
      send_words(words);
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 3, use_irq), this);
      words.delete();
      random_words(1, words);
      send_words(words);
      env.packets_sent++;
      finish(3, base);
   endtask : check_len_change

   // The timing of DONE, the mask of IRQ_EN, and the write-1-to-clear of IRQ.DONE, with one one-word packet.
   task check_done_and_irq(bit [5:0] base);
      bit [31:0] words[$];
      env.csr.write(env.regs.base, base, this);
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 1, 1), this);
      random_words(1, words);
      fork
         send_words(words);
      join_none
      // The edge of the commit, then DONE at the next edge: seen on irq one edge later still.
      do begin
         @(env.cfg.bus_cfg.vif.mon_cb);
      end while (env.cfg.bus_cfg.vif.mon_cb.commit !== 1'b1);
      expect_irq(0, "at the edge after the last commit");
      expect_irq(1, "two edges after the last commit");
      wait fork;
      env.packets_sent++;
      // IRQ_EN masks irq; DONE stays.
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 1, 0), this);
      expect_irq(0, "with IRQ_EN 0 and DONE set");
      env.csr.read_check(env.regs.irq, 1, "REF_IRQ_MASK", '1, this);
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 1, 1), this);
      expect_irq(1, "with IRQ_EN 1 and DONE set");
      // Only a 1 in an enabled byte clears DONE.
      env.csr.write(env.regs.irq, 0, this);
      env.csr.read_check(env.regs.irq, 1, "REF_IRQ_W1C", '1, this);
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, hexk_ref_regs::IRQ_OFFSET, 1, 4'b0000);
      env.csr.read_check(env.regs.irq, 1, "REF_IRQ_W1C", '1, this);
      finish(1, base);
      expect_irq(0, "after DONE was acknowledged");
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 1, use_irq), this);
   endtask : check_done_and_irq

   // At the next edge, irq is value.
   task expect_irq(bit value, string when);
      @(env.cfg.bus_cfg.vif.mon_cb);
      `hexk_check_eq(env.cfg.bus_cfg.vif.mon_cb.irq, value, "REF_IRQ", {"irq ", when})
   endtask : expect_irq

   // The packet of len words at base is done: its result is collected and DONE acknowledged.
   task finish(int unsigned len, bit [5:0] base);
      bit seen;
      wait_done(seen);
      if (seen) begin
         collect(len, base);
         acknowledge_done();
      end
   endtask : finish

endclass : hexk_ref_control_vseq

`endif  // HEXK_REF_CONTROL_VSEQ_SV
