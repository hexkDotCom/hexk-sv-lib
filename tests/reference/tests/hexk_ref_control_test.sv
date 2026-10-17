// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_control_test.sv
//
// The control of the DUT with hexk_ref_control_vseq: the gate of CTRL.EN, STATUS.BUSY, the timing
// of DONE, the mask of IRQ_EN and the write-1-to-clear of IRQ.DONE.

`ifndef HEXK_REF_CONTROL_TEST_SV
`define HEXK_REF_CONTROL_TEST_SV

class hexk_ref_control_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_control_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The control sequence.
   virtual function hexk_ref_vseq_base create_scenario();
      return hexk_ref_control_vseq::type_id::create("control_seq");
   endfunction : create_scenario

endclass : hexk_ref_control_test

`endif  // HEXK_REF_CONTROL_TEST_SV
