// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_hang_test.sv
//
// A DUT that takes a packet and never finishes it: hexk_ref_fault_vseq sets DEBUG.HANG, so DONE is
// never set. The packet was accepted and predicted, so its expected result waits in the
// scoreboard; the sequence's wait for DONE gives up with REF_DONE, and the scoreboard's time limit
// (max_wait_ps) reports the result that never came with HEXK_SB_TIMEOUT, long before the watchdog
// would end the test; at the end, the check of the base test that every packet sent was matched
// reports REF_MATCHED. The test fails with exactly these three errors: the regression list expects
// that.

`ifndef HEXK_REF_HANG_TEST_SV
`define HEXK_REF_HANG_TEST_SV

// MSG-9 waived: this test is meant to end FAILED, to show what a hang looks like; its line in the regression list
// states the IDs, severities, counts and the scoreboard that reports the timeout.
class hexk_ref_hang_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_hang_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // One packet into a DUT that hangs.
   virtual function hexk_ref_vseq_base create_scenario();
      hexk_ref_fault_vseq hang_seq = hexk_ref_fault_vseq::type_id::create("hang_seq");
      hang_seq.fault = HEXK_REF_FAULT_HANG;
      return hang_seq;
   endfunction : create_scenario

endclass : hexk_ref_hang_test

`endif  // HEXK_REF_HANG_TEST_SV
