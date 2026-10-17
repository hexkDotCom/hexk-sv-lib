// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_test_vseq.sv
//
// The stimulus of every reference test: runs the scenario of the test, the virtual sequence that
// create_scenario() of the test returned, as its child, and then has the environment compare ERR
// with the predictor. hexk_ref_base_test gives it to hexk_base_test as the stimulus, which
// randomizes it, the scenario with it, and starts it on no sequencer.

`ifndef HEXK_REF_TEST_VSEQ_SV
`define HEXK_REF_TEST_VSEQ_SV

class hexk_ref_test_vseq extends hexk_ref_vseq_base;

   // The scenario of the test; assigned by the starter, randomized with this sequence.
   rand hexk_ref_vseq_base scenario;

   `uvm_object_utils(hexk_ref_test_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_test_vseq");
      super.new(name);
   endfunction : new

   // The scenario, then the check of the error counters.
   task body();
      if (scenario == null) begin
         `uvm_fatal("REF_VSEQ_SCENARIO", "scenario is null; the starter assigns it before start()")
      end
      scenario.start(null, this);
      env.check_error_counters(this);
   endtask : body

endclass : hexk_ref_test_vseq

`endif  // HEXK_REF_TEST_VSEQ_SV
