// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_ecc_test.sv
//
// Errors in the RAM with hexk_ref_ecc_vseq: injected through the DUT, and by HDL access at every
// one of the 39 positions alone and at every pair of neighbouring positions; then the error
// counters driven to their limit. Everything the predictor expects must match.

`ifndef HEXK_REF_ECC_TEST_SV
`define HEXK_REF_ECC_TEST_SV

class hexk_ref_ecc_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_ecc_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The injections.
   virtual function hexk_ref_vseq_base create_scenario();
      return hexk_ref_ecc_vseq::type_id::create("ecc_seq");
   endfunction : create_scenario

endclass : hexk_ref_ecc_test

`endif  // HEXK_REF_ECC_TEST_SV
