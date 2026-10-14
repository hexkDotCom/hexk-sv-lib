// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_base_test.sv
//
// Optional common base test: the level between uvm_test and the base test of a block. It
// sets up what every test of every block needs and nothing that belongs to one block:
// the report server, if the testbench top did not install it; the knobs, with the knobs
// perf_mode, coverage and hexk_require_checks; the objection aggregator, the end-of-test
// registry and the watchdog; phase objections that do not propagate; the check statistics
// in the log; and one last line, TEST PASSED or TEST FAILED, where passing needs no error, no
// failed check beyond those that hexk_check_stats::expect_failures() allowed (also when the
// message of the check was demoted or switched off) and, unless switched off, at least one
// executed check: a check macro, a comparison of a scoreboard, or what another checker counts
// with hexk_check_stats::record_pass() and record_fail().
// Each policy can be switched off in the constructor of a block base test: install_report_server
// keeps a report server of the project, stop_objection_propagation keeps the propagation of UVM,
// require_checks lets a test without counted checks pass.
// A block base test extends it and overrides the hooks do_type_overrides(), define_knobs()
// and modify_cfg(); it builds its env in its own build_phase after super.build_phase().
//
//! @module    hexk_base_test
//! @since     0.7.0
//! @stability experimental
//! @serves    TST-1 TST-2 TST-6 OBJ-5 OBJ-7
//! @emits     HEXK_TEST_RESULT:info HEXK_TEST_CHECKS:info HEXK_TEST_NO_CHECKS:error HEXK_TEST_CHECK_FAILED:error
//! @plusargs  +perf_mode +coverage +hexk_require_checks

`ifndef HEXK_BASE_TEST_SV
`define HEXK_BASE_TEST_SV

