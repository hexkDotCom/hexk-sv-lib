// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_regex_unit_test.sv
//
// SVUnit tests of hexk_regex.
// Uses only the subset of POSIX extended regular expressions that the contract promises:
// literals, ".", character classes, "*", "+", "?", alternation, groups and the anchors.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM with its regex DPI code. Runs on Verilator with UVM 2020:
// make test SIM=verilator TEST=hexk_regex.

`include "svunit_defines.svh"

module hexk_regex_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_uvm_pkg::hexk_regex;

   string          name = "hexk_regex_ut";
   svunit_testcase svunit_ut;

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // "1" or "0" for hexk_regex::match.
   function automatic string match_text(string re, string s);
      return hexk_regex::match(re, s) ? "1" : "0";
   endfunction : match_text

   // "1" or "0" for is_match of a filter built from the two expressions.
   function automatic string passes(string include_re, string exclude_re, string s);
      hexk_regex filter = new(include_re, exclude_re);
      return filter.is_match(s) ? "1" : "0";
   endfunction : passes

   // "1" or "0" for matching s against the expression made from glob.
   function automatic string glob_matches(string glob, string s);
      return match_text(hexk_regex::glob_to_regex(glob), s);
   endfunction : glob_matches

   // The first expression and string for which a filter and hexk_regex::match() give different answers, with
   // the expression as include and as exclude expression; "" when they always agree. A filter matches an
   // expression without operators by a string comparison of its own.
   function automatic string filter_disagreement();
      string expressions[$] = '{
          "SB",
          "^SB",
          "SB$",
          "^SB$",
          "^$",
          "^",
          "$",
          "SB_MISMATCH",
          "S.B",
          "S\\.B",
          "^S[BC]$",
          "/SB/",
          "SB|DRV",
          "S*B",
          "(SB)",
          "S+B",
          "S?B"
      };
      string strings[$] = '{"", "SB", "xSB", "SBx", "xSBx", "S.B", "SxB", "B", "DRV", "SSB", "/SB/", "SB_MISMATCH"};
      hexk_regex include_filter;
      hexk_regex exclude_filter;
      bit expected;
      foreach (expressions[i]) begin
         include_filter = new(expressions[i]);
         exclude_filter = new("", expressions[i]);
         foreach (strings[k]) begin
            expected = hexk_regex::match(expressions[i], strings[k]);
            if (include_filter.is_match(
                    strings[k]
                ) != expected || exclude_filter.is_match(
                    strings[k]
                ) == expected) begin
               return $sformatf("'%s' on '%s'", expressions[i], strings[k]);
            end
         end
      end
      return "";
   endfunction : filter_disagreement

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(match_finds_the_expression_anywhere_in_the_string)
      `FAIL_UNLESS_STR_EQUAL(match_text("MISMATCH", "SB_MISMATCH_RD"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("SB_.*", "SB_MISMATCH"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("SB_.*", "my SB_LEFTOVER here"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("SB_.*", "DRV_TIMEOUT"), "0")
   `SVTEST_END

   `SVTEST(anchors_tie_the_expression_to_the_ends)
      `FAIL_UNLESS_STR_EQUAL(match_text("^SB_", "SB_MISMATCH"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("^SB_", "MY_SB_MISMATCH"), "0")
      `FAIL_UNLESS_STR_EQUAL(match_text("MATCH$", "SB_MISMATCH"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("MATCH$", "SB_MISMATCH_RD"), "0")
      `FAIL_UNLESS_STR_EQUAL(match_text("^abc$", "abc"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("^abc$", "abcd"), "0")
   `SVTEST_END

   `SVTEST(extended_syntax_is_available)
      `FAIL_UNLESS_STR_EQUAL(match_text("^(RD|WR)_[0-9]+$", "WR_17"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("^(RD|WR)_[0-9]+$", "RW_17"), "0")
      `FAIL_UNLESS_STR_EQUAL(match_text("^(RD|WR)_[0-9]+$", "WR_"), "0")
      `FAIL_UNLESS_STR_EQUAL(match_text("^ab?c$", "ac"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("^ab?c$", "abbc"), "0")
      `FAIL_UNLESS_STR_EQUAL(match_text("^a.c$", "abc"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("^a[^b]c$", "abc"), "0")
   `SVTEST_END

   `SVTEST(a_dot_must_be_escaped_to_match_literally)
      `FAIL_UNLESS_STR_EQUAL(match_text("^file\\.sv:12$", "file.sv:12"), "1")
      `FAIL_UNLESS_STR_EQUAL(match_text("^file\\.sv:12$", "fileXsv:12"), "0")
      `FAIL_UNLESS_STR_EQUAL(match_text("^file.sv:12$", "fileXsv:12"), "1")
   `SVTEST_END

   `SVTEST(matching_is_case_sensitive)
      `FAIL_UNLESS_STR_EQUAL(match_text("sb_mismatch", "SB_MISMATCH"), "0")
   `SVTEST_END

   `SVTEST(a_filter_without_expressions_passes_everything)
      `FAIL_UNLESS_STR_EQUAL(passes("", "", "anything"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("", "", ""), "1")
   `SVTEST_END

   `SVTEST(a_filter_passes_what_the_include_expression_matches)
      `FAIL_UNLESS_STR_EQUAL(passes("^SB_", "", "SB_MISMATCH"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB_", "", "DRV_TIMEOUT"), "0")
   `SVTEST_END

   `SVTEST(a_filter_rejects_what_the_exclude_expression_matches)
      `FAIL_UNLESS_STR_EQUAL(passes("", "LEFTOVER", "SB_LEFTOVER"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("", "LEFTOVER", "SB_MISMATCH"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB_", "LEFTOVER", "SB_LEFTOVER"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB_", "LEFTOVER", "SB_MISMATCH"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB_", "LEFTOVER", "DRV_TIMEOUT"), "0")
   `SVTEST_END

   `SVTEST(a_filter_gives_the_answers_of_match_for_every_kind_of_expression)
      `FAIL_UNLESS_STR_EQUAL(filter_disagreement(), "")
   `SVTEST_END

   `SVTEST(a_filter_matches_text_without_operators_where_the_anchors_say)
      `FAIL_UNLESS_STR_EQUAL(passes("SB", "", "xSBx"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("SB", "", "xS_Bx"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB", "", "SBx"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB", "", "xSB"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("SB$", "", "xSB"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("SB$", "", "SBx"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB$", "", "SB"), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("^SB$", "", "SBx"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("^$", "", ""), "1")
      `FAIL_UNLESS_STR_EQUAL(passes("^$", "", "a"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("", "^SB$", "SB"), "0")
      `FAIL_UNLESS_STR_EQUAL(passes("", "^SB$", "SBx"), "1")
   `SVTEST_END

   `SVTEST(glob_to_regex_matches_the_whole_string)
      `FAIL_UNLESS_STR_EQUAL(glob_matches("uvm_test_top.env.*", "uvm_test_top.env.agent"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("uvm_test_top.env.*", "x.uvm_test_top.env.agent"), "0")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("*.drv", "top.agent.drv"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("*.drv", "top.agent.drv_x"), "0")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("agent_?", "agent_3"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("agent_?", "agent_13"), "0")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("", ""), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("", "a"), "0")
   `SVTEST_END

   `SVTEST(glob_to_regex_takes_other_characters_literally)
      `FAIL_UNLESS_STR_EQUAL(glob_matches("a.b", "a.b"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("a.b", "aXb"), "0")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("q[3]", "q[3]"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("q[3]", "q3"), "0")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("a+b(c)", "a+b(c)"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("a|b", "a"), "0")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("^abc", "^abc"), "1")
      `FAIL_UNLESS_STR_EQUAL(glob_matches("^abc", "abc"), "0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_regex_unit_test
