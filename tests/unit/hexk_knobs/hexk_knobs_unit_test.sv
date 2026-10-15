// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_knobs_unit_test.sv
//
// SVUnit tests of hexk_knobs.
// The knobs are a singleton, so every test starts with reset_for_test(). Knobs whose name
// starts with ut_ have no plusarg; the knobs named in hexk_knobs_unit_test.plusargs get
// their value from the command line of the simulation. Errors and fatals of the knobs are
// demoted by a report catcher and counted. +hexk_knobs_help and +hexk_knobs_strict are not
// given to this simulation, which other suites share: the first would end it, and the check
// behind the second is tested through check_plusargs().
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_knobs.

`include "svunit_defines.svh"

module hexk_knobs_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_enum_knob;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   // Enumeration of the enumeration knobs; on the command line its members are rtl, gate and power.
   typedef enum {
      HEXK_UT_KNOB_NETLIST_RTL,
      HEXK_UT_KNOB_NETLIST_GATE,
      HEXK_UT_KNOB_NETLIST_POWER
   } hexk_ut_knob_netlist_e;

   // Another enumeration, to read a knob as the wrong one.
   typedef enum {
      HEXK_UT_KNOB_SPEED_FAST,
      HEXK_UT_KNOB_SPEED_SLOW
   } hexk_ut_knob_speed_e;

   // An enumeration whose members have the same texts on the command line as those of the netlist enumeration.
   typedef enum {
      HEXK_UT_KNOB_LOOK_RTL,
      HEXK_UT_KNOB_LOOK_GATE,
      HEXK_UT_KNOB_LOOK_POWER
   } hexk_ut_knob_look_e;

   // An enumeration with two members of the same text on the command line, x.
   typedef enum {
      HEXK_UT_KNOB_CASE_X,
      HEXK_UT_KNOB_CASE_x
   } hexk_ut_knob_case_e;

   string              name = "hexk_knobs_ut";
   svunit_testcase     svunit_ut;

   hexk_report_catcher catcher;
   hexk_knobs          knobs;
   string              modes                  [$] = '{"rtl", "gate", "power"};
   bit                 waiter_done;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
      knobs     = hexk_knobs::get();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_KNOBS_DEFINE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_LOCKED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_VALUE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_STRICT$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_READ$", UVM_FATAL, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_TYPE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_ENUM$", UVM_ERROR, "", 0, -1, UVM_INFO);
      hexk_knobs::reset_for_test();
      waiter_done = 0;
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_knobs::reset_for_test();
      catcher.clear();
   endtask : teardown

   // "same" when get() returns the knobs that build() got.
   function automatic string get_again();
      return (hexk_knobs::get() == knobs) ? "same" : "other";
   endfunction : get_again

   // Messages of the knobs in this test, as "define=<n> locked=<n> value=<n> strict=<n> read=<n>".
   function automatic string messages();
      int unsigned define_count = catcher.get_count("^HEXK_KNOBS_DEFINE$");
      int unsigned locked_count = catcher.get_count("^HEXK_KNOBS_LOCKED$");
      int unsigned value_count = catcher.get_count("^HEXK_KNOBS_VALUE$");
      int unsigned strict_count = catcher.get_count("^HEXK_KNOBS_STRICT$");
      int unsigned read_count = catcher.get_count("^HEXK_KNOBS_READ$", UVM_FATAL);
      return $sformatf(
          "define=%0d locked=%0d value=%0d strict=%0d read=%0d",
          define_count,
          locked_count,
          value_count,
          strict_count,
          read_count
      );
   endfunction : messages

   // Decimal text of an integer knob.
   function automatic string int_of(string knob_name);
      return $sformatf("%0d", knobs.get_int(knob_name));
   endfunction : int_of

   // "0" or "1" for a bit knob.
   function automatic string bit_of(string knob_name);
      return $sformatf("%0d", knobs.get_bit(knob_name));
   endfunction : bit_of

   // Defines one knob of each kind without a plusarg.
   function automatic void define_plain_knobs();
      knobs.add_int("ut_items", 10, "number of items per sequence", 1, 100);
      knobs.add_bit("ut_cov", 1, "collect functional coverage");
      knobs.add_str("ut_tag", "nightly", "label of the run");
      knobs.add_enum_str("ut_mode", "rtl", modes, "kind of netlist");
   endfunction : define_plain_knobs

   // Defines the knobs that the plusargs of this test set.
   function automatic void define_cli_knobs();
      knobs.add_int("hexk_ut_knob_items", 10, "number of items", 1, 100);
      knobs.add_bit("hexk_ut_knob_fast", 0, "skip the long reset");
      knobs.add_bit("hexk_ut_knob_slow", 1, "add idle cycles");
      knobs.add_str("hexk_ut_knob_label", "none", "label of the run");
      knobs.add_enum_str("hexk_ut_knob_mode", "rtl", modes, "kind of netlist");
   endfunction : define_cli_knobs

   // Defines a knob of an enumeration with two members of one text: "<HEXK_KNOBS_ENUM errors> <knob exists>".
   function automatic string define_ambiguous_enum_knob();
      hexk_enum_knob#(hexk_ut_knob_case_e)::add("ut_case", HEXK_UT_KNOB_CASE_X, "two members of one text");
      return $sformatf("%0d %0b", catcher.get_count("^HEXK_KNOBS_ENUM$"), knobs.has("ut_case"));
   endfunction : define_ambiguous_enum_knob

   // Defines two enumeration knobs: one without a plusarg, and one that the plusargs of this test set to power.
   function automatic void define_enum_knobs();
      hexk_enum_knob#(hexk_ut_knob_netlist_e)::add("ut_netlist", HEXK_UT_KNOB_NETLIST_GATE, "kind of netlist");
      hexk_enum_knob#(hexk_ut_knob_netlist_e)::add("hexk_ut_knob_netlist", HEXK_UT_KNOB_NETLIST_RTL, "kind of netlist");
   endfunction : define_enum_knobs

   // Sets an enumeration knob.
   function automatic void set_netlist(string knob_name, hexk_ut_knob_netlist_e value);
      hexk_enum_knob#(hexk_ut_knob_netlist_e)::set(knob_name, value);
   endfunction : set_netlist

   // Name of the member that an enumeration knob holds.
   function automatic string netlist_of(string knob_name);
      hexk_ut_knob_netlist_e value = hexk_enum_knob#(hexk_ut_knob_netlist_e)::get(knob_name);
      return value.name();
   endfunction : netlist_of

   // Name of the member that a knob gives when it is read as the look enumeration, whose texts are those of the
   // netlist enumeration.
   function automatic string look_of(string knob_name);
      hexk_ut_knob_look_e value = hexk_enum_knob#(hexk_ut_knob_look_e)::get(knob_name);
      return value.name();
   endfunction : look_of

   // Sets a knob through the look enumeration.
   function automatic void set_look(string knob_name, hexk_ut_knob_look_e value);
      hexk_enum_knob#(hexk_ut_knob_look_e)::set(knob_name, value);
   endfunction : set_look

   // Number of HEXK_KNOBS_TYPE errors so far.
   function automatic string type_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_KNOBS_TYPE$"));
   endfunction : type_errors

   // Name of the member that a knob gives when it is read as the speed enumeration.
   function automatic string speed_of(string knob_name);
      hexk_ut_knob_speed_e value = hexk_enum_knob#(hexk_ut_knob_speed_e)::get(knob_name);
      return value.name();
   endfunction : speed_of

   // help() on one line, with " | " for every line break.
   function automatic string help_text();
      return hexk_str::replace(knobs.help(), "\n", " | ");
   endfunction : help_text

   // The last line of help() with every run of blanks as one blank. The width of the columns
   // follows the longest name, and the name of a knob that is set by a plusarg holds the
   // prefix of the library, so this text does not depend on the length of that prefix.
   function automatic string last_help_line();
      string lines[$];
      string words[$];
      string kept [$];
      hexk_str::split(knobs.help(), lines, "\n");
      hexk_str::split(lines[lines.size()-1], words, " ");
      foreach (words[i]) begin
         if (words[i].len() != 0) begin
            kept.push_back(words[i]);
         end
      end
      return hexk_str::join_str(kept, " ");
   endfunction : last_help_line

   // Starts a thread that waits for lock() and then sets waiter_done.
   task automatic start_waiter();
      fork
         begin
            hexk_knobs::wait_locked();
            waiter_done = 1;
         end
      join_none
      advance(1ns);
   endtask : start_waiter

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // Number of findings of check_plusargs for a fixed command line.
   function automatic string strict_findings();
      string plusargs[$] = '{
          "+num_itms=5",
          "+perf_mod",
          "+UVM_TESTNAME=my_test",
          "+num_items=3",
          "+e",
          "+prf_mode=1",
          "+seed=12",
          "plain"
      };
      knobs.add_int("num_items", 1, "items");
      knobs.add_bit("perf_mode", 0, "performance mode");
      knobs.add_bit("en", 0, "enable");
      return $sformatf("%0d", knobs.check_plusargs(plusargs));
   endfunction : strict_findings

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(get_returns_the_one_set_of_knobs)
      `FAIL_UNLESS_STR_EQUAL(get_again(), "same")
   `SVTEST_END

   `SVTEST(a_knob_has_its_default_value)
      define_plain_knobs();
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "10")
      `FAIL_UNLESS_STR_EQUAL(bit_of("ut_cov"), "1")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_tag"), "nightly")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_mode"), "rtl")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(set_changes_a_value_before_lock)
      define_plain_knobs();
      knobs.set_int("ut_items", 25);
      knobs.set_int("ut_cov", 0);
      knobs.set_str("ut_tag", "smoke");
      knobs.set_str("ut_mode", "power");
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "25")
      `FAIL_UNLESS_STR_EQUAL(bit_of("ut_cov"), "0")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_tag"), "smoke")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_mode"), "power")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(a_plusarg_wins_over_the_default)
      define_cli_knobs();
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_knob_items"), "7")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_knob_fast"), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_knob_slow"), "0")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("hexk_ut_knob_label"), "from_cli")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("hexk_ut_knob_mode"), "gate")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(a_plusarg_wins_over_set)
      define_cli_knobs();
      knobs.set_int("hexk_ut_knob_items", 99);
      knobs.set_int("hexk_ut_knob_fast", 0);
      knobs.set_str("hexk_ut_knob_label", "from_test");
      knobs.set_str("hexk_ut_knob_mode", "power");
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_knob_items"), "7")
      `FAIL_UNLESS_STR_EQUAL(bit_of("hexk_ut_knob_fast"), "1")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("hexk_ut_knob_label"), "from_cli")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("hexk_ut_knob_mode"), "gate")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(an_integer_outside_its_limits_is_rejected)
      define_plain_knobs();
      knobs.set_int("ut_items", 101);
      knobs.set_int("ut_items", 0);
      knobs.set_int("ut_cov", 2);
      knobs.add_int("hexk_ut_knob_big", 50, "too big on the command line", 0, 100);
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=4 strict=0 read=0")
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "10")
      `FAIL_UNLESS_STR_EQUAL(bit_of("ut_cov"), "1")
      `FAIL_UNLESS_STR_EQUAL(int_of("hexk_ut_knob_big"), "50")
   `SVTEST_END

   `SVTEST(an_integer_without_limits_takes_any_value)
      knobs.add_int("ut_offset", 0, "signed offset");
      knobs.set_int("ut_offset", -64'sd5000000000);
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_offset"), "-5000000000")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(a_string_that_is_not_in_the_list_is_rejected)
      define_plain_knobs();
      knobs.set_str("ut_mode", "fpga");
      knobs.add_enum_str("hexk_ut_knob_bad_mode", "rtl", modes, "illegal on the command line");
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=2 strict=0 read=0")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_mode"), "rtl")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("hexk_ut_knob_bad_mode"), "rtl")
   `SVTEST_END

   `SVTEST(an_enumeration_knob_holds_a_member_of_its_enumeration)
      define_enum_knobs();
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(netlist_of("ut_netlist"), "HEXK_UT_KNOB_NETLIST_GATE")
      `FAIL_UNLESS_STR_EQUAL(netlist_of("hexk_ut_knob_netlist"), "HEXK_UT_KNOB_NETLIST_POWER")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_netlist"), "gate")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(an_enumeration_knob_is_set_with_a_member_and_a_plusarg_still_wins)
      define_enum_knobs();
      set_netlist("ut_netlist", HEXK_UT_KNOB_NETLIST_POWER);
      set_netlist("hexk_ut_knob_netlist", HEXK_UT_KNOB_NETLIST_GATE);
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(netlist_of("ut_netlist"), "HEXK_UT_KNOB_NETLIST_POWER")
      `FAIL_UNLESS_STR_EQUAL(netlist_of("hexk_ut_knob_netlist"), "HEXK_UT_KNOB_NETLIST_POWER")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(an_enumeration_knob_that_is_read_as_another_enumeration_is_an_error)
      define_enum_knobs();
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(speed_of("ut_netlist"), "HEXK_UT_KNOB_SPEED_FAST")
      `FAIL_UNLESS_STR_EQUAL(type_errors(), "1")
   `SVTEST_END

   `SVTEST(an_enumeration_with_the_same_texts_does_not_read_or_set_the_knob_of_another)
      define_enum_knobs();
      define_cli_knobs();
      set_look("ut_netlist", HEXK_UT_KNOB_LOOK_POWER);
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(look_of("ut_netlist"), "HEXK_UT_KNOB_LOOK_RTL")
      `FAIL_UNLESS_STR_EQUAL(netlist_of("ut_netlist"), "HEXK_UT_KNOB_NETLIST_GATE")
      `FAIL_UNLESS_STR_EQUAL(look_of("hexk_ut_knob_mode"), "HEXK_UT_KNOB_LOOK_RTL")
      `FAIL_UNLESS_STR_EQUAL(type_errors(), "3")
   `SVTEST_END

   `SVTEST(set_with_the_wrong_function_or_an_unknown_name_is_an_error)
      define_plain_knobs();
      knobs.set_str("ut_items", "25");
      knobs.set_int("ut_tag", 3);
      knobs.set_int("ut_missing", 3);
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=3 strict=0 read=0")
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "10")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_tag"), "nightly")
   `SVTEST_END

   `SVTEST(a_bad_definition_is_an_error)
      knobs.add_int("ut_items", 500, "default outside the limits", 1, 100);
      knobs.add_enum_str("ut_mode", "fpga", modes, "default not in the list");
      knobs.add_bit("ut_items", 0, "defined twice");
      knobs.add_str("", "x", "no name");
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=4 locked=0 value=0 strict=0 read=0")
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "500")
   `SVTEST_END

   `SVTEST(nothing_changes_after_lock)
      define_plain_knobs();
      knobs.lock();
      knobs.set_int("ut_items", 25);
      knobs.set_str("ut_tag", "late");
      knobs.add_bit("ut_late", 1, "defined after lock");
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=3 value=0 strict=0 read=0")
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "10")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_tag"), "nightly")
   `SVTEST_END

   `SVTEST(a_read_before_lock_is_fatal)
      define_plain_knobs();
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "0")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=1")
   `SVTEST_END

   `SVTEST(the_fatal_of_a_read_before_lock_says_where_the_knobs_are_locked)
      define_plain_knobs();
      catcher.clear();
      catcher.expect_msg("HEXK_KNOBS_READ", UVM_FATAL, "before lock.*hexk_base_test locks them in its build_phase", 0,
                         -1, UVM_INFO);
      catcher.expect_msg("^HEXK_KNOBS_READ$", UVM_FATAL, "", 0, -1, UVM_INFO);
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", catcher.get_count("HEXK_KNOBS_READ", UVM_FATAL)), "1")
   `SVTEST_END

   `SVTEST(a_read_of_an_unknown_knob_or_with_the_wrong_function_is_fatal)
      define_plain_knobs();
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_missing"), "0")
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_cov"), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_of("ut_items"), "0")
      `FAIL_UNLESS_STR_EQUAL(knobs.get_str("ut_items"), "")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=4")
   `SVTEST_END

   `SVTEST(has_says_whether_a_knob_is_defined)
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", knobs.has("ut_items")), "0")
      define_plain_knobs();
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", knobs.has("ut_items")), "1")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", knobs.has("ut_missing")), "0")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(help_is_a_table_with_value_and_source)
      define_plain_knobs();
      knobs.set_str("ut_tag", "smoke");
      `FAIL_UNLESS_STR_EQUAL(help_text(),
         {"  name      value  source   help | ",
          "  ut_items  10     default  number of items per sequence | ",
          "  ut_cov    1      default  collect functional coverage | ",
          "  ut_tag    smoke  set      label of the run | ",
          "  ut_mode   rtl    default  kind of netlist"})
   `SVTEST_END

   `SVTEST(help_names_the_plusarg_as_the_source_of_a_value)
      define_plain_knobs();
      knobs.add_int("hexk_ut_knob_items", 10, "number of items", 1, 100);
      `FAIL_UNLESS_STR_EQUAL(last_help_line(), "hexk_ut_knob_items 7 plusarg number of items")
   `SVTEST_END

   `SVTEST(help_says_when_there_are_no_knobs)
      `FAIL_UNLESS_STR_EQUAL(help_text(), "no knobs are defined")
   `SVTEST_END

   `SVTEST(wait_locked_returns_when_the_knobs_are_locked)
      define_plain_knobs();
      start_waiter();
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", waiter_done), "0")
      knobs.lock();
      advance(1ns);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", waiter_done), "1")
   `SVTEST_END

   `SVTEST(check_plusargs_finds_plusargs_that_look_like_knobs)
      `FAIL_UNLESS_STR_EQUAL(strict_findings(), "3")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=3 read=0")
   `SVTEST_END

   `SVTEST(reset_for_test_removes_the_knobs_and_the_lock)
      define_plain_knobs();
      knobs.lock();
      hexk_knobs::reset_for_test();
      `FAIL_UNLESS_STR_EQUAL(help_text(), "no knobs are defined")
      define_plain_knobs();
      knobs.set_int("ut_items", 3);
      knobs.lock();
      `FAIL_UNLESS_STR_EQUAL(int_of("ut_items"), "3")
      `FAIL_UNLESS_STR_EQUAL(messages(), "define=0 locked=0 value=0 strict=0 read=0")
   `SVTEST_END

   `SVTEST(an_enumeration_with_two_members_of_one_text_is_an_error_and_defines_no_knob)
      `FAIL_UNLESS_STR_EQUAL(define_ambiguous_enum_knob(), "1 0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_knobs_unit_test
