// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_layout.sv
//
// Where the packets of hexk_ref_multi_vseq go: one range of word addresses per packet, randomized,
// inside the RAM and none overlapping (hexk_constraint_no_overlap).

`ifndef HEXK_REF_LAYOUT_SV
`define HEXK_REF_LAYOUT_SV

// Where the packets of the sequence go: one range of word addresses per packet, none overlapping.
class hexk_ref_layout extends uvm_object;

   // Number of packets.
   localparam int unsigned NUM_PACKETS = 5;

   // First and last word of each packet.
   rand int unsigned first[NUM_PACKETS];
   rand int unsigned last [NUM_PACKETS];

   `uvm_object_utils(hexk_ref_layout)

   // Inside the RAM, 1 to 12 words each.
   constraint legal_values_cstr {
      foreach (first[i]) {
         first[i] < hexk_ref_regs::MEM_WORDS;
         last[i] < hexk_ref_regs::MEM_WORDS;
         last[i] >= first[i];
         last[i] - first[i] < 12;
      }
   }

   `hexk_constraint_no_overlap(first, last)

   // Creates a layout.
   function new(string name = "hexk_ref_layout");
      super.new(name);
   endfunction : new

endclass : hexk_ref_layout

`endif  // HEXK_REF_LAYOUT_SV
