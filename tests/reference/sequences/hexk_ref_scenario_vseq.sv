// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_scenario_vseq.sv
//
// Base of the virtual sequences that the tests start: a scenario of packets and register accesses.
// It adds to hexk_ref_vseq_base the steps that scenarios share: a whole packet with
// hexk_ref_packet_vseq, random within the lengths of the cfg or directed; a wait until nothing is
// in flight; an error injected into the RAM by HDL access; and a check of the code word that the
// RAM holds. A scenario checks itself what the scoreboards do not see, with read checks of the
// registers; the test that starts it configures the environment and says how the run must end.

`ifndef HEXK_REF_SCENARIO_VSEQ_SV
`define HEXK_REF_SCENARIO_VSEQ_SV

class hexk_ref_scenario_vseq extends hexk_ref_vseq_base;

   // The sequence of the last packet that send_random_packet() or send_packet() sent.
   hexk_ref_packet_vseq last_packet;

   `uvm_object_utils(hexk_ref_scenario_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_scenario_vseq");
      super.new(name);
   endfunction : new

   // Starts a virtual sequence below this one, with the environment and the settings of this one.
   task start_child(hexk_ref_vseq_base seq);
      seq.env     = env;
      seq.use_irq = use_irq;
      seq.mode    = mode;
      seq.start(null, this);
   endtask : start_child

   // Packet number i of random traffic: randomized within the constraints of hexk_ref_packet_vseq, with a length
   // between the limits of the cfg and scrambled as the mode says.
   task send_random_packet(int unsigned i);
      hexk_ref_packet_vseq packet_seq = hexk_ref_packet_vseq::type_id::create("packet_seq");
      int unsigned         shortest = env.cfg.min_len;
      int unsigned         longest = env.cfg.max_len;
      bit                  scrambled = scramble_of(i);
      `hexk_randomize_with_or_fatal(packet_seq, "REF_RAND",
                                    len inside {[local::shortest : local::longest]}; scramble == local::scrambled;)
      start_child(packet_seq);
      last_packet = packet_seq;
   endtask : send_random_packet

   // One packet of len random words at a given place; for directed traffic.
   task send_packet(int unsigned len, bit scramble, bit [5:0] base);
      hexk_ref_packet_vseq packet_seq = hexk_ref_packet_vseq::type_id::create("packet_seq");
      `hexk_randomize_or_fatal(packet_seq, "REF_RAND")
      packet_seq.len      = len;
      packet_seq.scramble = scramble;
      packet_seq.base     = base;
      start_child(packet_seq);
      last_packet = packet_seq;
   endtask : send_packet

   // Waits until no register access, no word and no packet is in flight, for a reset that loses nothing; at most
   // env.cfg.done_timeout_ps.
   task wait_quiet();
      bit idle;
      env.quiet.wait_idle(env.cfg.done_timeout_ps, "REF_QUIET", idle);
   endtask : wait_quiet

   // Flips the bits of mask in the code word that the RAM holds at word, by HDL access, as a fault-injection test
   // does, and tells the predictor; first checks that the RAM holds the code word the predictor expects. Needs read
   // and write access to the signals of the DUT, which make reference gives (Questa and VCS).
   task flip_code_bits(bit [5:0] word, bit [38:0] mask);
      string         path = $sformatf("hexk_ref_tb.dut.ram[%0d]", word);
      uvm_hdl_data_t code;
      `hexk_hdl_check_path_or_fatal(path, "REF_HDL_PATH")
      `hexk_hdl_read(path, code, "REF_HDL_READ")
      `hexk_check_eq(39'(code), env.predictor.expected_code(word), "REF_HDL_CODE",
                     $sformatf("code word of RAM word %0d at %s, before flipping 39'h%010h", word, path, mask))
      `hexk_hdl_deposit(path, 39'(code) ^ mask, "REF_HDL_DEPOSIT")
      env.predictor.inject(word, mask);
   endtask : flip_code_bits

   // The code word of a RAM word, read through RAW_ADDR, RAW_LO and RAW_HI, is the one the predictor expects.
   task check_code(bit [5:0] word, string id);
      bit            [38:0] code = env.predictor.expected_code(word);
      uvm_reg_data_t        value;
      env.csr.write(env.regs.raw_addr, word, this);
      env.csr.read(env.regs.raw_lo, value, this);
      `hexk_check_eq(32'(value), code[31:0], id, $sformatf("RAW_LO of RAM word %0d", word))
      env.csr.read(env.regs.raw_hi, value, this);
      `hexk_check_eq(32'(value), {25'd0, code[38:32]}, id, $sformatf("RAW_HI of RAM word %0d", word))
   endtask : check_code

endclass : hexk_ref_scenario_vseq

`endif  // HEXK_REF_SCENARIO_VSEQ_SV
