// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_warm_reset_test.sv
//
// Two resets in the middle of the traffic, with hexk_ref_warm_reset_vseq: a warm reset with the
// clock stopped and given a new period, and a reset between two edges that cuts a packet with
// words in the pipeline. Packets before and after the resets must all match, except the commits
// of the words that the reset dropped; and the monitor of the clock and reset agent must have
// checked the clock at both periods.

`ifndef HEXK_REF_WARM_RESET_TEST_SV
`define HEXK_REF_WARM_RESET_TEST_SV

class hexk_ref_warm_reset_test extends hexk_ref_base_test;

   // The scenario, kept for what it reports afterwards.
   hexk_ref_warm_reset_vseq scenario;

   `uvm_component_utils(hexk_ref_warm_reset_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The clock was checked at the old period and at the new one.
   function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      `hexk_check_ne(env.clk_rst_agent.mon.num_checked_at(scenario.old_period_ps), 0, "REF_CLOCK_CHECKED",
                     "intervals checked before the warm reset")
      `hexk_check_ne(env.clk_rst_agent.mon.num_checked_at(hexk_ref_warm_reset_vseq::NEW_PERIOD_PS), 0,
                     "REF_CLOCK_CHECKED", "intervals checked after the warm reset")
   endfunction : check_phase

   // The resets.
   virtual function hexk_ref_vseq_base create_scenario();
      scenario = hexk_ref_warm_reset_vseq::type_id::create("scenario");
      return scenario;
   endfunction : create_scenario

   // Every word sent was committed, except those that a reset dropped.
   virtual function int unsigned expected_commits();
      return env.words_sent - scenario.dropped_words;
   endfunction : expected_commits

endclass : hexk_ref_warm_reset_test

`endif  // HEXK_REF_WARM_RESET_TEST_SV
