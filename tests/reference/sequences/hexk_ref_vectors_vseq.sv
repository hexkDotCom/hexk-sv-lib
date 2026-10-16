// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_vectors_vseq.sv
//
// The fixed packets of hexk_ref_vectors.svh, whose CRC, stored words and code words were computed
// by a Python script without the library. Each packet goes through the normal flow, so the
// scoreboards compare the DUT with the library models as for random packets; then the registers
// are compared with the fixed values. A disagreement shows which of the three is wrong: the DUT,
// the library, or the testbench.

`ifndef HEXK_REF_VECTORS_VSEQ_SV
`define HEXK_REF_VECTORS_VSEQ_SV

class hexk_ref_vectors_vseq extends hexk_ref_scenario_vseq;

   `uvm_object_utils(hexk_ref_vectors_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_vectors_vseq");
      super.new(name);
   endfunction : new

   // Sends every fixed packet and checks the registers against the fixed values.
   task body();
      for (int unsigned i = 0; i < HEXK_REF_NUM_VECTORS; i++) begin
         hexk_ref_vector_t    vector = hexk_ref_vector(i);
         hexk_ref_packet_vseq vector_seq = hexk_ref_packet_vseq::type_id::create("vector_seq");
         `hexk_randomize_or_fatal(vector_seq, "REF_RAND")
         vector_seq.words    = vector.words;
         vector_seq.scramble = vector.scramble;
         vector_seq.base     = vector.base;
         start_child(vector_seq);
         if (!vector_seq.collected) begin
            continue;
         end
         env.csr.read_check(env.regs.crc, vector.crc, "REF_VECTOR_CRC", '1, this);
         foreach (vector.stored[w]) begin
            int unsigned word = (vector.base + w) % hexk_ref_regs::MEM_WORDS;
            env.csr.read_check(env.regs.mem_reg(word), vector.stored[w], "REF_VECTOR_WORD", '1, this);
            env.csr.write(env.regs.raw_addr, word, this);
            env.csr.read_check(env.regs.raw_lo, vector.codes[w][31:0], "REF_VECTOR_CODE", '1, this);
            env.csr.read_check(env.regs.raw_hi, vector.codes[w][38:32], "REF_VECTOR_CODE", '1, this);
         end
      end
   endtask : body

endclass : hexk_ref_vectors_vseq

`endif  // HEXK_REF_VECTORS_VSEQ_SV
