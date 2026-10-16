// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_regs_test.sv
//
// The registers with hexk_ref_regs_vseq: reset values, byte enables of register writes, unmapped
// addresses, and the bit-bash sequence of UVM. The test excludes from the bit bash what it must not
// touch: the 64 words of the RAM (the other tests write and read them by the thousand), DEBUG, whose
// HANG bit would stop every packet, and RAW_LO and RAW_HI, which show the code word of the RAM at
// RAW_ADDR: the RAM has no reset value, so a word that nothing has written reads as X, which the
// bus driver reports. exclude() also tells the register sequences of UVM.

`ifndef HEXK_REF_REGS_TEST_SV
`define HEXK_REF_REGS_TEST_SV

class hexk_ref_regs_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_regs_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // What the bit bash leaves out.
   virtual function void configure_test();
      hexk_csr_util::exclude ("*.mem_*", HEXK_CSR_BIT_BASH);
      hexk_csr_util::exclude ("*.debug", HEXK_CSR_BIT_BASH);
      hexk_csr_util::exclude ("*.raw_lo", HEXK_CSR_BIT_BASH);
      hexk_csr_util::exclude ("*.raw_hi", HEXK_CSR_BIT_BASH);
   endfunction : configure_test

   // The register checks.
   virtual function hexk_ref_vseq_base create_traffic();
      return hexk_ref_regs_vseq::type_id::create("regs_seq");
   endfunction : create_traffic

endclass : hexk_ref_regs_test

`endif  // HEXK_REF_REGS_TEST_SV
