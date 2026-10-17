// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_vectors_test.sv
//
// The fixed packets with hexk_ref_vectors_vseq: each one through the normal flow, then the
// registers against the fixed values that a Python script computed without the library.

`ifndef HEXK_REF_VECTORS_TEST_SV
`define HEXK_REF_VECTORS_TEST_SV

class hexk_ref_vectors_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_vectors_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The fixed packets.
   virtual function hexk_ref_vseq_base create_scenario();
      return hexk_ref_vectors_vseq::type_id::create("vectors_seq");
   endfunction : create_scenario

endclass : hexk_ref_vectors_test

`endif  // HEXK_REF_VECTORS_TEST_SV
