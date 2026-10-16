// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_mem_model.sv
//
// Model of the RAM of the DUT: hexk_mem_model with byte addresses, word i at byte address 4 * i.
// It holds the data the DUT should return, with partial writes through the bus applied as byte
// enables. At the end of the test (hexk_eot_registry) it checks that no word was read that the
// test never wrote: in this testbench such a read is a mistake of the testbench.

`ifndef HEXK_REF_MEM_MODEL_SV
`define HEXK_REF_MEM_MODEL_SV

class hexk_ref_mem_model extends hexk_mem_model #(
    .ADDR_WIDTH(8),
    .DATA_WIDTH(32)
);

   `uvm_object_utils(hexk_ref_mem_model)

   // Creates the model; a read of an unwritten byte is counted and reported.
   function new(string name = "hexk_ref_mem_model");
      super.new(name);
   endfunction : new

   // hexk_checkable: the summary of the library, then the invariant of this testbench.
   virtual function void eot_check();
      super.eot_check();
      `hexk_check_eq(num_uninit_reads(), 0, "REF_MEM_UNINIT", "the testbench read words that it never wrote")
   endfunction : eot_check

endclass : hexk_ref_mem_model

`endif  // HEXK_REF_MEM_MODEL_SV
