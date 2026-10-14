// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uid_unit_test.sv
//
// SVUnit tests of hexk_uid and hexk_uid_pool.
// Every test starts with a new pool. The error for an ID that grows too long is demoted by
// a report catcher and counted.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_uid.

`include "svunit_defines.svh"

module hexk_uid_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   import hexk_uvm_pkg::hexk_report_catcher;

   string              name = "hexk_uid_ut";
   svunit_testcase     svunit_ut;

   hexk_report_catcher catcher;
   hexk_uid_pool       pool;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_UID_LENGTH$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_UID_LABEL$", UVM_ERROR, "", 0, -1, UVM_INFO);
      hexk_uid_pool::reset_for_test();
      pool = hexk_uid_pool::get();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_uid_pool::reset_for_test();
      catcher.clear();
   endtask : teardown

   // The text of the next top-level ID with this label.
   function automatic string next_top(string label);
      hexk_uid uid = pool.new_uid(label);
      return uid.convert2string();
   endfunction : next_top

   // The texts of an item ID under each of two sequences, and of a second item under the first.
   function automatic string family();
      hexk_uid first_seq = pool.new_uid("seq_wr");
      hexk_uid second_seq = pool.new_uid("seq_wr");
      hexk_uid first_item = first_seq.new_child("item");
      hexk_uid other_item = second_seq.new_child("item");
      hexk_uid second_item = first_seq.new_child("item");
      hexk_uid response = first_seq.new_child("rsp");
      return {
         first_item.convert2string(),
         " ",
         other_item.convert2string(),
         " ",
         second_item.convert2string(),
         " ",
         response.convert2string()
      };
   endfunction : family

   // An ID three levels deep and what its accessors return.
   function automatic string accessors();
      hexk_uid seq_uid = pool.new_uid("seq");
      hexk_uid item_uid;
      hexk_uid beat_uid;
      hexk_uid top_parent;
      void'(seq_uid.new_child("item"));
      item_uid   = seq_uid.new_child("item");
      beat_uid   = item_uid.new_child("beat");
      top_parent = seq_uid.get_parent();
      return $sformatf(
          "%s label=%s number=%0d parent=%s length_ok=%0d top_parent_null=%0d",
          beat_uid.convert2string(),
          beat_uid.get_label(),
          item_uid.get_number(),
          beat_uid.get_parent().convert2string(),
          beat_uid.get_length() == beat_uid.convert2string().len(),
          top_parent == null
      );
   endfunction : accessors

   // The text of the ID with a number of seven digits.
   function automatic string wide_number();
      hexk_uid uid = new(null, "burst", 1234567);
      return $sformatf("%s length_ok=%0d", uid.convert2string(), uid.get_length() == uid.convert2string().len());
   endfunction : wide_number

   // Takes a child of the newest ID again and again, as a reused object would; returns the longest text seen.
   function automatic string reuse(int unsigned rounds);
      hexk_uid     uid = pool.new_uid("item");
      int unsigned longest = 0;
      repeat (rounds) begin
         uid = uid.new_child("item");
         if (uid.get_length() > longest) begin
            longest = uid.get_length();
         end
      end
      return $sformatf("longest=%0d errors=%0d", longest, catcher.get_count("^HEXK_UID_LENGTH$"));
   endfunction : reuse

   // Number of HEXK_UID_LENGTH errors in this test.
   function automatic string length_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_UID_LENGTH$"));
   endfunction : length_errors

   // IDs whose label holds one of the characters that separate the parts of an ID, and IDs without:
   // the number of HEXK_UID_LABEL errors. The label of a top-level ID and of a child is checked when first used.
   function automatic string label_errors();
      hexk_uid plain = pool.new_uid("a");
      void'(pool.new_uid("a:000000/b"));
      void'(pool.new_uid("a:000000/b"));
      void'(plain.new_child("b/c"));
      void'(plain.new_child("b/c"));
      void'(plain.new_child("b"));
      return $sformatf("%0d", catcher.get_count("^HEXK_UID_LABEL$"));
   endfunction : label_errors

   // Replaces the pool by a new one.
   function automatic void use_new_pool();
      hexk_uid_pool::reset_for_test();
      pool = hexk_uid_pool::get();
   endfunction : use_new_pool

   // Sets the length limit of the pool.
   function automatic void set_max_length(int unsigned max_length);
      pool.max_length = max_length;
   endfunction : set_max_length

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(top_level_ids_are_numbered_per_label_from_zero)
      `FAIL_UNLESS_STR_EQUAL(next_top("seq_wr"), "seq_wr:000000")
      `FAIL_UNLESS_STR_EQUAL(next_top("seq_wr"), "seq_wr:000001")
      `FAIL_UNLESS_STR_EQUAL(next_top("seq_rd"), "seq_rd:000000")
      `FAIL_UNLESS_STR_EQUAL(next_top("seq_wr"), "seq_wr:000002")
   `SVTEST_END

   `SVTEST(children_are_numbered_per_label_under_their_parent)
      `FAIL_UNLESS_STR_EQUAL(family(),
         "seq_wr:000000/item:000000 seq_wr:000001/item:000000 seq_wr:000000/item:000001 seq_wr:000000/rsp:000000")
   `SVTEST_END

   `SVTEST(an_id_knows_its_label_number_parent_and_length)
      `FAIL_UNLESS_STR_EQUAL(accessors(),
         {"seq:000000/item:000001/beat:000000 label=beat number=1 parent=seq:000000/item:000001 ",
          "length_ok=1 top_parent_null=1"})
   `SVTEST_END

   `SVTEST(a_number_with_more_than_six_digits_is_not_cut)
      `FAIL_UNLESS_STR_EQUAL(wide_number(), "burst:1234567 length_ok=1")
   `SVTEST_END

   `SVTEST(a_new_pool_starts_the_numbers_again)
      `FAIL_UNLESS_STR_EQUAL(next_top("seq"), "seq:000000")
      use_new_pool();
      `FAIL_UNLESS_STR_EQUAL(next_top("seq"), "seq:000000")
   `SVTEST_END

   `SVTEST(an_id_that_grows_too_long_is_an_error_and_starts_a_new_chain)
      set_max_length(40);
      `FAIL_UNLESS_STR_EQUAL(reuse(2), "longest=35 errors=0")
      `FAIL_UNLESS_STR_EQUAL(reuse(20), "longest=35 errors=6")
   `SVTEST_END

   `SVTEST(a_label_with_a_separator_character_is_an_error_once_per_label)
      `FAIL_UNLESS_STR_EQUAL(label_errors(), "2")
   `SVTEST_END

   `SVTEST(a_top_level_id_that_is_too_long_is_an_error)
      set_max_length(10);
      `FAIL_UNLESS_STR_EQUAL(next_top("abc"), "abc:000000")
      `FAIL_UNLESS_STR_EQUAL(length_errors(), "0")
      `FAIL_UNLESS_STR_EQUAL(next_top("abcdefgh"), "abcdefgh:000000")
      `FAIL_UNLESS_STR_EQUAL(length_errors(), "1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_uid_unit_test
