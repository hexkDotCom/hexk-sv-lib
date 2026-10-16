// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_warm_reset_vseq.sv
//
// A warm reset in the middle of the traffic, the way a power-management flow does it: when
// nothing is in flight, the reset is asserted and left asserted, the clock is stopped, given a new
// period with jitter (NEW_PERIOD_PS, NEW_JITTER_PS) and started again, and only then is the reset
// released at a rising edge. The DUT starts over (registers at their reset values, packet count 0)
// and keeps its RAM; the predictor and the scoreboards forget what was in flight; the register
// model is reset. Right after the reset, every register is at its reset value (the volatile ones
// too: the DUT is quiet, so the reset check of hexk_csr_util includes them) and every word that the
// packets before it wrote still holds its data. Before the warm reset, everything that it must
// clear is made to differ from its reset value, and checked to: ERR has counted a corrected and an
// uncorrectable read, DONE is set, and DEBUG, INJ_* and RAW_ADDR are programmed; so the reads after
// the reset show the reset, not a state that never changed.
// Then a reset of another kind: asserted at once, between two edges, while a packet is half
// received and its first words are still in the pipeline (three of eight, none committed yet). The
// DUT drops them and the partial packet and keeps its RAM, so the words that an earlier packet
// wrote at the same place read as before, no commit comes after the reset, and the next packet is a
// whole new one. Without a throttle of ready the words come at consecutive edges and none is
// committed; with one, the first may be. Three random packets come before, between and after the
// resets. Afterwards old_period_ps is the period before the warm reset, and dropped_words the
// number of cut words whose commit never came.

`ifndef HEXK_REF_WARM_RESET_VSEQ_SV
`define HEXK_REF_WARM_RESET_VSEQ_SV

