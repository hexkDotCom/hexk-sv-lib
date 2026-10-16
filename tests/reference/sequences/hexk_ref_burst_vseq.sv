// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_burst_vseq.sv
//
// Packets that follow each other without a gap: CTRL is programmed once, and the words of count
// packets of len words go out as one stream, so that a packet is accepted while the one before it
// is still in the pipeline. DONE comes with the first packet: the sequence waits until every word is
// committed and DONE has come, then acknowledges it. It collects nothing: the DUT overwrites its
// result registers with every packet, so only the last result can be read, which the starter
// compares itself.

`ifndef HEXK_REF_BURST_VSEQ_SV
`define HEXK_REF_BURST_VSEQ_SV

class hexk_ref_burst_vseq extends hexk_ref_vseq_base;

   // count packets of len words, scrambled or not, all starting at word address base.
   rand int unsigned       count;
   rand int unsigned       len;
   rand bit                scramble;
   rand bit          [5:0] base;

   // After the sequence: 1 when DONE came.
   bit                     done;

   // The most packets in a burst.
   localparam int unsigned MAX_COUNT = 1000;

   `uvm_object_utils(hexk_ref_burst_vseq)

   // A burst the DUT takes.
   constraint legal_cstr {
      count inside {[1 : MAX_COUNT]};
      len inside {[1 : 16]};
   }

   // Creates the sequence.
   function new(string name = "hexk_ref_burst_vseq");
      super.new(name);
   endfunction : new

   // The burst.
   task body();
      bit [31:0] data[$];
      if (count < 1 || count > MAX_COUNT || len < 1 || len > 16) begin
         `uvm_fatal("REF_PACKET_LEN", $sformatf("a burst has 1 to %0d packets of 1 to 16 words, not %0d of %0d",
                                                MAX_COUNT, count, len))
      end
      `uvm_info("REF_PACKET", $sformatf("burst of %0d packets of %0d words at word %0d, %s", count, len, base,
                                        scramble ? "scrambled" : "plain"), UVM_MEDIUM)
      program_packet(len, scramble, base);
      random_words(count * len, data);
      send_words(data);
      env.packets_sent += count;
      wait_drained();
      wait_done(done);
      if (done) begin
         acknowledge_done();
      end
   endtask : body

endclass : hexk_ref_burst_vseq

`endif  // HEXK_REF_BURST_VSEQ_SV
