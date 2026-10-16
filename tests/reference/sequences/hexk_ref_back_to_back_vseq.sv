// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_back_to_back_vseq.sv
//
// Bursts of packets that follow each other without a gap (hexk_ref_burst_vseq), one length per
// burst, from one word to the full sixteen. A packet is then accepted while the one before it is
// still in the pipeline, and the DUT overwrites the result registers (CRC, CYCLES,
// STATUS.PKT_COUNT) before they could be read, so this sequence collects no result: after each
// burst it compares the registers with the result that the predictor expects for the last packet,
// and the words of the RAM that the burst wrote (all packets of a burst start at one base) with
// their code words. A burst of 260 one-word packets takes STATUS.PKT_COUNT through 255 and back to
// 0. The starter turns the result stream of the predictor off and the delays of the input agent.

`ifndef HEXK_REF_BACK_TO_BACK_VSEQ_SV
`define HEXK_REF_BACK_TO_BACK_VSEQ_SV

class hexk_ref_back_to_back_vseq extends hexk_ref_scenario_vseq;

   `uvm_object_utils(hexk_ref_back_to_back_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_back_to_back_vseq");
      super.new(name);
   endfunction : new

   // Bursts of packets of one length each.
   task body();
      burst(8, 1, 0);
      burst(6, 2, 1);
      burst(3, 5, 0);
      burst(2, 16, 1);
      burst(260, 1, 1);
   endtask : body

   // num_packets packets of packet_len words, at a random base; then the registers against the last expected
   // result. The arguments are named apart from the members of the sequence, which the constraints name.
   task burst(int unsigned num_packets, int unsigned packet_len, bit scrambled);
      hexk_ref_burst_vseq burst_seq = hexk_ref_burst_vseq::type_id::create("burst_seq");
      int unsigned        packets_before = env.predictor.num_packets;
      `hexk_randomize_with_or_fatal(burst_seq, "REF_RAND",
                                    count == local::num_packets; len == local::packet_len;
                                    scramble == local::scrambled;)
      start_child(burst_seq);
      wait_quiet();
      `hexk_check_eq(env.predictor.num_packets - packets_before, num_packets, "REF_B2B_PACKETS", "packets completed")
      check_last_result();
      check_ram(burst_seq.base, packet_len);
   endtask : burst

   // The words that the last packet wrote, their data and their code words, as the predictor expects them.
   task check_ram(bit [5:0] base, int unsigned len);
      for (int unsigned i = 0; i < len; i++) begin
         env.csr.read_check(env.regs.mem_reg(base + i), env.predictor.expected_word(base + i), "REF_B2B_RAM", '1, this);
         check_code(6'(base + i), "REF_B2B_RAM");
      end
   endtask : check_ram

   // The result registers hold the result of the last packet, as the predictor expects it.
   task check_last_result();
      hexk_ref_result expected = env.predictor.last_result;
      env.csr.read_check(env.regs.crc, expected.crc, "REF_B2B_RESULT", '1, this);
      env.csr.read_check(env.regs.cycles, expected.cycles, "REF_B2B_RESULT", '1, this);
      env.csr.read_check(env.regs.status, {16'd0, expected.number, 8'd0}, "REF_B2B_RESULT", '1, this);
   endtask : check_last_result

endclass : hexk_ref_back_to_back_vseq

`endif  // HEXK_REF_BACK_TO_BACK_VSEQ_SV
