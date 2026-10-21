// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_mem_test.sv
//
// The RAM through plain bus accesses with hexk_ref_mem_vseq, without packets: written whole first,
// then every pattern of byte enables, then partial writes to words with one and with two flipped
// bits. Every read must give what the writes made of the word.

`ifndef HEXK_REF_MEM_TEST_SV
`define HEXK_REF_MEM_TEST_SV

class hexk_ref_mem_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_mem_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: the checks of the scenario ran (guide TST-6): reads of the RAM after the first writes, after
   // writes with byte enables and after damaged code words.
   function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      `hexk_check_ne(hexk_check_stats::num_passed("REF_MEM_INIT"), 0, "REF_MEM_CHECKED", "reads after the first writes")
      `hexk_check_ne(hexk_check_stats::num_passed("REF_MEM_STROBE"), 0, "REF_MEM_CHECKED", "reads after byte enables")
      `hexk_check_ne(hexk_check_stats::num_passed("REF_MEM_DAMAGED"), 0, "REF_MEM_CHECKED", "reads of damaged words")
   endfunction : check_phase

   // The bus accesses to the RAM.
   virtual function hexk_ref_vseq_base create_scenario();
      return hexk_ref_mem_vseq::type_id::create("mem_seq");
   endfunction : create_scenario

endclass : hexk_ref_mem_test

`endif  // HEXK_REF_MEM_TEST_SV
