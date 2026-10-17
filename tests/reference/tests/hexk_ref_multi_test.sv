// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_multi_test.sv
//
// Packets at randomized places that must not overlap, then byte writes into them, then every word
// read back against the RAM model, with hexk_ref_multi_vseq.

`ifndef HEXK_REF_MULTI_TEST_SV
`define HEXK_REF_MULTI_TEST_SV

class hexk_ref_multi_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_multi_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The packets at their places.
   virtual function hexk_ref_vseq_base create_scenario();
      return hexk_ref_multi_vseq::type_id::create("multi_seq");
   endfunction : create_scenario

endclass : hexk_ref_multi_test

`endif  // HEXK_REF_MULTI_TEST_SV
