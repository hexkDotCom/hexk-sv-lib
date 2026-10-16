// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_mem_vseq.sv
//
// The MEM window of the register map, through plain bus accesses (hexk_ref_bus_seq), without packets:
// - every word written whole first, as a debugger initializes a RAM; the predictor learns the words
//   from these writes, and every word reads back as written;
// - all 16 patterns of byte enables, one per word: a write changes exactly its enabled bytes, and
//   the code word in the RAM (RAW_*) is that of the result;
// - a partial write to a word with one flipped bit and to one with two (flipped by HDL access): the
//   DUT decodes first, so the kept bytes are the corrected ones, or with two errors the decoded,
//   wrong ones; ERR counts each decode.
// The values that a write must give are computed here from what the sequence wrote, not taken from
// the predictor, which checks every read on its own as well.

`ifndef HEXK_REF_MEM_VSEQ_SV
`define HEXK_REF_MEM_VSEQ_SV

class hexk_ref_mem_vseq extends hexk_ref_scenario_vseq;

   // What the sequence wrote into each word of the RAM.
   bit [31:0] written[hexk_ref_regs::MEM_WORDS];

   `uvm_object_utils(hexk_ref_mem_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_mem_vseq");
      super.new(name);
   endfunction : new

   // Initialization, the byte enables, and partial writes to damaged words.
   task body();
      initialize();
      for (int unsigned strobe = 0; strobe < 16; strobe++) begin
         write_bytes(6'(strobe), 4'(strobe));
      end
      write_damaged(6'd20, 39'h00_0000_0040, 4'b0010);
      write_damaged(6'd21, 39'h00_0000_0180, 4'b1000);
   endtask : body

   // The byte address of a word of the RAM.
   function bit [8:0] mem_addr(bit [5:0] word);
      return 9'(hexk_ref_regs::MEM_BASE + 4 * word);
   endfunction : mem_addr

   // Every word written whole with random data, then read back.
   task initialize();
      bit [31:0] data;
      for (int unsigned word = 0; word < hexk_ref_regs::MEM_WORDS; word++) begin
         `hexk_std_randomize_or_fatal(data, "REF_RAND")
         written[word] = data;
         hexk_ref_bus_seq::write(this, env.bus_agent.sqr, mem_addr(6'(word)), written[word]);
      end
      for (int unsigned word = 0; word < hexk_ref_regs::MEM_WORDS; word++) begin
         env.csr.read_check(env.regs.mem_reg(word), written[word], "REF_MEM_INIT", '1, this);
      end
   endtask : initialize

   // The word that a write of data with the byte enables strobe makes of old.
   function bit [31:0] merged(bit [31:0] old, bit [31:0] data, bit [3:0] strobe);
      for (int unsigned b = 0; b < 4; b++) begin
         if (strobe[b]) begin
            old[8*b+:8] = data[8*b+:8];
         end
      end
      return old;
   endfunction : merged

   // A write of random data with the byte enables strobe to word; the word and its code word afterwards.
   task write_bytes(bit [5:0] word, bit [3:0] strobe);
      bit [31:0] data;
      `hexk_std_randomize_or_fatal(data, "REF_RAND")
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, mem_addr(word), data, strobe);
      written[word] = merged(written[word], data, strobe);
      env.csr.read_check(env.regs.mem_reg(word), written[word], "REF_MEM_STROBE", '1, this);
      check_code(word, "REF_MEM_CODE");
   endtask : write_bytes

   // flip in the code word of word by HDL access, then a partial write: the kept bytes are what the DUT decoded.
   task write_damaged(bit [5:0] word, bit [38:0] flip, bit [3:0] strobe);
      bit [31:0] data;
      bit [31:0] decoded;
      `hexk_std_randomize_or_fatal(data, "REF_RAND")
      flip_code_bits(word, flip);
      // A single error decodes to what was written; a double one to what the predictor's decoder makes of it.
      decoded = ($countones(flip) == 1) ? written[word] : env.predictor.expected_word(word);
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, mem_addr(word), data, strobe);
      written[word] = merged(decoded, data, strobe);
      env.csr.read_check(env.regs.mem_reg(word), written[word], "REF_MEM_DAMAGED", '1, this);
      check_code(word, "REF_MEM_CODE");
   endtask : write_damaged

endclass : hexk_ref_mem_vseq

`endif  // HEXK_REF_MEM_VSEQ_SV
