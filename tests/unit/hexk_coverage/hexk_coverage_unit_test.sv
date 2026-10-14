// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_coverage_unit_test.sv
//
// SVUnit tests of hexk_handshake_coverage and of the macro `hexk_cg_new.
// Each test creates a coverage component with a name of its own, after it has set up the
// knob coverage of hexk_knobs the way the test needs it, and samples sequences of cycles
// that are written as text: I, W, S and A for idle, wait, stall and active, and a dot for a
// reset. The same text can go through write() as records of hexk_handshake_cycle_t. The
// coverage numbers are compared as text with two decimals (see tests/unit/README.md). Needs
// UVM. Verilator does not build covergroups, so the tests of the coverage numbers run on the
// other simulators only: make test SIM=questa TEST=hexk_coverage.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_coverage_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_handshake_coverage;
   import hexk_uvm_pkg::hexk_handshake_cycle_t;
   import hexk_uvm_pkg::hexk_handshake_state_e;

   // A component with a covergroup of its own that is created with the macro.
   class hexk_ut_cg_owner extends uvm_component;
      // verilator lint_off COVERIGN
      covergroup level_cg with function sample (bit [1:0] level);
         option.per_instance = 1;
         option.get_inst_coverage = 1;
         level_cp: coverpoint level;
      endgroup : level_cg
      // verilator lint_on COVERIGN

      `uvm_component_utils(hexk_ut_cg_owner)

      function new(string component_name, uvm_component parent);
         super.new(component_name, parent);
         `hexk_cg_new(level_cg)
      endfunction : new

      // 1 when the covergroup was created.
      function bit has_cg();
         return level_cg != null;
      endfunction : has_cg

      // Samples a level when the covergroup exists.
      function void sample (bit [1:0] level);
         if (level_cg != null) begin
            level_cg.sample(level);
         end
      endfunction : sample

      // Name of the covergroup instance, or "" when there is none.
      function string cg_name();
         return (level_cg == null) ? "" : level_cg.option.name;
      endfunction : cg_name

      // Coverage of the instance with two decimals.
      function string cg_coverage();
         if (level_cg == null) begin
            return "none";
         end
         return $sformatf("%0.2f", level_cg.get_inst_coverage());
      endfunction : cg_coverage
   endclass : hexk_ut_cg_owner

   string                  name = "hexk_coverage_ut";
   svunit_testcase         svunit_ut;

   hexk_handshake_coverage coverage;
   hexk_ut_cg_owner        owner;
   int unsigned            serial;

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      hexk_knobs::reset_for_test();
      coverage = null;
      owner    = null;
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_knobs::reset_for_test();
   endtask : teardown

   // Defines the knob coverage with the given value and makes the knobs readable.
   function automatic void define_knob(bit value);
      hexk_knobs knobs = hexk_knobs::get();
      knobs.add_bit("coverage", value, "functional coverage");
      knobs.lock();
   endfunction : define_knob

   // Creates the two components under test, each with a name that no earlier test used.
   function automatic void create();
      serial++;
      coverage = new($sformatf("ut_coverage_%0d", serial), null);
      owner    = new($sformatf("ut_owner_%0d", serial), null);
   endfunction : create

   // Samples a sequence of cycles: I, W, S, A for the four states, a dot for a reset.
   function automatic void cycles(string sequence_text);
      foreach (sequence_text[i]) begin
         case (sequence_text[i])
            "I":     coverage.sample(0, 0);
            "W":     coverage.sample(0, 1);
            "S":     coverage.sample(1, 0);
            "A":     coverage.sample(1, 1);
            default: coverage.on_reset();
         endcase
      end
   endfunction : cycles

   // Writes records of rising edges: I, W, S, A for the four states out of reset; a dot for the first edge
   // of a reset and a dash for a later edge of it; i, w, s, a for a state after a reset that came and went
   // between the edge before and this one.
   function automatic void records(string sequence_text);
      hexk_handshake_cycle_t cycle;
      foreach (sequence_text[i]) begin
         cycle             = '0;
         cycle.reset_began = (sequence_text[i] == "." || (sequence_text[i] >= "a" && sequence_text[i] <= "z"));
         cycle.in_reset    = (sequence_text[i] == "." || sequence_text[i] == "-");
         case (sequence_text[i])
            "W", "w": cycle.ready = 1;
            "S", "s": cycle.valid = 1;
            "A", "a": begin
               cycle.valid = 1;
               cycle.ready = 1;
            end
            default:  ;
         endcase
         coverage.write(cycle);
      end
   endfunction : records

   // Name of the state that two signal values stand for.
   function automatic string state_name(bit valid, bit ready);
      hexk_handshake_state_e state = hexk_handshake_coverage::state_of(valid, ready);
      return state.name();
   endfunction : state_name

   // "<covergroup exists> <samples> <coverage with two decimals>".
   function automatic string status();
      return $sformatf("%0d %0d %0.2f", coverage.is_enabled(), coverage.num_samples(), coverage.get_coverage());
   endfunction : status

   // "<covergroup exists> <samples>".
   function automatic string counts();
      return $sformatf("%0d %0d", coverage.is_enabled(), coverage.num_samples());
   endfunction : counts

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(state_of_names_the_four_combinations)
      `FAIL_UNLESS_STR_EQUAL(state_name(0, 0), "HEXK_HANDSHAKE_IDLE")
      `FAIL_UNLESS_STR_EQUAL(state_name(0, 1), "HEXK_HANDSHAKE_WAIT")
      `FAIL_UNLESS_STR_EQUAL(state_name(1, 0), "HEXK_HANDSHAKE_STALL")
      `FAIL_UNLESS_STR_EQUAL(state_name(1, 1), "HEXK_HANDSHAKE_ACTIVE")
   `SVTEST_END

   `SVTEST(write_samples_the_edges_out_of_reset_only)
      create();
      records("IA.--Wsa");
      `FAIL_UNLESS_STR_EQUAL(counts(), "1 5")
   `SVTEST_END

   `SVTEST(without_the_knob_the_covergroups_are_created)
      create();
      cycles("IWSA");
      `FAIL_UNLESS_STR_EQUAL(counts(), "1 4")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", owner.has_cg()), "1")
   `SVTEST_END

   `SVTEST(with_the_knob_at_1_the_covergroups_are_created)
      define_knob(1);
      create();
      cycles("IA");
      `FAIL_UNLESS_STR_EQUAL(counts(), "1 2")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", owner.has_cg()), "1")
   `SVTEST_END

   `SVTEST(with_the_knob_at_0_no_covergroup_is_created_and_sampling_only_counts)
      define_knob(0);
      create();
      cycles("IWSA.AA");
      owner.sample(2'd1);
      `FAIL_UNLESS_STR_EQUAL(status(), "0 6 0.00")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", owner.has_cg()), "0")
      `FAIL_UNLESS_STR_EQUAL(owner.cg_name(), "")
      `FAIL_UNLESS_STR_EQUAL(owner.cg_coverage(), "none")
   `SVTEST_END

`ifndef VERILATOR
   `SVTEST(the_instance_is_named_after_the_component_and_the_covergroup)
      create();
      `FAIL_UNLESS_STR_EQUAL(owner.cg_name(), {owner.get_full_name(), ".level_cg"})
   `SVTEST_END

   `SVTEST(a_covergroup_created_by_the_macro_collects_coverage)
      create();
      `FAIL_UNLESS_STR_EQUAL(owner.cg_coverage(), "0.00")
      owner.sample(2'd0);
      owner.sample(2'd3);
      `FAIL_UNLESS_STR_EQUAL(owner.cg_coverage(), "50.00")
   `SVTEST_END

   `SVTEST(the_four_states_are_half_of_the_coverage)
      create();
      `FAIL_UNLESS_STR_EQUAL(status(), "1 0 0.00")
      cycles("I.W");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 2 25.00")
      cycles(".S.A");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 4 50.00")
   `SVTEST_END

   `SVTEST(the_fourteen_pairs_of_cycles_are_the_other_half)
      create();
      // Every pair but the two in which valid is taken back: 4 + 4 + 2 + 4.
      cycles("IIWWAASSA.IA.IS.WI.WS.AI.AW");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 21 100.00")
   `SVTEST_END

   `SVTEST(one_pair_is_one_fourteenth_of_its_half)
      create();
      cycles("AA");
      // One state of four, and the back-to-back pair of fourteen pairs.
      `FAIL_UNLESS_STR_EQUAL(status(), "1 2 16.07")
   `SVTEST_END

   `SVTEST(valid_taken_back_during_a_stall_is_not_part_of_the_coverage)
      create();
      cycles("SI.SW");
      // Three states of four and no pair.
      `FAIL_UNLESS_STR_EQUAL(status(), "1 4 37.50")
   `SVTEST_END

   `SVTEST(no_pair_is_counted_across_a_reset)
      create();
      cycles("A.A");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 2 12.50")
   `SVTEST_END

   `SVTEST(write_counts_pairs_and_no_pair_across_a_reset_also_between_two_edges)
      create();
      records("AA");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 2 16.07")
      create();
      records("A.-A");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 2 12.50")
      create();
      records("Aa");
      `FAIL_UNLESS_STR_EQUAL(status(), "1 2 12.50")
   `SVTEST_END
`endif

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_coverage_unit_test
