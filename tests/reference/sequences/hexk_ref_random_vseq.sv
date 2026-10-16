// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_random_vseq.sv
//
// Random traffic: num_packets packets, each with hexk_ref_packet_vseq, one after the other, so a
// result is never read while the next packet overwrites it. The lengths stay within the limits of
// the cfg; which packets are scrambled follows the mode. The default traffic of the base test.

`ifndef HEXK_REF_RANDOM_VSEQ_SV
`define HEXK_REF_RANDOM_VSEQ_SV

class hexk_ref_random_vseq extends hexk_ref_scenario_vseq;

   // Number of packets.
   int unsigned num_packets = 10;

   `uvm_object_utils(hexk_ref_random_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_random_vseq");
      super.new(name);
   endfunction : new

   // The packets.
   task body();
      for (int unsigned i = 0; i < num_packets; i++) begin
         send_random_packet(i);
      end
   endtask : body

endclass : hexk_ref_random_vseq

`endif  // HEXK_REF_RANDOM_VSEQ_SV
