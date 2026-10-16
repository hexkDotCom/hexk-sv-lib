// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_corrupt_vseq.sv
//
// DEBUG.CORRUPT_READ inverts bit 0 of every word that a read of the RAM returns, after the ECC has
// corrected it; then num_packets random packets. Every packet result then differs from the
// expected one, which the starter expects. The predictor knows CORRUPT_READ, so its own check of
// every read still passes. After each packet the sequence checks that the result that was
// collected, the one the scoreboard compared, is right in everything else: its number, CRC and
// CYCLES as expected, and every word with bit 0 inverted and nothing else, so that a mismatch
// caused by something other than CORRUPT_READ cannot hide.

`ifndef HEXK_REF_CORRUPT_VSEQ_SV
`define HEXK_REF_CORRUPT_VSEQ_SV

class hexk_ref_corrupt_vseq extends hexk_ref_scenario_vseq;

   // Number of packets.
   int unsigned num_packets = 4;

   `uvm_object_utils(hexk_ref_corrupt_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_corrupt_vseq");
      super.new(name);
   endfunction : new

   // Every read corrupted; each packet result is a mismatch.
   task body();
      // The whole register: CORRUPT_READ and HANG share a byte and are not individually accessible, so a
      // write of one of them would be a write of the whole register anyway, with a warning of UVM.
      env.csr.write(env.regs.debug, 1 << env.regs.debug_corrupt_read.get_lsb_pos(), this);
      for (int unsigned i = 0; i < num_packets; i++) begin
         send_random_packet(i);
         check_corrupted_result();
      end
   endtask : body

   // The collected result of the last packet: number, CRC and CYCLES as expected, every word with bit 0 inverted.
   function void check_corrupted_result();
      hexk_ref_result expected = env.predictor.last_result;
      hexk_ref_result actual = last_packet.collected_result;
      if (!last_packet.collected || actual == null) begin
         `uvm_error("REF_CORRUPT_RESULT", "the result of the packet was not collected")
         return;
      end
      `hexk_check_eq(actual.number, expected.number, "REF_CORRUPT_RESULT", "packet number")
      `hexk_check_eq(actual.crc, expected.crc, "REF_CORRUPT_RESULT", "CRC")
      `hexk_check_eq(actual.cycles, expected.cycles, "REF_CORRUPT_RESULT", "CYCLES")
      `hexk_check_eq(actual.words.size(), expected.words.size(), "REF_CORRUPT_RESULT", "words")
      foreach (expected.words[i]) begin
         if (i < actual.words.size()) begin
            `hexk_check_eq(actual.words[i], expected.words[i] ^ 32'd1, "REF_CORRUPT_RESULT", $sformatf("word %0d", i))
         end
      end
   endfunction : check_corrupted_result

endclass : hexk_ref_corrupt_vseq

`endif  // HEXK_REF_CORRUPT_VSEQ_SV
