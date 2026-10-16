// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_packet_vseq.sv
//
// One packet from start to end: program BASE and CTRL, send the words, wait for DONE, collect the
// result for the result scoreboard, acknowledge DONE. The words are random, len of them, or the
// given ones in words. collected says afterwards whether DONE came and the result was collected.
// A length outside 1 to 16 is the fatal REF_PACKET_LEN before anything is sent. The packet is
// traced with REF_PACKET at UVM_MEDIUM, its words at UVM_HIGH (+UVM_VERBOSITY=UVM_HIGH).

`ifndef HEXK_REF_PACKET_VSEQ_SV
`define HEXK_REF_PACKET_VSEQ_SV

class hexk_ref_packet_vseq extends hexk_ref_vseq_base;

   // The packet: its length in words, whether it is scrambled, and its first word address in the RAM.
   rand int unsigned        len;
   rand bit                 scramble;
   rand bit          [ 5:0] base;

   // Words to send instead of random ones; when given, their number is the length.
   bit               [31:0] words     [$];

   // After the sequence: 1 when DONE came and the result was collected.
   bit                      collected;

   `uvm_object_utils(hexk_ref_packet_vseq)

   // A length the DUT takes.
   constraint legal_len_cstr {len inside {[1 : 16]};}

   // Creates the sequence.
   function new(string name = "hexk_ref_packet_vseq");
      super.new(name);
   endfunction : new

   // The packet.
   task body();
      bit [31:0] data[$] = words;
      int unsigned size = (words.size() != 0) ? words.size() : len;
      if (size < 1 || size > 16) begin
         `uvm_fatal("REF_PACKET_LEN", $sformatf("a packet has 1 to 16 words, not %0d", size))
      end
      if (data.size() == 0) begin
         random_words(len, data);
      end
      `uvm_info("REF_PACKET", $sformatf("%0d words at word %0d, %s", data.size(), base,
                                        scramble ? "scrambled" : "plain"), UVM_MEDIUM)
      foreach (data[i]) begin
         `uvm_info("REF_PACKET", $sformatf("  word %0d: 0x%08h", i, data[i]), UVM_HIGH)
      end
      program_packet(data.size(), scramble, base);
      send_words(data);
      env.packets_sent++;
      wait_done(collected);
      if (collected) begin
         collect(data.size(), base);
         acknowledge_done();
      end
   endtask : body

endclass : hexk_ref_packet_vseq

`endif  // HEXK_REF_PACKET_VSEQ_SV
