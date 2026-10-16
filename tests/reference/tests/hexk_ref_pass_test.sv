// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_pass_test.sv
//
// Random packets, plain and scrambled as the knob ref_mode says, with the interrupt or by polling
// as ref_irq says. Every packet result and every commit must match.

`ifndef HEXK_REF_PASS_TEST_SV
`define HEXK_REF_PASS_TEST_SV

class hexk_ref_pass_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_pass_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

endclass : hexk_ref_pass_test

`endif  // HEXK_REF_PASS_TEST_SV