class hexk_base_test extends uvm_test;

   // The knobs of the simulation; locked at the end of build_phase.
   hexk_knobs                knobs;

   // Keeps the run-time phases alive while registered objects are busy.
   hexk_objection_aggregator objections;

   // Runs the end-of-test checks of objects that are not components.
   hexk_eot_registry         eot_registry;

   // Ends a test that hangs; its limits can be set in build_phase of a derived test.
   hexk_watchdog             watchdog;

   // When 1, a test passes only if at least one check was executed; +hexk_require_checks overrides it.
   bit                       require_checks             = 1;

   // When 1, build_phase installs hexk_report_server unless it is installed already; 0 keeps any report server.
   bit                       install_report_server      = 1;

   // When 1, start_of_simulation_phase stops the objections of the run phase and of the run-time phases from
   // propagating up the hierarchy; 0 leaves the propagation of UVM as it is.
   bit                       stop_objection_propagation = 1;

   `uvm_component_utils(hexk_base_test)

   // Creates the test; everything else happens in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Hook: factory overrides of the test; called first in build_phase, before anything is created.
   virtual function void do_type_overrides();
   endfunction : do_type_overrides

   // Hook: knobs of the block or of the test; called in build_phase before the knobs are locked.
   virtual function void define_knobs();
   endfunction : define_knobs

   // Hook: changes to the cfg of the block before it is randomized; called last in build_phase, when knobs can be read.
   virtual function void modify_cfg();
   endfunction : modify_cfg

   // UVM callback: sets up report server, knobs, aggregator, registry and watchdog, and calls the hooks.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      do_type_overrides();
      if (install_report_server && hexk_report_server::get_installed() == null) begin
         hexk_report_cfg report_cfg = hexk_report_cfg::type_id::create("report_cfg");
         report_cfg.apply_plusargs();
         void'(hexk_report_server::install(report_cfg));
      end
      knobs = hexk_knobs::get();
      if (!knobs.has("perf_mode")) begin
         knobs.add_bit("perf_mode", 0, "performance mode: every delay of the delay generators is 0");
      end
      if (!knobs.has("coverage")) begin
         knobs.add_bit("coverage", 1, "functional coverage: the covergroups of the library macro are created");
      end
      if (!knobs.has("hexk_require_checks")) begin
         knobs.add_bit("hexk_require_checks", require_checks, "a test passes only if at least one check was executed");
      end
      define_knobs();
      objections          = hexk_objection_aggregator::type_id::create("objections", this);
      watchdog            = hexk_watchdog::type_id::create("watchdog", this);
      watchdog.aggregator = objections;
      eot_registry        = hexk_eot_registry::get();
      knobs.lock();
      require_checks = knobs.get_bit("hexk_require_checks");
      modify_cfg();
   endfunction : build_phase

   // UVM callback: stops the objections of the run-time phases from propagating up the hierarchy, unless
   // stop_objection_propagation is 0.
   function void start_of_simulation_phase(uvm_phase phase);
      uvm_domain common = uvm_domain::get_common_domain();
      uvm_domain runtime = uvm_domain::get_uvm_domain();
      super.start_of_simulation_phase(phase);
      if (!stop_objection_propagation) begin
         return;
      end
      stop_propagation(common.find(uvm_run_phase::get()));
      stop_propagation(runtime.find(uvm_pre_reset_phase::get()));
      stop_propagation(runtime.find(uvm_reset_phase::get()));
      stop_propagation(runtime.find(uvm_post_reset_phase::get()));
      stop_propagation(runtime.find(uvm_pre_configure_phase::get()));
      stop_propagation(runtime.find(uvm_configure_phase::get()));
      stop_propagation(runtime.find(uvm_post_configure_phase::get()));
      stop_propagation(runtime.find(uvm_pre_main_phase::get()));
      stop_propagation(runtime.find(uvm_main_phase::get()));
      stop_propagation(runtime.find(uvm_post_main_phase::get()));
      stop_propagation(runtime.find(uvm_pre_shutdown_phase::get()));
      stop_propagation(runtime.find(uvm_shutdown_phase::get()));
      stop_propagation(runtime.find(uvm_post_shutdown_phase::get()));
   endfunction : start_of_simulation_phase

   // UVM callback: reports the statistics of the check macros.
   function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("HEXK_TEST_CHECKS", {"\n", hexk_check_stats::summary()}, UVM_LOW)
   endfunction : report_phase

   // UVM callback: reports the last line of the test, TEST PASSED or TEST FAILED.
   function void final_phase(uvm_phase phase);
      super.final_phase(phase);
      if (num_errors() == 0 && require_checks && hexk_check_stats::num_checks() == 0) begin
         `uvm_error("HEXK_TEST_NO_CHECKS", {"no check was executed, so the test proved nothing; use the check macros, ",
                                            "or clear require_checks for a test that checks in another way"})
      end
      // A failed check whose error was demoted or switched off is still a failure, unless the test expected it.
      if (num_errors() == 0 && hexk_check_stats::num_unexpected_failures() != 0) begin
         `uvm_error("HEXK_TEST_CHECK_FAILED",
                    $sformatf(
                        "%0d checks failed although their messages counted no error; %s",
                        hexk_check_stats::num_unexpected_failures(),
                        "declare a failure that the test wants with hexk_check_stats::expect_failures(id, count)"))
      end
      `uvm_info("HEXK_TEST_RESULT", result_text(), UVM_NONE)
   endfunction : final_phase

   // 1 when there was no error or fatal so far, no failed check beyond the expected ones and, if require_checks is
   // set, at least one check was executed.
   function bit has_passed();
      return num_errors() == 0 && hexk_check_stats::num_unexpected_failures() == 0 &&
          (!require_checks || hexk_check_stats::num_checks() != 0);
   endfunction : has_passed

   // The last line of the test: "TEST PASSED" or "TEST FAILED" with the counts behind the verdict.
   function string result_text();
      uvm_report_server server = uvm_report_server::get_server();
      int unsigned errors = server.get_severity_count(UVM_ERROR);
      int unsigned fatals = server.get_severity_count(UVM_FATAL);
      int unsigned unexpected = hexk_check_stats::num_unexpected_failures();
      string counts = $sformatf(
          "%0d errors, %0d fatals, %0d checks executed", errors, fatals, hexk_check_stats::num_checks()
      );
      if (unexpected != 0) begin
         counts = $sformatf("%s, %0d failed without an error", counts, unexpected);
      end
      if (has_passed()) begin
         return {"TEST PASSED (", counts, ")"};
      end
      return {"TEST FAILED (", counts, ")"};
   endfunction : result_text

   // Number of errors and fatals that the report server has counted.
   local function int num_errors();
      uvm_report_server server = uvm_report_server::get_server();
      return server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
   endfunction : num_errors

   // Switches the propagation of the objection of one phase off.
   local function void stop_propagation(uvm_phase node);
      uvm_objection objection;
      if (node == null) begin
         return;
      end
      objection = node.get_objection();
      if (objection != null) begin
         objection.set_propagate_mode(0);
      end
   endfunction : stop_propagation

endclass : hexk_base_test

`endif  // HEXK_BASE_TEST_SV