class hexk_ref_warm_reset_vseq extends hexk_ref_scenario_vseq;

   // The clock after the reset: 6 ns with 200 ps of jitter.
   localparam longint unsigned NEW_PERIOD_PS = 6_000;
   localparam longint unsigned NEW_JITTER_PS = 200;

   // Where the packet that a reset cuts goes, and how many of its words the DUT takes before the reset.
   localparam bit [5:0] CUT_BASE = 6'd40;
   localparam int unsigned CUT_WORDS = 3;

   // Words at which leave_state_set() puts its errors.
   localparam bit [5:0] ERROR_WORD = 6'd60;

   // After the sequence: the period of the clock before the warm reset, and the words that a reset dropped from
   // the pipeline, whose commits never come.
   longint unsigned old_period_ps;
   int unsigned     dropped_words;

   `uvm_object_utils(hexk_ref_warm_reset_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_warm_reset_vseq");
      super.new(name);
   endfunction : new

   // Packets, the warm reset, the reset values, packets, the reset in a packet, the reset values, packets.
   task body();
      send_packets(3);
      leave_state_set();
      wait_quiet();
      // A reset clears ERR and the counts of the predictor: compare them before.
      env.check_error_counters(this);
      old_period_ps = env.clk_rst_agent.status.period_ps;
      warm_reset();
      check_after_reset();
      send_packets(3);
      reset_in_packet();
      check_after_reset();
      send_packets(3);
   endtask : body

   // count random packets.
   task send_packets(int unsigned count);
      for (int unsigned i = 0; i < count; i++) begin
         send_random_packet(i);
      end
   endtask : send_packets

   // A packet of eight words at CUT_BASE, then another one there that a reset cuts after CUT_WORDS words, between two
   // edges, before any of them is committed. The input runs without delays meanwhile, so that the words follow
   // each other at consecutive edges.
   task reset_in_packet();
      hexk_valid_ready_data_seq #(32) cut_seq = hexk_valid_ready_data_seq#(32)::type_id::create("cut_seq");
      hexk_clk_rst_assert_seq assert_seq = hexk_clk_rst_assert_seq::type_id::create("assert_seq");
      hexk_clk_rst_release_seq release_seq = hexk_clk_rst_release_seq::type_id::create("release_seq");
      hexk_delay_mode_e delay_mode = env.cfg.in_cfg.delay_cfg.mode;
      int unsigned words_before;
      int unsigned commits_before;
      int unsigned cut_committed;
      hexk_sb_stats stats;
      bit [31:0] word;
      send_packet(8, 0, CUT_BASE);
      env.check_error_counters(this);
      `hexk_randomize_or_fatal(cut_seq, "REF_RAND")
      `hexk_randomize_or_fatal(assert_seq, "REF_RAND")
      `hexk_randomize_or_fatal(release_seq, "REF_RAND")
      env.cfg.in_cfg.delay_cfg.mode = HEXK_DELAY_NONE;
      env.csr.write(env.regs.base, CUT_BASE, this);
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 8, use_irq), this);
      for (int unsigned i = 0; i < CUT_WORDS; i++) begin
         `hexk_std_randomize_or_fatal(word, "REF_RAND")
         cut_seq.words.push_back(word);
      end
      words_before   = env.predictor.num_words;
      stats          = env.commit_sb.get_stats();
      commits_before = stats.matched;
      fork
         cut_seq.start(env.in_agent.sqr, this);
      join_none
      // The last of the words is taken at an edge; a third of a period later, the reset.
      wait (env.predictor.num_words == words_before + CUT_WORDS);
      hexk_wait_util::wait_ps(env.clk_rst_agent.status.period_ps / 3);
      assert_seq.sync_assert = 0;
      assert_seq.start(env.clk_rst_agent.sqr, this);
      release_seq.start(env.clk_rst_agent.sqr, this);
      wait fork;
      // The last of the words came a third of a period before the reset: at least that one never reaches the RAM.
      stats         = env.commit_sb.get_stats();
      cut_committed = stats.matched - commits_before;
      `hexk_check(cut_committed < CUT_WORDS, "REF_RESET_CUT", "the reset came after every cut word was committed")
      env.words_sent += CUT_WORDS;
      dropped_words += CUT_WORDS - cut_committed;
      env.cfg.in_cfg.delay_cfg.mode = delay_mode;
   endtask : reset_in_packet

   // Sets what a reset must clear: a corrected and an uncorrectable read in ERR, DONE of a one-word packet that is not
   // acknowledged (its result is not collected: the reset empties the result scoreboard), DEBUG.CORRUPT_READ,
   // INJ_LO, INJ_HI, INJ_CTRL.ARM and RAW_ADDR; and checks each of them.
   task leave_state_set();
      hexk_valid_ready_data_seq #(32) unacked_seq = hexk_valid_ready_data_seq#(32)::type_id::create("unacked_seq");
      uvm_reg_data_t                  value;
      bit                             seen;
      send_packet(2, 0, ERROR_WORD);
      flip_code_bits(ERROR_WORD, 39'h00_0000_0020);
      flip_code_bits(ERROR_WORD + 1, 39'h00_0000_0060);
      env.csr.read(env.regs.mem_reg(ERROR_WORD), value, this);
      env.csr.read(env.regs.mem_reg(ERROR_WORD + 1), value, this);
      env.csr.read(env.regs.err, value, this);
      `hexk_check(value[7:0] != 0 && value[15:8] != 0, "REF_RESET_BEFORE", "ERR counts errors before the reset")
      // A packet whose DONE stays set.
      env.csr.write(env.regs.ctrl, hexk_ref_regs::ctrl_value(1, 1, use_irq), this);
      `hexk_randomize_or_fatal(unacked_seq, "REF_RAND")
      unacked_seq.words.push_back(32'h0BAD_D0E5);
      unacked_seq.start(env.in_agent.sqr, this);
      env.words_sent++;
      env.csr.spinwait(env.regs.irq, 1, 1, "REF_RESET_BEFORE", seen, this);
      // The debug and injection registers away from their reset values; nothing reads or commits after this.
      env.csr.write(env.regs.debug, 1 << env.regs.debug_corrupt_read.get_lsb_pos(), this);
      env.csr.write(env.regs.inj_lo, 32'hDEAD_BEEF, this);
      env.csr.write(env.regs.inj_hi, 7'h55, this);
      env.csr.write(env.regs.inj_ctrl, 1, this);
      env.csr.write(env.regs.raw_addr, 6'd33, this);
      env.csr.read_check(env.regs.debug, 1, "REF_RESET_BEFORE", '1, this);
      env.csr.read_check(env.regs.inj_ctrl, 1, "REF_RESET_BEFORE", '1, this);
      env.csr.read_check(env.regs.raw_addr, 33, "REF_RESET_BEFORE", '1, this);
   endtask : leave_state_set

   // Assert, stop the clock, new clock, start, release at an edge.
   task warm_reset();
      hexk_clk_rst_assert_seq  assert_seq = hexk_clk_rst_assert_seq::type_id::create("assert_seq");
      hexk_clk_rst_stop_seq    stop_seq = hexk_clk_rst_stop_seq::type_id::create("stop_seq");
      hexk_clk_rst_clock_seq   clock_seq = hexk_clk_rst_clock_seq::type_id::create("clock_seq");
      hexk_clk_rst_start_seq   start_seq = hexk_clk_rst_start_seq::type_id::create("start_seq");
      hexk_clk_rst_release_seq release_seq = hexk_clk_rst_release_seq::type_id::create("release_seq");
      `hexk_randomize_or_fatal(assert_seq, "REF_RAND")
      `hexk_randomize_or_fatal(stop_seq, "REF_RAND")
      `hexk_randomize_or_fatal(clock_seq, "REF_RAND")
      `hexk_randomize_or_fatal(start_seq, "REF_RAND")
      `hexk_randomize_or_fatal(release_seq, "REF_RAND")
      assert_seq.sync_assert = 1;
      assert_seq.start(env.clk_rst_agent.sqr, this);
      stop_seq.start(env.clk_rst_agent.sqr, this);
      clock_seq.period_ps = NEW_PERIOD_PS;
      clock_seq.jitter_ps = NEW_JITTER_PS;
      clock_seq.start(env.clk_rst_agent.sqr, this);
      start_seq.start(env.clk_rst_agent.sqr, this);
      release_seq.start(env.clk_rst_agent.sqr, this);
   endtask : warm_reset

   // Every register at its reset value, and the RAM as it was.
   task check_after_reset();
      // With the volatile fields: the DUT is quiet, so what it counts must have started again.
      env.csr.check_reset_values(env.regs, 1, this);
      // The reset keeps the RAM: every word written before it reads back as written.
      for (int unsigned word = 0; word < hexk_ref_regs::MEM_WORDS; word++) begin
         if (env.predictor.is_known(word)) begin
            env.csr.read_check(env.regs.mem_reg(word), env.predictor.expected_word(word), "REF_RAM_KEPT", '1, this);
         end
      end
   endtask : check_after_reset

endclass : hexk_ref_warm_reset_vseq

`endif  // HEXK_REF_WARM_RESET_VSEQ_SV
