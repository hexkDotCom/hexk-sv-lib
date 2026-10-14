// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_str_unit_test.sv
//
// SVUnit tests of hexk_str.
// Every function is checked with a small table of inputs, including empty strings and
// separators or matches at the ends. Queue results are compared as one string through the
// *_text helpers below. Two tool limits shape the test bodies: they hold only macro calls
// and call statements, because Verible cannot see the task that the SVUnit macros open
// around them; and every result is compared as text with FAIL_UNLESS_STR_EQUAL, because
// the other SVUnit checks turn their argument into a string, which Verilator rejects when
// the argument itself holds a string literal.
// Runs on Verilator: make test SIM=verilator TEST=hexk_str.

`include "svunit_defines.svh"

module hexk_str_unit_test;
   import svunit_pkg::svunit_testcase;
   import hexk_core_pkg::hexk_str;

   string           name = "hexk_str_ut";
   svunit_testcase  svunit_ut;

   string           parts                [$];
   string           list                 [$];
   byte unsigned    data                 [$];
   longint unsigned nums                 [$];

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // s written n times, one concatenation at a time: the expected value for pad and repeat_str.
   function automatic string run_of(string s, int unsigned n);
      string result;
      repeat (n) begin
         result = {result, s};
      end
      return result;
   endfunction : run_of

   // Decimal text of an int result.
   function automatic string int_text(int value);
      return $sformatf("%0d", value);
   endfunction : int_text

   // "1" or "0" for a bit result.
   function automatic string bit_text(bit value);
      return value ? "1" : "0";
   endfunction : bit_text

   // Result of hexk_str::split as "<count>:<part>|<part>...".
   function automatic string split_text(string s, byte sep = " ", int unsigned max_parts = 0);
      string result[$];
      hexk_str::split(s, result, sep, max_parts);
      return $sformatf("%0d:%s", result.size(), hexk_str::join_str(result, "|"));
   endfunction : split_text

   // Result of hexk_str::get_numbers as "<n>,<n>...".
   function automatic string numbers_text(string s);
      longint unsigned result[$];
      string text;
      hexk_str::get_numbers(s, result);
      foreach (result[i]) begin
         text = {text, (i == 0) ? "" : ",", $sformatf("%0d", result[i])};
      end
      return text;
   endfunction : numbers_text

   // The module-level list after hexk_str::natural_sort, joined with ",".
   function automatic string sorted_text(bit reverse = 0);
      hexk_str::natural_sort(list, reverse);
      return hexk_str::join_str(list, ",");
   endfunction : sorted_text

   // Fills the module-level data queue from a string of two-digit hex bytes.
   function automatic void set_data(string hex_bytes);
      string digits;
      data.delete();
      for (int i = 0; i + 1 < hex_bytes.len(); i += 2) begin
         digits = hex_bytes.substr(i, i + 1);
         data.push_back(8'(digits.atohex()));
      end
   endfunction : set_data

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(split_separates_fields)
      `FAIL_UNLESS_STR_EQUAL(split_text("a b c"), "3:a|b|c")
      `FAIL_UNLESS_STR_EQUAL(split_text("top.env.agent", "."), "3:top|env|agent")
      `FAIL_UNLESS_STR_EQUAL(split_text("no_separator", ","), "1:no_separator")
   `SVTEST_END

   `SVTEST(split_keeps_empty_fields)
      `FAIL_UNLESS_STR_EQUAL(split_text("a,,b", ","), "3:a||b")
      `FAIL_UNLESS_STR_EQUAL(split_text(",a,", ","), "3:|a|")
      `FAIL_UNLESS_STR_EQUAL(split_text(",", ","), "2:|")
   `SVTEST_END

   `SVTEST(split_of_empty_string_gives_no_parts)
      `FAIL_UNLESS_STR_EQUAL(split_text("", ","), "0:")
   `SVTEST_END

   `SVTEST(split_stops_at_max_parts)
      `FAIL_UNLESS_STR_EQUAL(split_text("a,b,c,d", ",", 2), "2:a|b,c,d")
      `FAIL_UNLESS_STR_EQUAL(split_text("a,b,c,d", ",", 1), "1:a,b,c,d")
      `FAIL_UNLESS_STR_EQUAL(split_text("a,b", ",", 5), "2:a|b")
   `SVTEST_END

   `SVTEST(split_clears_previous_parts)
      hexk_str::split("old content", parts);
      hexk_str::split("x", parts);
      `FAIL_UNLESS_STR_EQUAL(int_text(parts.size()), "1")
      `FAIL_UNLESS_STR_EQUAL(parts[0], "x")
   `SVTEST_END

   `SVTEST(join_str_puts_separator_between_parts)
      hexk_str::split("a b c", parts);
      `FAIL_UNLESS_STR_EQUAL(hexk_str::join_str(parts), "a b c")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::join_str(parts, ", "), "a, b, c")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::join_str(parts, ""), "abc")
      hexk_str::split("only", parts);
      `FAIL_UNLESS_STR_EQUAL(hexk_str::join_str(parts, ","), "only")
      hexk_str::split("", parts);
      `FAIL_UNLESS_STR_EQUAL(hexk_str::join_str(parts, ","), "")
   `SVTEST_END

   `SVTEST(join_str_inverts_split)
      hexk_str::split(",a,,b,", parts, ",");
      `FAIL_UNLESS_STR_EQUAL(hexk_str::join_str(parts, ","), ",a,,b,")
   `SVTEST_END

   `SVTEST(strip_removes_whitespace_at_both_ends)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::strip("  \t a b \n"), "a b")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::strip("a"), "a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::strip(" \t\n"), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::strip(""), "")
   `SVTEST_END

   `SVTEST(lstrip_and_rstrip_touch_one_end_only)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::lstrip("  a  "), "a  ")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip("  a  "), "  a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::lstrip("   "), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip("   "), "")
   `SVTEST_END

   `SVTEST(strip_uses_the_given_character_set)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::strip("xyaxbyx", "xy"), "axb")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::strip(" a ", "x"), " a ")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::rstrip("path///", "/"), "path")
   `SVTEST_END

   `SVTEST(starts_with_and_ends_with_compare_the_ends)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::starts_with("agent_cfg", "agent_")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::starts_with("agent_cfg", "cfg")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::starts_with("abc", "")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::starts_with("abc", "abc")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::starts_with("abc", "abcd")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::ends_with("file.sv", ".sv")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::ends_with("file.sv", "file")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::ends_with("abc", "")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::ends_with("bc", "abc")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::starts_with("", "")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::ends_with("", "")), "1")
   `SVTEST_END

   `SVTEST(contains_finds_a_substring_anywhere)
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::contains("uvm_test_top.env", "top")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::contains("abc", "abc")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::contains("abc", "")), "1")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::contains("abc", "abd")), "0")
      `FAIL_UNLESS_STR_EQUAL(bit_text(hexk_str::contains("", "a")), "0")
   `SVTEST_END

   `SVTEST(find_returns_the_first_position_at_or_after_start)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abcabc", "bc")), "1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abcabc", "bc", 2)), "4")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abcabc", "a")), "0")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abcabc", "c", 5)), "5")
   `SVTEST_END

   `SVTEST(find_returns_minus_one_when_absent)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "x")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "abcd")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "a", 1)), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "c", 10)), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("", "a")), "-1")
   `SVTEST_END

   `SVTEST(find_of_empty_substring_returns_start)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "")), "0")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "", 3)), "3")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "", 4)), "-1")
   `SVTEST_END

   `SVTEST(offsets_and_counts_above_the_largest_int_are_not_taken_as_negative)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "", 32'h8000_0000)), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::find("abc", "b", 32'hFFFF_FFFF)), "-1")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdef", 32'hFFFF_FFFF), "abcdef")
      `FAIL_UNLESS_STR_EQUAL(split_text("a b c", " ", 32'hFFFF_FFFF), "3:a|b|c")
   `SVTEST_END

   `SVTEST(rfind_returns_the_last_position)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::rfind("abcabc", "bc")), "4")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::rfind("abcabc", "a")), "3")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::rfind("abc", "x")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::rfind("abc", "abcd")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::rfind("abc", "")), "3")
   `SVTEST_END

   `SVTEST(replace_substitutes_every_occurrence)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("a.b.c", ".", "/"), "a/b/c")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("abab", "ab", ""), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("abc", "x", "y"), "abc")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("", "x", "y"), "")
   `SVTEST_END

   `SVTEST(replace_first_only_when_all_is_clear)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("a.b.c", ".", "/", 0), "a/b.c")
   `SVTEST_END

   `SVTEST(replace_does_not_rescan_its_own_output)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("aaa", "aa", "b"), "ba")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("a", "a", "aa"), "aa")
   `SVTEST_END

   `SVTEST(replace_with_empty_search_text_changes_nothing)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::replace("abc", "", "x"), "abc")
   `SVTEST_END

   `SVTEST(pad_fills_up_to_the_width)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("ab", 5), "   ab")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("ab", 5, 1), "ab   ")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("7", 3, 0, "0"), "007")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("", 2, 1, "-"), "--")
   `SVTEST_END

   `SVTEST(pad_fills_long_runs_of_blanks_and_of_other_characters)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("x", 64), {run_of(" ", 63), "x"})
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("x", 65), {run_of(" ", 64), "x"})
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("x", 100, 1), {"x", run_of(" ", 99)})
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("", 64, 1), run_of(" ", 64))
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("5", 70, 0, "0"), {run_of("0", 69), "5"})
   `SVTEST_END

   `SVTEST(pad_never_shortens)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("abcdef", 3), "abcdef")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("abc", 3), "abc")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::pad("abc", 0), "abc")
   `SVTEST_END

   `SVTEST(truncate_marks_the_cut_with_an_ellipsis)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 5), "abc..")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 5, 1), "..fgh")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 6, 0, "~"), "abcde~")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 6, 0, ""), "abcdef")
   `SVTEST_END

   `SVTEST(truncate_leaves_short_strings_alone)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abc", 5), "abc")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcde", 5), "abcde")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("", 0), "")
   `SVTEST_END

   `SVTEST(truncate_drops_the_ellipsis_when_it_does_not_fit)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 2), "ab")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 2, 1), "gh")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 1), "a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate("abcdefgh", 0), "")
   `SVTEST_END

   `SVTEST(repeat_str_concatenates_copies)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("ab", 3), "ababab")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("ab", 1), "ab")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("ab", 0), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("", 4), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("ab", 7), run_of("ab", 7))
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("xyz", 64), run_of("xyz", 64))
      `FAIL_UNLESS_STR_EQUAL(hexk_str::repeat_str("-", 1000), run_of("-", 1000))
   `SVTEST_END

   `SVTEST(basename_is_the_last_path_component)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::basename("a/b/c.sv"), "c.sv")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::basename("c.sv"), "c.sv")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::basename("/abs/dir/"), "dir")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::basename("/"), "/")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::basename(""), "")
   `SVTEST_END

   `SVTEST(dirname_is_the_path_without_its_last_component)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname("a/b/c.sv"), "a/b")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname("c.sv"), ".")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname("/c.sv"), "/")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname("a/b/"), "a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname("a//b"), "a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname("/"), "/")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::dirname(""), ".")
   `SVTEST_END

   `SVTEST(scope_slice_picks_elements_by_position)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b.c.d", 1, 2), "b.c")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b.c.d", 0, 0), "a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b.c.d", 0, 3), "a.b.c.d")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a/b/c", 1, 2, "/"), "b/c")
   `SVTEST_END

   `SVTEST(scope_slice_counts_negative_positions_from_the_end)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b.c.d", -2, -1), "c.d")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b.c.d", 1, -1), "b.c.d")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b.c.d", -1, -1), "d")
   `SVTEST_END

   `SVTEST(scope_slice_clamps_out_of_range_positions)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b", 0, 9), "a.b")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b", -9, 0), "a")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b", 2, 5), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("a.b", 1, 0), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::scope_slice("", 0, 0), "")
   `SVTEST_END

   `SVTEST(get_numbers_collects_every_digit_run)
      `FAIL_UNLESS_STR_EQUAL(numbers_text("a12b003c"), "12,3")
      `FAIL_UNLESS_STR_EQUAL(numbers_text("7"), "7")
      `FAIL_UNLESS_STR_EQUAL(numbers_text("x0y"), "0")
      `FAIL_UNLESS_STR_EQUAL(numbers_text("agent_3.item_18446744073709551615"), "3,18446744073709551615")
      `FAIL_UNLESS_STR_EQUAL(numbers_text("none"), "")
      `FAIL_UNLESS_STR_EQUAL(numbers_text(""), "")
   `SVTEST_END

   `SVTEST(get_numbers_clears_previous_numbers)
      hexk_str::get_numbers("1 2", nums);
      hexk_str::get_numbers("no digits", nums);
      `FAIL_UNLESS_STR_EQUAL(int_text(nums.size()), "0")
   `SVTEST_END

   `SVTEST(denumber_replaces_digit_runs)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::denumber("agent_12.drv"), "agent_#.drv")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::denumber("12ab34"), "#ab#")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::denumber("a1b22c333"), "a#b#c#")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::denumber("no_digits"), "no_digits")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::denumber(""), "")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::denumber("id[7]", "<n>"), "id[<n>]")
   `SVTEST_END

   `SVTEST(natural_cmp_compares_digit_runs_as_numbers)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a2", "a10")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a10", "a2")), "1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("item_9.x", "item_10.a")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("x99999999999999999999", "x100000000000000000000")), "-1")
   `SVTEST_END

   `SVTEST(natural_cmp_compares_other_characters_in_plain_order)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("abc", "abd")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("b", "a")), "1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a", "a1")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a1", "ab")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("", "a")), "-1")
   `SVTEST_END

   `SVTEST(natural_cmp_is_zero_only_for_identical_strings)
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a10", "a10")), "0")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("", "")), "0")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a01", "a1")), "-1")
      `FAIL_UNLESS_STR_EQUAL(int_text(hexk_str::natural_cmp("a1", "a01")), "1")
   `SVTEST_END

   `SVTEST(natural_sort_orders_a_list)
      hexk_str::split("t10 t2 t1 s3", list);
      `FAIL_UNLESS_STR_EQUAL(sorted_text(), "s3,t1,t2,t10")
      `FAIL_UNLESS_STR_EQUAL(sorted_text(1), "t10,t2,t1,s3")
   `SVTEST_END

   `SVTEST(natural_sort_accepts_short_lists)
      hexk_str::split("", list);
      `FAIL_UNLESS_STR_EQUAL(sorted_text(), "")
      hexk_str::split("one", list);
      `FAIL_UNLESS_STR_EQUAL(sorted_text(), "one")
      hexk_str::split("b a b", list);
      `FAIL_UNLESS_STR_EQUAL(sorted_text(), "a,b,b")
   `SVTEST_END

   `SVTEST(bytes_to_hex_dumps_bytes_in_lines)
      set_data("00ab10");
      `FAIL_UNLESS_STR_EQUAL(hexk_str::bytes_to_hex(data), "00 ab 10")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::bytes_to_hex(data, 2), "00 ab\n10")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::bytes_to_hex(data, 1), "00\nab\n10")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::bytes_to_hex(data, 0), "00 ab 10")
      set_data("");
      `FAIL_UNLESS_STR_EQUAL(hexk_str::bytes_to_hex(data), "")
   `SVTEST_END

   `SVTEST(simplify_typename_keeps_the_type_name_only)
      `FAIL_UNLESS_STR_EQUAL(hexk_str::simplify_typename("class my_pkg::my_item extends uvm_object"), "my_pkg::my_item")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::simplify_typename("class my_item"), "my_item")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::simplify_typename("  my_item  "), "my_item")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::simplify_typename("classy_item"), "classy_item")
      `FAIL_UNLESS_STR_EQUAL(hexk_str::simplify_typename(""), "")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_str_unit_test
