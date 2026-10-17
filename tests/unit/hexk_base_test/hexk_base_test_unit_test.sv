// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_base_test_unit_test.sv
//
// SVUnit tests of hexk_base_test.
// The UVM phases do not run in a unit test simulation, so each test creates a test component
// of a class derived from hexk_base_test and calls its build_phase, start_of_simulation_phase
// and final_phase itself. The derived class notes the order in which its hooks are called.
// The verdict depends on the error counts of the report server and on the check statistics,
// which the whole simulation shares: the tests save them, set them to what they need and put
// them back. A small report catcher keeps the text of the result line.
// A report server is installed before the first test, so the tests exercise the path "the
// testbench top installed it already"; the other path, and hexk_tb_top_inc.svh, are covered
// by the example, which was run by hand.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_base_test.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_base_test_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_base_test;
   import hexk_uvm_pkg::hexk_check_stats;
   import hexk_uvm_pkg::hexk_eot_registry;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_report_server;
   `include "uvm_macros.svh"

   // Cfg of the block test: three random knobs in the same range.
   class hexk_ut_block_cfg extends uvm_object;
      rand int unsigned pinned;
      rand int unsigned plain;
      rand int unsigned assigned_after;

      `uvm_object_utils(hexk_ut_block_cfg)

      constraint range_cstr {
         pinned inside {[10 : 20]};
         plain inside {[10 : 20]};
         assigned_after inside {[10 : 20]};
      }

      function new(string cfg_name = "hexk_ut_block_cfg");
         super.new(cfg_name);
      endfunction : new
   endclass : hexk_ut_block_cfg

   // Test that notes the order of its hooks and defines one knob. Before the randomization of its cfg it pins one
   // knob and assigns another plainly; after it, it assigns a third one.
   class hexk_ut_block_test extends hexk_base_test;
      string            hook_log;
      bit               knobs_readable_in_modify_cfg;
      hexk_ut_block_cfg cfg;

      function new(string component_name, uvm_component parent);
         super.new(component_name, parent);
      endfunction : new

      virtual function void do_type_overrides();
         hook_log = {hook_log, "overrides "};
      endfunction : do_type_overrides

      virtual function void define_knobs();
         hook_log = {hook_log, "knobs "};
         knobs.add_int("ut_block_items", 5, "items of the block test");
      endfunction : define_knobs

      virtual function uvm_object create_cfg();
         hook_log = {hook_log, "create "};
         cfg      = hexk_ut_block_cfg::type_id::create("cfg");
         return cfg;
      endfunction : create_cfg

      virtual function void modify_cfg();
         hook_log                     = {hook_log, "cfg "};
         knobs_readable_in_modify_cfg = (knobs.get_int("ut_block_items") == 5);
         cfg.pinned.rand_mode(0);
         cfg.pinned = 15;
         cfg.plain  = 99;
      endfunction : modify_cfg

      virtual function void modify_randomized_cfg();
         hook_log           = {hook_log, "randomized "};
         cfg.assigned_after = 99;
      endfunction : modify_randomized_cfg
   endclass : hexk_ut_block_test

   // Keeps the text of the latest HEXK_TEST_RESULT message.
   class hexk_ut_result_catcher extends uvm_report_catcher;
      string text;

      function new(string catcher_name = "hexk_ut_result_catcher");
         super.new(catcher_name);
      endfunction : new

      function action_e catch();
         if (get_id() == "HEXK_TEST_RESULT") begin
            text = get_message();
         end
         return THROW;
      endfunction : catch
   endclass : hexk_ut_result_catcher

   string                 name = "hexk_base_test_ut";
   svunit_testcase        svunit_ut;

   hexk_report_catcher    catcher;
   hexk_ut_result_catcher result_catcher;
   hexk_ut_block_test     test;
   int unsigned           created;
   int                    saved_errors;
   int                    saved_fatals;

   function automatic void build();
      svunit_ut      = new(name);
      catcher        = hexk_report_catcher::add_global();
      result_catcher = new();
      uvm_report_cb::add(null, result_catcher);
      if (hexk_report_server::get_installed() == null) begin
         void'(hexk_report_server::install());
      end
   endfunction : build

   // Every test gets a fresh test component, fresh knobs and empty check statistics.
   task automatic setup();
      uvm_report_server server = uvm_report_server::get_server();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_TEST_NO_CHECKS$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_TEST_CHECK_FAILED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^UT_BASE_FAIL$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_TEST_WARNING$", UVM_ERROR, "", 0, -1, UVM_INFO);
      hexk_knobs::reset_for_test();
      hexk_check_stats::reset_for_test();
      saved_errors = server.get_severity_count(UVM_ERROR);
      saved_fatals = server.get_severity_count(UVM_FATAL);
      server.set_severity_count(UVM_ERROR, 0);
      server.set_severity_count(UVM_FATAL, 0);
      created++;
      test                = new($sformatf("ut_base_test_%0d", created), null);
      result_catcher.text = "";
   endtask : setup

   task automatic teardown();
      uvm_report_server server = uvm_report_server::get_server();
      svunit_ut.teardown();
      server.set_severity_count(UVM_ERROR, saved_errors);
      server.set_severity_count(UVM_FATAL, saved_fatals);
      hexk_knobs::reset_for_test();
      hexk_check_stats::reset_for_test();
      catcher.clear();
   endtask : teardown

   // Which of the helpers exist after build_phase, as "<objections> <watchdog> <registry> <connected>".
   function automatic string helpers();
      return $sformatf(
          "%0d %0d %0d %0d",
          test.objections != null,
          test.watchdog != null,
          test.eot_registry == hexk_eot_registry::get(),
          test.watchdog != null && test.watchdog.aggregator == test.objections
      );
   endfunction : helpers

   // Whether the knobs exist, as "<perf_mode> <coverage> <hexk_require_checks> <ut_block_items>".
   function automatic string knobs_defined();
      hexk_knobs knobs = hexk_knobs::get();
      return $sformatf(
          "%0d %0d %0d %0d",
          knobs.has(
              "perf_mode"
          ),
          knobs.has(
              "coverage"
          ),
          knobs.has(
              "hexk_require_checks"
          ),
          knobs.has(
              "ut_block_items"
          )
      );
   endfunction : knobs_defined

   // Executes passing checks.
   function automatic void run_checks(int unsigned count);
      int unsigned value = 3;
      repeat (count) begin
         `hexk_check_eq(value, 3, "UT_BASE_CHECK")
      end
   endfunction : run_checks

   // Executes one failing check whose error the catcher of the test demotes, so that it counts no error.
   function automatic void run_failing_check();
      int unsigned value = 4;
      `hexk_check_eq(value, 3, "UT_BASE_FAIL")
   endfunction : run_failing_check

   // What get_verdict() gives: "<1 when a hexk_base_test was built> <verdict>".
   function automatic string verdict();
      hexk_base_test::verdict_e found;
      bit                       known = hexk_base_test::get_verdict(found);
      return $sformatf("%0d %s", known, found.name());
   endfunction : verdict

   // A banner of banner_text() with the counts "c", its blocks shown as '#': "<number of lines> | <second line> |
   // <last line>"; the first line is empty or the colour codes, the second the top row of the letters.
   function automatic string banner(hexk_base_test::verdict_e found, bit color, int unsigned face = 0);
      string text = hexk_base_test::banner_text(found, "c", color, face);
      string lines[$];
      hexk_str::split(hexk_str::replace(text, "\342\226\210", "#"), lines, "\n");
      return $sformatf("%0d | %s | %s", lines.size(), lines[1], lines[lines.size()-1]);
   endfunction : banner

   // The colour codes at the start of a coloured banner and its face, the line before the last:
   // "<codes> <face> <1 when a '#' is left>"; the face is picked modulo the number of faces.
   function automatic string banner_edges(hexk_base_test::verdict_e found, int unsigned face);
      string text = hexk_base_test::banner_text(found, "c", 1, face);
      string lines[$];
      hexk_str::split(text, lines, "\n");
      return $sformatf(
          "%s %s %0d",
          text.substr(
              0, 8
          ),
          hexk_str::replace(
              lines[lines.size()-2], "\033[0m", ""
          ),
          hexk_str::contains(
              text, "#"
          )
      );
   endfunction : banner_edges

   // Issues a warning with the given ID, as a component of the testbench would.
   function automatic void warn(string id);
      `uvm_warning(id, "a warning of the unit test")
   endfunction : warn

   // Number of HEXK_TEST_WARNING errors in this test.
   function automatic string warning_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_TEST_WARNING$"));
   endfunction : warning_errors

   // A test with fail_on_warnings set to policy that allows UT_ALLOWED and sees UT_ALLOWED and UT_UNEXPECTED:
   // "<HEXK_TEST_WARNING errors> <unexpected warnings counted>".
   function automatic string warnings_with_policy(bit policy);
      test.fail_on_warnings = policy;
      test.allow_warning("^UT_ALLOWED$");
      test.build_phase(null);
      warn("UT_ALLOWED");
      warn("UT_UNEXPECTED");
      test.report_phase(null);
      return $sformatf("%s %0d", warning_errors(), test.warnings.num_unexpected());
   endfunction : warnings_with_policy

   // Number of HEXK_TEST_CHECK_FAILED errors in this test.
   function automatic string check_failed_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_TEST_CHECK_FAILED$"));
   endfunction : check_failed_errors

   // Makes the report server count errors as if they had been reported.
   function automatic void pretend_errors(int errors, int fatals = 0);
      uvm_report_server server = uvm_report_server::get_server();
      server.set_severity_count(UVM_ERROR, errors);
      server.set_severity_count(UVM_FATAL, fatals);
   endfunction : pretend_errors

   // Clears the member that makes a test without checks fail.
   function automatic void do_not_require_checks();
      test.require_checks = 0;
   endfunction : do_not_require_checks

   // Number of HEXK_TEST_NO_CHECKS errors in this test.
   function automatic string no_check_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_TEST_NO_CHECKS$"));
   endfunction : no_check_errors

   // Whether the objection of the run phase propagates, as "0" or "1".
   function automatic string run_phase_propagates();
      uvm_domain    common = uvm_domain::get_common_domain();
      uvm_phase     run_node = common.find(uvm_run_phase::get());
      uvm_objection objection = run_node.get_objection();
      return $sformatf("%0d", objection.get_propagate_mode());
   endfunction : run_phase_propagates

   // With stop_objection_propagation at 0, whether the objection of the run phase still propagates after
   // start_of_simulation_phase: "0" or "1". The mode of the simulation is restored afterwards.
   function automatic string propagation_kept();
      uvm_domain    common = uvm_domain::get_common_domain();
      uvm_phase     run_node = common.find(uvm_run_phase::get());
      uvm_objection objection = run_node.get_objection();
      bit           saved = objection.get_propagate_mode();
      string        kept;
      objection.set_propagate_mode(1);
      test.stop_objection_propagation = 0;
      test.build_phase(null);
      test.start_of_simulation_phase(null);
      kept = run_phase_propagates();
      objection.set_propagate_mode(saved);
      return kept;
   endfunction : propagation_kept

   // With install_report_server at 0 and a plain UVM report server installed, whether build_phase left it
   // in place: "<hexk_report_server installed after the build>". The report server of the suite is put back.
   function automatic string report_server_kept();
      uvm_report_server         saved = uvm_report_server::get_server();
      uvm_default_report_server plain = new("ut_plain_server");
      bit                       installed;
      uvm_report_server::set_server(plain);
      test.install_report_server = 0;
      test.build_phase(null);
      installed = (hexk_report_server::get_installed() != null);
      uvm_report_server::set_server(saved);
      return $sformatf("%0d", installed);
   endfunction : report_server_kept

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(build_phase_creates_the_helpers_and_connects_the_watchdog)
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL(helpers(), "1 1 1 1")
   `SVTEST_END

   `SVTEST(build_phase_defines_the_knobs_and_locks_them)
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL(knobs_defined(), "1 1 1 1")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.knobs.get_bit("perf_mode")), "0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.knobs.get_bit("coverage")), "1")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.knobs.get_bit("hexk_require_checks")), "1")
   `SVTEST_END

   `SVTEST(the_hooks_are_called_in_order_and_modify_cfg_can_read_knobs)
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL(test.hook_log, "overrides knobs create cfg randomized ")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.knobs_readable_in_modify_cfg), "1")
   `SVTEST_END

   `SVTEST(the_cfg_is_randomized_between_modify_cfg_and_modify_randomized_cfg)
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d %0d %0d %0d", test.block_cfg == test.cfg, test.cfg.pinned,
                                       test.cfg.plain inside {[10 : 20]}, test.cfg.assigned_after), "1 15 1 99")
   `SVTEST_END

   `SVTEST(require_checks_set_before_the_build_is_the_default_of_its_knob)
      do_not_require_checks();
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.knobs.get_bit("hexk_require_checks")), "0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.require_checks), "0")
   `SVTEST_END

   `SVTEST(start_of_simulation_stops_the_propagation_of_phase_objections)
      test.build_phase(null);
      test.start_of_simulation_phase(null);
      `FAIL_UNLESS_STR_EQUAL(run_phase_propagates(), "0")
   `SVTEST_END

   `SVTEST(without_stop_objection_propagation_the_propagation_of_uvm_stays)
      `FAIL_UNLESS_STR_EQUAL(propagation_kept(), "1")
   `SVTEST_END

   `SVTEST(without_install_report_server_another_report_server_stays)
      `FAIL_UNLESS_STR_EQUAL(report_server_kept(), "0")
   `SVTEST_END

   `SVTEST(a_test_with_checks_and_without_errors_passes)
      test.build_phase(null);
      run_checks(3);
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(result_catcher.text, "TEST PASSED (0 errors, 0 fatals, 3 checks executed)")
      `FAIL_UNLESS_STR_EQUAL(no_check_errors(), "0")
   `SVTEST_END

   `SVTEST(a_test_with_errors_fails)
      test.build_phase(null);
      run_checks(3);
      pretend_errors(2);
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(result_catcher.text, "TEST FAILED (2 errors, 0 fatals, 3 checks executed)")
      `FAIL_UNLESS_STR_EQUAL(no_check_errors(), "0")
   `SVTEST_END

   `SVTEST(a_test_with_a_fatal_fails)
      test.build_phase(null);
      run_checks(1);
      pretend_errors(0, 1);
      `FAIL_UNLESS_STR_EQUAL(test.result_text(), "TEST FAILED (0 errors, 1 fatals, 1 checks executed)")
   `SVTEST_END

   `SVTEST(a_test_without_checks_fails_with_an_error_of_its_own)
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.has_passed()), "0")
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(no_check_errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(result_catcher.text, "TEST FAILED (0 errors, 0 fatals, 0 checks executed)")
   `SVTEST_END

   `SVTEST(a_failed_check_whose_error_was_demoted_fails_the_test)
      test.build_phase(null);
      run_checks(2);
      run_failing_check();
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.has_passed()), "0")
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(check_failed_errors(), "1")
      `FAIL_UNLESS_STR_EQUAL(result_catcher.text,
         "TEST FAILED (0 errors, 0 fatals, 3 checks executed, 1 failed without an error)")
   `SVTEST_END

   `SVTEST(a_failed_check_that_reported_its_error_is_not_called_one_without_an_error)
      test.build_phase(null);
      run_checks(2);
      run_failing_check();
      pretend_errors(1);
      `FAIL_UNLESS_STR_EQUAL(test.result_text(), "TEST FAILED (1 errors, 0 fatals, 3 checks executed)")
   `SVTEST_END

   `SVTEST(a_failed_check_that_the_test_expects_lets_it_pass)
      test.build_phase(null);
      run_checks(2);
      hexk_check_stats::expect_failures("UT_BASE_FAIL");
      run_failing_check();
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(check_failed_errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(result_catcher.text, "TEST PASSED (0 errors, 0 fatals, 3 checks executed)")
      run_failing_check();
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.has_passed()), "0")
   `SVTEST_END

   `SVTEST(a_test_whose_final_phase_did_not_run_is_aborted)
      test.build_phase(null);
      run_checks(1);
      `FAIL_UNLESS_STR_EQUAL(verdict(), "1 HEXK_TEST_ABORTED")
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(verdict(), "1 HEXK_TEST_PASSED")
   `SVTEST_END

   `SVTEST(after_its_final_phase_a_test_with_errors_has_failed)
      test.build_phase(null);
      run_checks(1);
      pretend_errors(1);
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(verdict(), "1 HEXK_TEST_FAILED")
   `SVTEST_END

   `SVTEST(the_plain_banner_has_letters_of_hash_signs_and_the_line_with_the_counts)
      `FAIL_UNLESS_STR_EQUAL(banner(hexk_base_test::HEXK_TEST_PASSED, 0),
         "7 |     ######   #####  ####### ####### ####### ###### | SIMULATION PASSED (c)")
      `FAIL_UNLESS_STR_EQUAL(banner(hexk_base_test::HEXK_TEST_FAILED, 0),
         "7 |     #######  #####  ## ##      ####### ###### | SIMULATION FAILED (c)")
      `FAIL_UNLESS_STR_EQUAL(banner(hexk_base_test::HEXK_TEST_ABORTED, 0),
         "7 |      #####  ######   ######  ######  ######## ####### ###### | SIMULATION FAILED - ABORTED (c)")
   `SVTEST_END

   `SVTEST(the_colored_banner_has_blocks_a_face_and_resets_the_color)
      `FAIL_UNLESS_STR_EQUAL(banner(hexk_base_test::HEXK_TEST_FAILED, 1, 13),
         "8 |     #######  #####  ## ##      ####### ###### | SIMULATION FAILED (c)")
      `FAIL_UNLESS_STR_EQUAL(banner_edges(hexk_base_test::HEXK_TEST_FAILED, 13), "\033[31m\033[1m (._.) 0")
      `FAIL_UNLESS_STR_EQUAL(banner_edges(hexk_base_test::HEXK_TEST_PASSED, 14 + 9), "\033[32m\033[1m \342\234\214 0")
      // 14 faces for a pass and 20 otherwise: the index wraps to the first one, whose last line is shown.
      `FAIL_UNLESS_STR_EQUAL(banner_edges(hexk_base_test::HEXK_TEST_PASSED, 14),
         "\033[32m\033[1m (\342\214\220\342\226\240_\342\226\240) 0")
      `FAIL_UNLESS_STR_EQUAL(banner_edges(hexk_base_test::HEXK_TEST_ABORTED, 20),
         "\033[31m\033[1m \302\257\\_(\343\203\204)_/\302\257 0")
   `SVTEST_END

   `SVTEST(build_phase_gives_the_test_a_global_catcher)
      test.build_phase(null);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", test.catcher != null), "1")
   `SVTEST_END

   `SVTEST(with_fail_on_warnings_a_warning_that_was_not_allowed_is_an_error)
      `FAIL_UNLESS_STR_EQUAL(warnings_with_policy(1), "1 1")
   `SVTEST_END

   `SVTEST(without_fail_on_warnings_warnings_are_counted_but_not_errors)
      `FAIL_UNLESS_STR_EQUAL(warnings_with_policy(0), "0 1")
   `SVTEST_END

   `SVTEST(a_test_without_checks_passes_when_checks_are_not_required)
      do_not_require_checks();
      test.build_phase(null);
      test.final_phase(null);
      `FAIL_UNLESS_STR_EQUAL(no_check_errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(result_catcher.text, "TEST PASSED (0 errors, 0 fatals, 0 checks executed)")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_base_test_unit_test
