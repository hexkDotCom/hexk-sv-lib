// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_multi_vseq.sv
//
// Several packets at different places of the RAM, which must not overlap: the places come from a
// randomized plan (hexk_ref_layout) whose ranges hexk_constraint_no_overlap keeps apart. After the
// packets, single bytes of their words are written through the bus with byte enables, and at the
// end every word of every packet is read back and compared with the RAM model (hexk_mem_model),
// which saw the same partial writes from the bus monitor.

`ifndef HEXK_REF_MULTI_VSEQ_SV
`define HEXK_REF_MULTI_VSEQ_SV

class hexk_ref_multi_vseq extends hexk_ref_scenario_vseq;

   `uvm_object_utils(hexk_ref_multi_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_multi_vseq");
      super.new(name);
   endfunction : new

   // The packets at their places, partial writes, then every word read back.
   task body();
      hexk_ref_layout layout = hexk_ref_layout::type_id::create("layout");
      `hexk_randomize_or_fatal(layout, "REF_RAND")
      foreach (layout.first[i]) begin
         send_packet(layout.last[i] - layout.first[i] + 1, scramble_of(i), 6'(layout.first[i]));
      end
      foreach (layout.first[i]) begin
         write_byte(layout.first[i], 4'b0100);
         write_byte(layout.last[i], 4'b0001);
      end
      foreach (layout.first[i]) begin
         for (int unsigned word = layout.first[i]; word <= layout.last[i]; word++) begin
            env.csr.read_check(env.regs.mem_reg(word), env.predictor.expected_word(word), "REF_MULTI_WORD", '1, this);
         end
      end
   endtask : body

   // Writes the bytes of strobe of a word through the bus, with random data, as a debugger would.
   task write_byte(int unsigned word, bit [3:0] strobe);
      bit [31:0] data;
      `hexk_std_randomize_or_fatal(data, "REF_RAND")
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, 9'(hexk_ref_regs::MEM_BASE + 4 * word), data, strobe);
   endtask : write_byte

endclass : hexk_ref_multi_vseq

`endif  // HEXK_REF_MULTI_VSEQ_SV
