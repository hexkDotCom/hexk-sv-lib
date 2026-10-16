// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_corrupt_test.sv
//
// A negative test done right: with hexk_ref_corrupt_vseq every read of the RAM is corrupted, so
// every packet result differs, and the test says so in code: expect_check() of the catcher expects
// exactly one HEXK_SB_MISMATCH per packet, demotes those errors and allows the failed checks. The
// test passes only when the mismatches came, exactly as many as packets, and when everything else
// is right, which the sequence checks after each packet.

`ifndef HEXK_REF_CORRUPT_TEST_SV
`define HEXK_REF_CORRUPT_TEST_SV

class hexk_ref_corrupt_test extends hexk_ref_base_test;

   // Number of packets.
   localparam int unsigned NUM_PACKETS = 4;

   `uvm_component_utils(hexk_ref_corrupt_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // One mismatch per packet is expected.
   virtual function void configure_test();
      catcher.expect_check("HEXK_SB_MISMATCH", NUM_PACKETS);
   endfunction : configure_test

   // The packets with corrupted reads.
   virtual function hexk_ref_vseq_base create_traffic();
      hexk_ref_corrupt_vseq corrupt_seq = hexk_ref_corrupt_vseq::type_id::create("corrupt_seq");
      corrupt_seq.num_packets = NUM_PACKETS;
      return corrupt_seq;
   endfunction : create_traffic

   // No packet result matches.
   virtual function int unsigned expected_matches();
      return 0;
   endfunction : expected_matches

   // The packets were compared, each as a mismatch.
   function void check_phase(uvm_phase phase);
      hexk_sb_stats results;
      super.check_phase(phase);
      results = env.result_sb.get_stats();
      `hexk_check_eq(results.mismatched, NUM_PACKETS, "REF_CORRUPT_MISMATCHED", "packets reported as mismatches")
   endfunction : check_phase

endclass : hexk_ref_corrupt_test

`endif  // HEXK_REF_CORRUPT_TEST_SV
