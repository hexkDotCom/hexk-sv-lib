// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_ecc_vseq.sv
//
// Errors in the RAM, two ways:
// - through the DUT: INJ_LO/INJ_HI/INJ_CTRL put a mask into the next code word that it commits;
// - from outside: a code word with flipped bits deposited into the RAM of the DUT by HDL access,
//   as a fault-injection test does (flip_code_bits(); Questa and VCS).
// From outside, every one of the 39 bit positions is flipped alone (corrected: the overall parity
// bit, the check bits and the data bits), and every pair of neighbouring positions (detected, not
// corrected). The predictor knows each injection and predicts, with hexk_ecc, the code word in the
// RAM (read back through RAW_*), the data of every read and the error counters. At the end the
// counters are driven to their limit: they stay at 255.

`ifndef HEXK_REF_ECC_VSEQ_SV
`define HEXK_REF_ECC_VSEQ_SV

class hexk_ref_ecc_vseq extends hexk_ref_scenario_vseq;

   // Number of positions of a code word.
   localparam int unsigned CODE_BITS = 39;

   `uvm_object_utils(hexk_ref_ecc_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_ecc_vseq");
      super.new(name);
   endfunction : new

   // Injection through the DUT, every single and every neighbouring double error from outside, then saturation.
   task body();
      inject_on_commit(6'd50, 39'h0000_0000_20);
      inject_on_commit(6'd51, 39'h40_0000_0001);
      // Word i gets the single error at position i, then (overwritten by a new packet) the double error at i and i+1.
      for (int unsigned pos = 0; pos < CODE_BITS; pos++) begin
         inject_by_path(6'(pos), 39'(1) << pos);
      end
      for (int unsigned pos = 0; pos + 1 < CODE_BITS; pos++) begin
         inject_by_path(6'(pos), 39'(3) << pos);
      end
      // Word 38 kept its single error, word 0 has a double one.
      saturate(6'd38, 1);
      saturate(6'd0, 0);
   endtask : body

   // A one-word packet at word whose code word gets mask when the DUT commits it.
   task inject_on_commit(bit [5:0] word, bit [38:0] mask);
      env.csr.write(env.regs.inj_lo, mask[31:0], this);
      env.csr.write(env.regs.inj_hi, mask[38:32], this);
      env.csr.write(env.regs.inj_ctrl, 1, this);
      send_packet(1, 0, word);
      check_code(word, "REF_ECC_CODE");
   endtask : inject_on_commit

   // A one-word packet at word, then mask XORed into its code word in the RAM by HDL access; the code word and a
   // read of the word afterwards.
   task inject_by_path(bit [5:0] word, bit [38:0] mask);
      send_packet(1, 0, word);
      flip_code_bits(word, mask);
      check_code(word, "REF_ECC_CODE");
      env.csr.read_check(env.regs.mem_reg(word), env.predictor.expected_word(word), "REF_ECC_WORD", '1, this);
   endtask : inject_by_path

   // Reads word, which holds a single error (corrected) or a double one, until its counter in ERR is at 254, then three
   // times more: the counter reaches 255 and stays there.
   task saturate(bit [5:0] word, bit corrected);
      uvm_reg_data_t value;
      while ((corrected ? env.predictor.corrected : env.predictor.uncorrectable) < 254) begin
         env.csr.read(env.regs.mem_reg(word), value, this);
      end
      repeat (3) begin
         env.csr.read(env.regs.mem_reg(word), value, this);
         env.check_error_counters(this);
      end
      `hexk_check_eq(corrected ? env.predictor.corrected : env.predictor.uncorrectable, 255, "REF_ECC_SATURATED",
                     "error counter at its limit")
   endtask : saturate

endclass : hexk_ref_ecc_vseq

`endif  // HEXK_REF_ECC_VSEQ_SV
