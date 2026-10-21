// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_catcher_unit_test.sv
//
// SVUnit tests of hexk_report_catcher.
// One catcher is registered for the whole simulation and cleared before every test. Each
// test reports real messages through the UVM macros and looks at two things: what the
// catcher counted, and how the severity counts of the UVM report server moved, which shows
// whether a message was demoted or passed through. The unexpected errors that some tests
// report on purpose, and the verdicts of check_expectations, stay in the log as errors.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_report_catcher.

`include "svunit_defines.svh"

module hexk_report_catcher_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_check_stats;
   `include "uvm_macros.svh"

   string              name = "hexk_report_catcher_ut";
   svunit_testcase     svunit_ut;

   hexk_report_catcher catcher;
   int                 infos_at_start;
   int                 warnings_at_start;
   int                 errors_at_start;
   int                 missing_at_start;
   int                 excess_at_start;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      uvm_report_server server = uvm_report_server::get_server();
      svunit_ut.setup();
      catcher.clear();
      infos_at_start    = server.get_severity_count(UVM_INFO);
      warnings_at_start = server.get_severity_count(UVM_WARNING);
      errors_at_start   = server.get_severity_count(UVM_ERROR);
      missing_at_start  = server.get_id_count("HEXK_CATCHER_MISSING");
      excess_at_start   = server.get_id_count("HEXK_CATCHER_EXCESS");
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Reports one message through the UVM macro of the given severity.
   function automatic void emit(uvm_severity severity, string id, string text = "text");
      case (severity)
         UVM_INFO:    `uvm_info(id, text, UVM_NONE)
         UVM_WARNING: `uvm_warning(id, text)
         UVM_ERROR:   `uvm_error(id, text)
         default:     `uvm_fatal(id, text)
      endcase
   endfunction : emit

   // Messages the UVM report server counted since the start of the test, as "<infos> <warnings> <errors>".
   function automatic string counted();
      uvm_report_server server = uvm_report_server::get_server();
      return $sformatf(
          "%0d %0d %0d",
          server.get_severity_count(
              UVM_INFO
          ) - infos_at_start,
          server.get_severity_count(
              UVM_WARNING
          ) - warnings_at_start,
          server.get_severity_count(
              UVM_ERROR
          ) - errors_at_start
      );
   endfunction : counted

   // Verdicts of check_expectations since the start of the test, as "<missing> <excess>".
   function automatic string verdicts();
      uvm_report_server server = uvm_report_server::get_server();
      return $sformatf(
          "%0d %0d",
          server.get_id_count(
              "HEXK_CATCHER_MISSING"
          ) - missing_at_start,
          server.get_id_count(
              "HEXK_CATCHER_EXCESS"
          ) - excess_at_start
      );
   endfunction : verdicts

   // Makes the last message before a check come from a reporter that ignores the verdicts of a catcher.
   function automatic void report_from_a_muted_reporter();
      uvm_report_object muted = new("ut_muted_reporter");
      muted.set_report_id_action("HEXK_CATCHER_MISSING", UVM_NO_ACTION);
      muted.set_report_id_action("HEXK_CATCHER_EXCESS", UVM_NO_ACTION);
      // FAC-9 waived: `uvm_info_context of UVM 1.2 does not elaborate cleanly with slang (an int as a condition).
      muted.uvm_report_info("UT_LAST", "the last message before the check", UVM_NONE);
   endfunction : report_from_a_muted_reporter

   // Expects two failures of the check UT_CHECK with expect_check(), then lets the check fail twice, with its
   // error, as a check macro would: "<failures beyond the allowance> <checks failed>".
   function automatic string expected_check_failures();
      int unsigned unexpected_before = hexk_check_stats::num_unexpected_failures();
      catcher.expect_check("UT_CHECK", 2);
      repeat (2) begin
         hexk_check_stats::record_fail("UT_CHECK");
         emit(UVM_ERROR, "UT_CHECK");
      end
      return $sformatf(
          "%0d %0d",
          hexk_check_stats::num_unexpected_failures() - unexpected_before,
          hexk_check_stats::num_failed(
              "UT_CHECK"
          )
      );
   endfunction : expected_check_failures

   // expect_check() of an ID with characters that are operators of an expression, and a rule for an ID that the
   // expression would match; one error of each.
   function automatic void expected_check_with_operators();
      catcher.expect_check("UT.ID[0]", 1);
      catcher.expect_msg("^UTXID0$", UVM_ERROR, "", 1);
      emit(UVM_ERROR, "UTXID0");
      emit(UVM_ERROR, "UT.ID[0]");
   endfunction : expected_check_with_operators

   // A catcher of add_to() on one reporter that expects UT_SCOPED once, and the error UT_SCOPED from another reporter
   // and from that one: "<caught by the catcher of the reporter> <infos warnings errors>". The error of the other
   // reporter passes through.
   function automatic string scoped_catcher();
      uvm_report_object   client = new("ut_client");
      uvm_report_object   other = new("ut_other");
      hexk_report_catcher scoped = hexk_report_catcher::add_to(client);
      scoped.expect_msg("^UT_SCOPED$");
      // FAC-9 waived: `uvm_error_context of UVM 1.2 does not elaborate cleanly with slang (an int as a condition).
      other.uvm_report_error("UT_SCOPED", "from another reporter", UVM_NONE);
      client.uvm_report_error("UT_SCOPED", "from the reporter of the catcher", UVM_NONE);
      scoped.check_expectations();
      return $sformatf("%0d %s", scoped.get_count("^UT_SCOPED$"), counted());
   endfunction : scoped_catcher

   // A catcher of its own, created with add_global(), with an expectation that is never met; check_unchecked()
   // checks it once, and a second call leaves it alone.
   function automatic void unchecked_global_catcher();
      hexk_report_catcher own = hexk_report_catcher::add_global();
      own.expect_msg("^UT_NEVER_SEEN$");
      hexk_report_catcher::check_unchecked();
      hexk_report_catcher::check_unchecked();
      own.clear();
   endfunction : unchecked_global_catcher

   // add_to() without a component, with its fatal expected by the catcher of the suite: "<returned null> <caught>".
   function automatic string catcher_without_a_client();
      hexk_report_catcher none;
      catcher.expect_msg("^HEXK_CATCHER_CLIENT$", UVM_FATAL);
      none = hexk_report_catcher::add_to(null);
      return $sformatf("%0d %0d", none == null, catcher.get_count("^HEXK_CATCHER_CLIENT$", UVM_FATAL));
   endfunction : catcher_without_a_client

   // Decimal text of a count kept by the catcher.
   function automatic string caught(string id_regex, uvm_severity severity = UVM_ERROR);
      return $sformatf("%0d", catcher.get_count(id_regex, severity));
   endfunction : caught

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(an_expected_error_becomes_an_info)
      catcher.expect_msg("^UT_EXPECTED$");
      emit(UVM_ERROR, "UT_EXPECTED");
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 0 0")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_EXPECTED$"), "1")
   `SVTEST_END

   `SVTEST(an_error_that_matches_no_rule_passes_through)
      catcher.expect_msg("^UT_EXPECTED$");
      emit(UVM_ERROR, "UT_OTHER");
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 0 1")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_EXPECTED$"), "0")
   `SVTEST_END

   `SVTEST(the_id_expression_matches_anywhere_unless_anchored)
      catcher.expect_msg("EXPECTED");
      emit(UVM_ERROR, "UT_EXPECTED_TOO");
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 0 0")
   `SVTEST_END

   `SVTEST(the_severity_must_match)
      catcher.expect_msg("^UT_EXPECTED$", UVM_WARNING);
      emit(UVM_ERROR, "UT_EXPECTED");
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 0 1")
      emit(UVM_WARNING, "UT_EXPECTED");
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 0 1")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_EXPECTED$", UVM_WARNING), "1")
   `SVTEST_END

   `SVTEST(the_text_expression_narrows_a_rule)
      catcher.expect_msg("^UT_EXPECTED$", UVM_ERROR, "act=.* exp=");
      emit(UVM_ERROR, "UT_EXPECTED", "act=4 exp=5");
      emit(UVM_ERROR, "UT_EXPECTED", "something else");
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 0 1")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_EXPECTED$"), "1")
   `SVTEST_END

   `SVTEST(the_first_matching_rule_wins)
      catcher.expect_msg("^UT_", UVM_ERROR, "", 1, -1, UVM_WARNING);
      catcher.expect_msg("^UT_EXPECTED$");
      emit(UVM_ERROR, "UT_EXPECTED");
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 1 0")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_"), "1")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_EXPECTED$"), "0")
   `SVTEST_END

   `SVTEST(an_expected_fatal_does_not_end_the_simulation)
      catcher.expect_msg("^UT_FATAL$", UVM_FATAL);
      emit(UVM_FATAL, "UT_FATAL");
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 0 0")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_FATAL$", UVM_FATAL), "1")
   `SVTEST_END

   `SVTEST(demote_changes_the_severity)
      catcher.demote("^UT_NOISY$", UVM_WARNING, UVM_INFO);
      catcher.demote("^UT_SOFT$", UVM_ERROR, UVM_WARNING, "tolerated");
      emit(UVM_WARNING, "UT_NOISY");
      emit(UVM_ERROR, "UT_SOFT", "tolerated here");
      emit(UVM_ERROR, "UT_SOFT", "not this one");
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 1 1")
   `SVTEST_END

   `SVTEST(a_demotion_is_not_checked_as_an_expectation)
      catcher.demote("^UT_NEVER$", UVM_ERROR, UVM_INFO);
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 0 0")
   `SVTEST_END

   `SVTEST(check_expectations_is_quiet_when_all_are_met)
      catcher.expect_msg("^UT_EXPECTED$", UVM_ERROR, "", 2, 2);
      emit(UVM_ERROR, "UT_EXPECTED");
      emit(UVM_ERROR, "UT_EXPECTED");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(counted(), "2 0 0")
   `SVTEST_END

   `SVTEST(check_expectations_reports_a_missing_message)
      catcher.expect_msg("^UT_NEVER$");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "1 0")
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 0 1")
   `SVTEST_END

   `SVTEST(check_expectations_reports_too_many_messages)
      catcher.expect_msg("^UT_ONCE$", UVM_ERROR, "", 1, 1);
      emit(UVM_ERROR, "UT_ONCE");
      emit(UVM_ERROR, "UT_ONCE");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 1")
      `FAIL_UNLESS_STR_EQUAL(counted(), "2 0 1")
   `SVTEST_END

   `SVTEST(the_shortest_call_expects_exactly_one_message)
      catcher.expect_msg("^UT_TWICE$");
      emit(UVM_ERROR, "UT_TWICE");
      emit(UVM_ERROR, "UT_TWICE");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 1")
   `SVTEST_END

   `SVTEST(no_limit_allows_any_number_above_the_minimum)
      catcher.expect_msg("^UT_MANY$", UVM_ERROR, "", 1, hexk_report_catcher::NO_LIMIT);
      emit(UVM_ERROR, "UT_MANY");
      emit(UVM_ERROR, "UT_MANY");
      emit(UVM_ERROR, "UT_MANY");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 0")
      `FAIL_UNLESS_STR_EQUAL(counted(), "3 0 0")
   `SVTEST_END

   `SVTEST(expect_check_expects_the_messages_and_allows_the_failures_of_a_check)
      `FAIL_UNLESS_STR_EQUAL(expected_check_failures(), "0 2")
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 0")
      `FAIL_UNLESS_STR_EQUAL(counted(), "2 0 0")
   `SVTEST_END

   `SVTEST(expect_check_compares_the_id_as_text)
      expected_check_with_operators();
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 0")
      `FAIL_UNLESS_STR_EQUAL(counted(), "2 0 0")
   `SVTEST_END

   `SVTEST(a_catcher_added_to_a_reporter_counts_only_its_messages)
      `FAIL_UNLESS_STR_EQUAL(scoped_catcher(), "1 1 0 1")
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 0")
   `SVTEST_END

   `SVTEST(check_unchecked_checks_a_global_catcher_once)
      unchecked_global_catcher();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "1 0")
   `SVTEST_END

   `SVTEST(a_maximum_of_zero_forbids_a_message)
      catcher.expect_msg("^UT_FORBIDDEN$", UVM_WARNING, "", 0, 0);
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 0")
      emit(UVM_WARNING, "UT_FORBIDDEN");
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 1")
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 2")
   `SVTEST_END

   `SVTEST(an_excess_after_the_check_is_reported_at_once)
      catcher.expect_msg("^UT_LATE$");
      emit(UVM_ERROR, "UT_LATE");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 0")
      emit(UVM_ERROR, "UT_LATE");
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "0 1")
      `FAIL_UNLESS_STR_EQUAL(counted(), "2 0 1")
   `SVTEST_END

   `SVTEST(add_to_needs_a_component)
      `FAIL_UNLESS_STR_EQUAL(catcher_without_a_client(), "1 1")
      `FAIL_UNLESS_STR_EQUAL(counted(), "1 0 0")
   `SVTEST_END

   `SVTEST(the_verdict_of_the_catcher_cannot_be_caught_by_its_own_rules)
      catcher.expect_msg("^UT_NEVER$");
      catcher.expect_msg(".*", UVM_ERROR, "", 0);
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "1 0")
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 0 1")
   `SVTEST_END

   `SVTEST(a_verdict_does_not_depend_on_the_reporter_of_the_last_message)
      catcher.expect_msg("^UT_NEVER$");
      catcher.expect_msg("^UT_LAST$", UVM_INFO, "", 0, 0);
      report_from_a_muted_reporter();
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(verdicts(), "1 1")
   `SVTEST_END

   `SVTEST(clear_removes_every_rule)
      catcher.expect_msg("^UT_EXPECTED$");
      catcher.clear();
      emit(UVM_ERROR, "UT_EXPECTED");
      catcher.check_expectations();
      `FAIL_UNLESS_STR_EQUAL(counted(), "0 0 1")
      `FAIL_UNLESS_STR_EQUAL(caught("^UT_EXPECTED$"), "0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_report_catcher_unit_test
