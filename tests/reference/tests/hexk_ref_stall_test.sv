// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_stall_test.sv
//
// A DUT whose input never becomes ready: hexk_ref_fault_vseq drives the strap pin that holds the
// input's ready at 0, then sends a packet. Nothing is accepted and nothing is predicted, so no
// scoreboard waits for anything; the sequence waits for ever, and only the watchdog can end the
// test: its fatal names the busy input agent.

`ifndef HEXK_REF_STALL_TEST_SV
`define HEXK_REF_STALL_TEST_SV

class hexk_ref_stall_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_stall_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // One packet into a DUT that never takes a word.
   virtual function hexk_ref_vseq_base create_traffic();
      hexk_ref_fault_vseq stall_seq = hexk_ref_fault_vseq::type_id::create("stall_seq");
      stall_seq.fault = HEXK_REF_FAULT_STALL;
      return stall_seq;
   endfunction : create_traffic

endclass : hexk_ref_stall_test

`endif  // HEXK_REF_STALL_TEST_SV
