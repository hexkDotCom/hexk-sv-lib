// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_vseq_base.sv
//
// Base of the virtual sequences of the reference testbench. They run on no sequencer of their own
// (start(null)): the starter assigns env, and through it the sequences reach the sequencer of the
// input agent, the register utility (env.csr), the register model and the interrupt line. Here are
// the steps of a packet that every sequence uses: program BASE and CTRL, send words, wait for DONE
// (the interrupt or a spin-wait on IRQ.DONE, within env.cfg.done_timeout_ps), collect the result
// through the registers for the result scoreboard, acknowledge DONE. A sequence acknowledges the
// DONE of its own packets, so the next one starts with DONE clear. The sequences count what they
// send in the environment (packets_sent, words_sent), which the tests compare with what the
// scoreboards matched. The starter also gives the mode of the knob ref_mode, which says which
// packets of random traffic are scrambled (scramble_of()).

`ifndef HEXK_REF_VSEQ_BASE_SV
`define HEXK_REF_VSEQ_BASE_SV

// How the packets of random traffic are sent: all plain, all scrambled, or each one either way.
typedef enum bit [1:0] {
   HEXK_REF_PLAIN,
   HEXK_REF_SCRAMBLE,
   HEXK_REF_MIXED
} hexk_ref_mode_e;

class hexk_ref_vseq_base extends uvm_sequence;

   // The environment; assigned by the starter.
   // SEQ-5 waived: the sequences reach the sequencers of the agents through the environment, not through members of
   // their own: one handle gives every scenario the sequencers, the register utility, the register model and the
   // checks of the environment.
   // REG-6 waived: the register model is env.regs, through the same handle.
   hexk_ref_env    env;

   // 1: wait for DONE through the interrupt; 0: poll IRQ.DONE with interrupts off.
   bit             use_irq           = 1;

   // Which packets of random traffic are scrambled.
   hexk_ref_mode_e mode              = HEXK_REF_MIXED;

   // The result that collect() read last, as it went to the result scoreboard; null before.
   hexk_ref_result collected_result;

   `uvm_object_utils(hexk_ref_vseq_base)

   // Creates the sequence.
   function new(string name = "hexk_ref_vseq_base");
      super.new(name);
   endfunction : new

   // UVM callback: a sequence that is started without its environment cannot do anything.
   task pre_start();
      if (env == null) begin
         `uvm_fatal("REF_VSEQ_ENV", "env is null; the starter assigns it before start()")
      end
   endtask : pre_start

   // Whether packet i of random traffic is scrambled in the mode of the starter.
   function bit scramble_of(int unsigned i);
      case (mode)
         HEXK_REF_PLAIN:    return 0;
         HEXK_REF_SCRAMBLE: return 1;
         default:           return i[0];
      endcase
   endfunction : scramble_of

   // Programs BASE and CTRL for packets of len words; enables the DUT.
   task program_packet(int unsigned len, bit scramble, bit [5:0] base);
      env.csr.write(env.regs.base, base, this);
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, len, use_irq, scramble), this);
   endtask : program_packet

   // count random words.
   function void random_words(int unsigned count, ref bit [31:0] words[$]);
      bit [31:0] word;
      for (int unsigned i = 0; i < count; i++) begin
         `hexk_std_randomize_or_fatal(word, "REF_RAND")
         words.push_back(word);
      end
   endfunction : random_words

   // Sends words as one stream, through the input agent; CTRL.LEN cuts them into packets.
   task send_words(const ref bit [31:0] words[$]);
      hexk_valid_ready_data_seq #(32) seq = hexk_valid_ready_data_seq#(32)::type_id::create("seq");
      `hexk_randomize_or_fatal(seq, "REF_RAND")
      foreach (words[i]) begin
         seq.words.push_back(words[i]);
      end
      seq.start(env.in_agent.sqr, this);
      env.words_sent += words.size();
   endtask : send_words

   // Waits for DONE, at most env.cfg.done_timeout_ps: for the interrupt, or by polling IRQ.DONE.
   // SEQ-13 waived: waiting for the interrupt line is what a test of an interrupt does; a monitor of the line would
   // only pass the same level on.
   // CHK-7 waived: the scenario waits for the interrupt of its own packet, in line; nothing is interrupted, so no
   // handler component and no lock are needed.
   task wait_done(output bit seen);
      if (use_irq) begin
         `hexk_wait_timeout(env.cfg.bus_cfg.vif.irq === 1'b1, env.cfg.done_timeout_ps * 1ps, "REF_DONE")
         seen = env.cfg.bus_cfg.vif.irq === 1'b1;
      end else begin
         env.csr.spinwait(env.regs.irq, 1, 1, "REF_DONE", seen, this);
      end
   endtask : wait_done

   // Acknowledges DONE and checks that it cleared.
   task acknowledge_done();
      env.csr.write(env.regs.irq, 1, this);
      env.csr.read_check(env.regs.irq, 0, "REF_DONE_CLEAR", '1, this);
   endtask : acknowledge_done

   // Waits until every word sent is accepted and committed, at most env.cfg.done_timeout_ps.
   task wait_drained();
      bit idle;
      env.drained.wait_idle(env.cfg.done_timeout_ps, "REF_DRAINED", idle);
   endtask : wait_drained

   // Reads the result of the packet that just completed and gives it to the result scoreboard.
   task collect(int unsigned len, bit [5:0] base);
      hexk_ref_result actual = hexk_ref_result::type_id::create("actual");
      uvm_reg_data_t  value;
      env.csr.read(env.regs.status, value, this);
      actual.number = value[15:8];
      env.csr.read(env.regs.crc, value, this);
      actual.crc = 32'(value);
      env.csr.read(env.regs.cycles, value, this);
      actual.cycles = 16'(value);
      for (int unsigned i = 0; i < len; i++) begin
         env.csr.read(env.regs.mem_reg(base + i), value, this);
         actual.words.push_back(32'(value));
      end
      collected_result = actual;
      env.result_sb.actual_export.write(hexk_ref_meta_result_t::wrap(actual, "collector"));
      if (env.watchdog != null) begin
         env.watchdog.heartbeat("collector");
      end
   endtask : collect

endclass : hexk_ref_vseq_base

`endif  // HEXK_REF_VSEQ_BASE_SV
