// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_back_to_back_test.sv
//
// Packets that follow each other without a gap, with hexk_ref_back_to_back_vseq. The input agent
// sends without delays, so that a packet is accepted while the one before it is still in the
// pipeline. The DUT then overwrites the result registers before they could be read, so the test
// turns the result stream of the predictor off (publish_results) and expects no packet result to
// match; the sequence compares the registers after each burst instead. Every commit must still
// match.

`ifndef HEXK_REF_BACK_TO_BACK_TEST_SV
`define HEXK_REF_BACK_TO_BACK_TEST_SV

class hexk_ref_back_to_back_test extends hexk_ref_base_test;

   `uvm_component_utils(hexk_ref_back_to_back_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The input sends without delays, so that the packets of a burst follow each other closely.
   virtual function void modify_randomized_cfg();
      super.modify_randomized_cfg();
      env_cfg.in_cfg.delay_cfg.mode = HEXK_DELAY_NONE;
   endfunction : modify_randomized_cfg

   // UVM callback: the predictor publishes no results, which nobody could collect.
   function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      env.predictor.publish_results = 0;
   endfunction : end_of_elaboration_phase

   // The bursts.
   virtual function hexk_ref_vseq_base create_scenario();
      return hexk_ref_back_to_back_vseq::type_id::create("back_to_back_seq");
   endfunction : create_scenario

   // The results go to no scoreboard in this test.
   virtual function int unsigned expected_matches();
      return 0;
   endfunction : expected_matches

endclass : hexk_ref_back_to_back_test

`endif  // HEXK_REF_BACK_TO_BACK_TEST_SV
