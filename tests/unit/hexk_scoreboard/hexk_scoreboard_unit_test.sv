// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_scoreboard_unit_test.sv
//
// SVUnit tests of hexk_scoreboard, hexk_scoreboard_cfg and hexk_sb_stats.
// The items are small packets with an ID, which is the key, and data. A class derived from
// the scoreboard overrides the hooks: the key is the ID, the text of an item is one line,
// and the other hooks do something special only when a test switches that on.
// The UVM phases do not run in a unit test simulation, so each test sets the cfg of a fresh
// scoreboard, calls its build_phase and later its check_phase itself, and writes items
// through write_expected_idx/write_actual_idx or through analysis ports connected to the
// exports. Errors of the scoreboard are demoted by a report catcher and counted; a second
// catcher keeps the text of the latest message of the scoreboard.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_scoreboard.

`include "svunit_defines.svh"
`include "uvm_macros.svh"
`include "hexk_macros.svh"

module hexk_scoreboard_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_uvm_pkg::hexk_sb_mode_e;
   import hexk_uvm_pkg::HEXK_SB_IN_ORDER;
   import hexk_uvm_pkg::HEXK_SB_OUT_OF_ORDER;
   import hexk_uvm_pkg::HEXK_SB_IN_ORDER_PER_KEY;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   import hexk_uvm_pkg::hexk_check_stats;
   `include "uvm_macros.svh"

   // Data value that makes transform_expected() of the test scoreboard drop the item.
   localparam int unsigned DROPPED_DATA = 999;

   // Item with a key and compared data.
   class hexk_ut_packet extends uvm_object;
      `uvm_object_utils(hexk_ut_packet)

      int unsigned     id;
      int unsigned     data;
      hexk_uid         uid;
      longint unsigned seen_at_ps;
      // Not compared: a transaction ID that the test scoreboard can pair by.
      int unsigned     tag;
      // 1: do_compare() compares through the comparer, which then names the fields that differ.
      static bit       names_fields;

      function new(string object_name = "hexk_ut_packet");
         super.new(object_name);
      endfunction : new

      virtual function string convert2string();
         return $sformatf("id=%0d data=%0d", id, data);
      endfunction : convert2string

      virtual function void do_copy(uvm_object rhs);
         hexk_ut_packet other;
         super.do_copy(rhs);
         void'($cast(other, rhs));
         id         = other.id;
         data       = other.data;
         uid        = other.uid;
         seen_at_ps = other.seen_at_ps;
         tag        = other.tag;
      endfunction : do_copy

      virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_ut_packet other;
         if (!$cast(other, rhs)) begin
            return 0;
         end
         if (names_fields) begin
            return comparer.compare_field_int("id", 64'(id), 64'(other.id), 32) &
                comparer.compare_field_int("data", 64'(data), 64'(other.data), 32);
         end
         return other.id == id && other.data == data;
      endfunction : do_compare
   endclass : hexk_ut_packet

   // A packet whose clone() gives nothing, as that of a class without a factory registration does.
   class hexk_ut_uncloneable_packet extends hexk_ut_packet;
      function new(string object_name = "hexk_ut_uncloneable_packet");
         super.new(object_name);
      endfunction : new

      virtual function uvm_object clone();
         return null;
      endfunction : clone
   endclass : hexk_ut_uncloneable_packet

   // Scoreboard for the packets with every hook overridden.
   class hexk_ut_scoreboard extends hexk_scoreboard #(
       .T  (hexk_ut_packet),
       .KEY(int unsigned)
   );
      bit          explain_difference;
      bit          use_item_time;
      // 1: is_partner() pairs by tag, so that compare_items() checks the pair it chose.
      bit          partner_by_tag;
      // Number of calls of item_text().
      int unsigned texts_built;
      // Number of calls of compare_items().
      int unsigned compares;

      function new(string component_name, uvm_component parent);
         super.new(component_name, parent);
      endfunction : new

      virtual function int unsigned get_key(hexk_ut_packet item);
         return item.id;
      endfunction : get_key

      virtual function bit compare_items(hexk_ut_packet exp, hexk_ut_packet act, output string diff);
         bit equal = super.compare_items(exp, act, diff);
         compares++;
         if (!equal && explain_difference) begin
            diff = $sformatf("data %0d is not %0d", act.data, exp.data);
         end
         return equal;
      endfunction : compare_items

      virtual function bit is_partner(hexk_ut_packet exp, hexk_ut_packet act);
         return partner_by_tag ? exp.tag == act.tag : super.is_partner(exp, act);
      endfunction : is_partner

      virtual function hexk_ut_packet transform_expected(hexk_ut_packet item);
         return (item.data == DROPPED_DATA) ? null : item;
      endfunction : transform_expected

      virtual function longint unsigned get_timestamp_ps(hexk_ut_packet item);
         return use_item_time ? item.seen_at_ps : super.get_timestamp_ps(item);
      endfunction : get_timestamp_ps

      virtual function hexk_uid get_uid(hexk_ut_packet item);
         return item.uid;
      endfunction : get_uid

      // The text is that of the scoreboard, which takes convert2string() of an item that has one.
      virtual function string item_text(hexk_ut_packet item);
         texts_built++;
         return super.item_text(item);
      endfunction : item_text
   endclass : hexk_ut_scoreboard

   // Keeps the text of the latest summary and of the latest other message whose ID starts with HEXK_SB_.
   class hexk_ut_text_catcher extends uvm_report_catcher;
      string text;
      string summary;

      function new(string catcher_name = "hexk_ut_text_catcher");
         super.new(catcher_name);
      endfunction : new

      function action_e catch();
         string id = get_id();
         if (id == "HEXK_SB_SUMMARY") begin
            summary = get_message();
         end else if (hexk_str::starts_with(id, "HEXK_SB_")) begin
            text = get_message();
         end
         return THROW;
      endfunction : catch
   endclass : hexk_ut_text_catcher

   string                              name = "hexk_scoreboard_ut";
   svunit_testcase                     svunit_ut;

   hexk_report_catcher                 catcher;
   hexk_ut_text_catcher                text_catcher;
   hexk_scoreboard_cfg                 cfg;
   hexk_ut_scoreboard                  scoreboard;
   hexk_objection_aggregator           aggregator;
   uvm_analysis_port #(hexk_ut_packet) expected_port;
   uvm_analysis_port #(hexk_ut_packet) actual_port;
   int unsigned                        created;

   function automatic void build();
      svunit_ut    = new(name);
      catcher      = hexk_report_catcher::add_global();
      text_catcher = new();
      uvm_report_cb::add(null, text_catcher);
   endfunction : build

   // Every test gets a fresh cfg and scoreboard; the test builds the scoreboard after it set the cfg.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_SB_MISMATCH$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_UNEXPECTED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_LEFTOVER$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_LATENCY$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_OUTSTANDING$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_STREAM$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_AGGREGATOR$", UVM_WARNING, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_SB_CLONE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      hexk_uid_pool::reset_for_test();
      hexk_ut_packet::names_fields = 0;
      created++;
      cfg                  = hexk_scoreboard_cfg::type_id::create("cfg");
      scoreboard           = new($sformatf("ut_scoreboard_%0d", created), null);
      scoreboard.cfg       = cfg;
      aggregator           = null;
      text_catcher.text    = "";
      text_catcher.summary = "";
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_uid_pool::reset_for_test();
      catcher.clear();
   endtask : teardown

   // Sets the mode and the number of streams, then builds the scoreboard.
   function automatic void build_scoreboard(hexk_sb_mode_e mode = HEXK_SB_IN_ORDER, int unsigned num_streams = 1);
      cfg.mode        = mode;
      cfg.num_streams = num_streams;
      scoreboard.build_phase(null);
   endfunction : build_scoreboard

   // Lets actual items wait for their expected items.
   function automatic void allow_unexpected();
      cfg.allow_unexpected = 1;
   endfunction : allow_unexpected

   // Sets one of the numeric limits of the cfg.
   function automatic void set_limit(string which, int unsigned value);
      case (which)
         "max_errors":      cfg.max_errors = value;
         "max_outstanding": cfg.max_outstanding = value;
         default:           cfg.leftover_print_limit = value;
      endcase
   endfunction : set_limit

   // Sets the longest latency that is not an error, given as a time of this module.
   function automatic void set_max_latency(realtime max_latency);
      cfg.max_latency_ps = `hexk_ps(max_latency);
   endfunction : set_max_latency

   // Clears one of the flags of the cfg that are set by default.
   function automatic void clear_flag(string which);
      if (which == "hold_objection") begin
         cfg.hold_objection = 0;
      end else begin
         cfg.flush_on_reset = 0;
      end
   endfunction : clear_flag

   // The summary of check_phase on one line, cut after the given number of characters.
   function automatic string summary_start(int unsigned length);
      return hexk_str::truncate(hexk_str::replace(text_catcher.summary, "\n", " | "), length, 0, "");
   endfunction : summary_start

   // A packet with the given ID and data.
   function automatic hexk_ut_packet packet(int unsigned id, int unsigned data);
      hexk_ut_packet item = new();
      item.id   = id;
      item.data = data;
      return item;
   endfunction : packet

   // Writes an expected packet to a stream.
   function automatic void expect_packet(int unsigned id, int unsigned data, int stream = 0);
      scoreboard.write_expected_idx(stream, packet(id, data));
   endfunction : expect_packet

   // Writes an actual packet to a stream.
   function automatic void actual_packet(int unsigned id, int unsigned data, int stream = 0);
      scoreboard.write_actual_idx(stream, packet(id, data));
   endfunction : actual_packet

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // The counters of a stream, or of all streams, as text.
   function automatic string stats(int stream = -1);
      hexk_sb_stats counters = scoreboard.get_stats(stream);
      return counters.convert2string();
   endfunction : stats

   // "<matched> <mismatched>" of a stream, or of all streams.
   function automatic string pairs(int stream = -1);
      hexk_sb_stats counters = scoreboard.get_stats(stream);
      return $sformatf("%0d %0d", counters.matched, counters.mismatched);
   endfunction : pairs

   // Latency of the matched pairs of stream 0 in nanoseconds, as "<min> <mean> <max>".
   function automatic string latencies();
      hexk_sb_stats counters = scoreboard.get_stats(0);
      return $sformatf(
          "%0d %0d %0d",
          counters.latency_min_ps / 1000,
          counters.latency_avg_ps() / 1000,
          counters.latency_max_ps / 1000
      );
   endfunction : latencies

   // Messages of the scoreboard in this test, as "<mismatch> <unexpected> <leftover> <latency> <outstanding> <stream>".
   function automatic string problems();
      return $sformatf(
          "%0d %0d %0d %0d %0d %0d",
          catcher.get_count(
              "^HEXK_SB_MISMATCH$"
          ),
          catcher.get_count(
              "^HEXK_SB_UNEXPECTED$"
          ),
          catcher.get_count(
              "^HEXK_SB_LEFTOVER$"
          ),
          catcher.get_count(
              "^HEXK_SB_LATENCY$"
          ),
          catcher.get_count(
              "^HEXK_SB_OUTSTANDING$"
          ),
          catcher.get_count(
              "^HEXK_SB_STREAM$"
          )
      );
   endfunction : problems

   // The latest message of the scoreboard on one line, with " | " for every line break.
   function automatic string message();
      return hexk_str::replace(text_catcher.text, "\n", " | ");
   endfunction : message

   // The first line of the latest message of the scoreboard.
   function automatic string headline();
      string lines[$];
      hexk_str::split(text_catcher.text, lines, "\n");
      return (lines.size() == 0) ? "" : lines[0];
   endfunction : headline

   // Number of lines of the latest message of the scoreboard.
   function automatic string message_lines();
      string lines[$];
      hexk_str::split(text_catcher.text, lines, "\n");
      return $sformatf("%0d", lines.size());
   endfunction : message_lines

   // "<is_busy> <busy_reason without the time>".
   function automatic string busy();
      string reason = scoreboard.busy_reason();
      int    since = hexk_str::find(reason, ", the oldest");
      if (since >= 0) begin
         reason = reason.substr(0, since - 1);
      end
      return $sformatf("%0d %s", scoreboard.is_busy(), reason);
   endfunction : busy

   // Gives the scoreboard an aggregator and runs end_of_elaboration; returns what the aggregator reports as busy.
   function automatic string register_with_aggregator();
      aggregator            = new($sformatf("ut_sb_objections_%0d", created), null);
      scoreboard.aggregator = aggregator;
      scoreboard.end_of_elaboration_phase(null);
      expect_packet(1, 10);
      return hexk_str::replace(aggregator.report_busy(), scoreboard.get_full_name(), "sb");
   endfunction : register_with_aggregator

   // Connects analysis ports to the exports of a stream and writes one matching pair through them.
   function automatic void write_through_ports(int unsigned stream);
      expected_port = new($sformatf("ut_sb_expected_port_%0d_%0d", created, stream), null);
      actual_port   = new($sformatf("ut_sb_actual_port_%0d_%0d", created, stream), null);
      if (stream == 0) begin
         expected_port.connect(scoreboard.expected_export);
         actual_port.connect(scoreboard.actual_export);
      end else begin
         expected_port.connect(scoreboard.expected_exports[stream]);
         actual_port.connect(scoreboard.actual_exports[stream]);
      end
      expected_port.resolve_bindings();
      actual_port.resolve_bindings();
      expected_port.write(packet(1, 10));
      actual_port.write(packet(1, 10));
   endfunction : write_through_ports

   // A plain in-order scoreboard whose KEY is a four-state type gets two expected and two actual packets, the
   // second pair with a difference: "<matched> <mismatched> <unexpected> <is_busy>".
   function automatic string in_order_with_a_four_state_key();
      hexk_scoreboard #(
          .T  (hexk_ut_packet),
          .KEY(logic [7:0])
      ) plain = new(
          $sformatf("ut_plain_scoreboard_%0d", created), null
      );
      hexk_sb_stats counters;
      plain.cfg = cfg;
      plain.build_phase(null);
      plain.write_expected_idx(0, packet(1, 10));
      plain.write_expected_idx(0, packet(2, 20));
      plain.write_actual_idx(0, packet(1, 10));
      plain.write_actual_idx(0, packet(2, 21));
      counters = plain.get_stats();
      return $sformatf("%0d %0d %0d %0d", counters.matched, counters.mismatched, counters.unexpected, plain.is_busy());
   endfunction : in_order_with_a_four_state_key

   // Writes a mismatching pair whose packets have unique IDs.
   function automatic void mismatch_with_uids();
      hexk_uid_pool  pool = hexk_uid_pool::get();
      hexk_uid       seq_uid = pool.new_uid("seq");
      hexk_ut_packet expected = packet(1, 10);
      hexk_ut_packet actual = packet(1, 11);
      expected.uid = seq_uid.new_child("item");
      actual.uid   = pool.new_uid("mon");
      scoreboard.write_expected_idx(0, expected);
      scoreboard.write_actual_idx(0, actual);
   endfunction : mismatch_with_uids

   // Writes an expected packet whose own time stamp is the given time of this module before now.
   function automatic void expect_seen_earlier(realtime earlier);
      hexk_ut_packet expected = packet(1, 10);
      expected.seen_at_ps      = hexk_uvm_pkg::hexk_wait_util::now_ps() - `hexk_ps(earlier);
      scoreboard.use_item_time = 1;
      scoreboard.write_expected_idx(0, expected);
   endfunction : expect_seen_earlier

   // Makes the test scoreboard explain a mismatch.
   function automatic void explain_differences();
      scoreboard.explain_difference = 1;
   endfunction : explain_differences

   // Makes the packets compare through the comparer, which then names the fields that differ.
   function automatic void name_fields();
      hexk_ut_packet::names_fields = 1;
   endfunction : name_fields

   // Makes the scoreboard keep clones of the expected items that wait.
   function automatic void clone_expected();
      cfg.clone_expected = 1;
   endfunction : clone_expected

   // The settings of a new cfg, and of a clone of the cfg of the test after every member got a value that is
   // not its default. The cfg is changed again after the clone, which must not follow.
   function automatic string cfg_texts();
      hexk_scoreboard_cfg fresh = hexk_scoreboard_cfg::type_id::create("fresh");
      hexk_scoreboard_cfg cloned;
      uvm_object          copied;
      cfg.mode                 = HEXK_SB_OUT_OF_ORDER;
      cfg.num_streams          = 3;
      cfg.max_errors           = 4;
      cfg.max_outstanding      = 5;
      cfg.max_latency_ps       = 6000;
      cfg.allow_unexpected     = 1;
      cfg.hold_objection       = 0;
      cfg.flush_on_reset       = 0;
      cfg.leftover_print_limit = 8;
      cfg.clone_expected       = 1;
      copied                   = cfg.clone();
      void'($cast(cloned, copied));
      cfg.num_streams = 7;
      cfg.max_errors  = 9;
      return {fresh.convert2string(), " / ", cloned.convert2string()};
   endfunction : cfg_texts

   // An expected packet with data 10 that its producer changes to 20 after writing it, then an actual packet with
   // data 20; with an uncloneable packet the expected one cannot be cloned. Gives "<pairs> <clone errors>".
   function automatic string reused_expected(bit uncloneable = 0);
      hexk_ut_packet             item = packet(1, 10);
      hexk_ut_uncloneable_packet plain;
      if (uncloneable) begin
         plain      = new();
         plain.id   = 1;
         plain.data = 10;
         item       = plain;
      end
      scoreboard.write_expected_idx(0, item);
      item.data = 20;
      actual_packet(1, 20);
      return $sformatf("%s %0d", pairs(), catcher.get_count("^HEXK_SB_CLONE$", UVM_ERROR));
   endfunction : reused_expected

   // Writes an expected and an actual packet with a tag, to a scoreboard that pairs by tag.
   function automatic void expect_tagged(int unsigned id, int unsigned data, int unsigned tag);
      hexk_ut_packet item = packet(id, data);
      item.tag                  = tag;
      scoreboard.partner_by_tag = 1;
      scoreboard.write_expected_idx(0, item);
   endfunction : expect_tagged

   function automatic void actual_tagged(int unsigned id, int unsigned data, int unsigned tag);
      hexk_ut_packet item = packet(id, data);
      item.tag = tag;
      scoreboard.write_actual_idx(0, item);
   endfunction : actual_tagged

   // An out-of-order search that compares the actual item with an unequal waiting item first:
   // "<info messages MISCMP of the comparer> <matched> <mismatched>".
   function automatic string search_messages();
      catcher.expect_msg("^MISCMP$", UVM_INFO, "", 0, -1, UVM_INFO);
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(1, 11);
      actual_packet(1, 11);
      return $sformatf("%0d %s", catcher.get_count("^MISCMP$", UVM_INFO), pairs());
   endfunction : search_messages

   // Forgets the checks counted so far.
   function automatic void forget_checks();
      hexk_check_stats::reset_for_test();
   endfunction : forget_checks

   // The comparisons of the scoreboard in hexk_check_stats: "<passed> <failed>".
   function automatic string checks();
      return $sformatf("%0d %0d", hexk_check_stats::num_passed("HEXK_SB_MISMATCH"),
                       hexk_check_stats::num_failed("HEXK_SB_MISMATCH"));
   endfunction : checks

   // Number of calls of compare_items() of the scoreboard so far.
   function automatic string compare_calls();
      return $sformatf("%0d", scoreboard.compares);
   endfunction : compare_calls

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(in_order_equal_items_match)
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      actual_packet(1, 10);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"2 expected, 2 actual, 2 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
   `SVTEST_END

   `SVTEST(in_order_a_different_item_is_a_mismatch_with_both_items_in_the_message)
      build_scoreboard();
      expect_packet(1, 10);
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "0 1")
      `FAIL_UNLESS_STR_EQUAL(problems(), "1 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected: | id=1 data=10 | ",
          "actual: | id=1 data=11"})
   `SVTEST_END

   `SVTEST(in_order_items_in_another_order_are_mismatches)
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      actual_packet(2, 20);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "0 2")
   `SVTEST_END

   `SVTEST(the_difference_text_of_compare_items_is_part_of_the_message)
      build_scoreboard();
      explain_differences();
      expect_packet(1, 10);
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected: | id=1 data=10 | ",
          "actual: | id=1 data=11 | difference: data 11 is not 10"})
   `SVTEST_END

   `SVTEST(the_default_difference_text_is_what_the_comparer_noted)
      build_scoreboard();
      name_fields();
      expect_packet(1, 10);
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected: | id=1 data=10 | ",
          "actual: | id=1 data=11 | difference: hexk_ut_packet.data: lhs = 'ha : rhs = 'hb"})
   `SVTEST_END

   `SVTEST(the_unique_ids_of_the_items_are_part_of_the_message)
      build_scoreboard();
      mismatch_with_uids();
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected (seq:000000/item:000000): | ",
          "id=1 data=10 | actual (mon:000000): | id=1 data=11"})
   `SVTEST_END

   `SVTEST(an_actual_item_without_an_expected_item_is_an_error)
      build_scoreboard();
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 1 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(message(), "stream 0: an actual item has no expected item | actual: | id=1 data=10")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"0 expected, 1 actual, 0 matched, 0 mismatched, 1 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(with_allow_unexpected_an_actual_item_waits_for_its_expected_item)
      allow_unexpected();
      build_scoreboard();
      actual_packet(1, 10);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 stream 0: 0 expected and 2 actual items are waiting")
      expect_packet(1, 10);
      expect_packet(2, 21);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 1")
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 ")
   `SVTEST_END

   `SVTEST(out_of_order_items_match_by_key)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(2, 20);
      expect_packet(3, 30);
      actual_packet(3, 30);
      actual_packet(1, 10);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "3 0")
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
   `SVTEST_END

   `SVTEST(out_of_order_duplicate_keys_match_whichever_item_is_equal)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(1, 11);
      expect_packet(1, 10);
      actual_packet(1, 11);
      actual_packet(1, 10);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "3 0")
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 ")
   `SVTEST_END

   `SVTEST(out_of_order_a_pair_that_the_search_found_equal_is_compared_once)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(1, 11);
      // The search compares with both waiting items; the pair it finds is not compared again.
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL(compare_calls(), "2")
      // No waiting item is equal: after the search, the oldest one is compared for the report.
      actual_packet(1, 12);
      `FAIL_UNLESS_STR_EQUAL(compare_calls(), "4")
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 1")
   `SVTEST_END

   `SVTEST(in_order_a_pair_is_compared_once)
      build_scoreboard();
      expect_packet(1, 10);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(compare_calls(), "1")
   `SVTEST_END

   `SVTEST(is_partner_chooses_the_pair_and_compare_items_checks_it)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_tagged(1, 10, 7);
      expect_tagged(1, 20, 8);
      actual_tagged(1, 21, 8);
      `FAIL_UNLESS_STR_EQUAL(problems(), "1 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected: | id=1 data=20 | ",
          "actual: | id=1 data=21"})
      actual_tagged(1, 10, 7);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 1")
      `FAIL_UNLESS_STR_EQUAL(compare_calls(), "2")
   `SVTEST_END

   `SVTEST(the_search_of_out_of_order_mode_prints_nothing_for_unequal_candidates)
      `FAIL_UNLESS_STR_EQUAL(search_messages(), "0 1 0")
   `SVTEST_END

   `SVTEST(every_comparison_of_a_pair_counts_as_a_check)
      forget_checks();
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      expect_packet(3, 30);
      actual_packet(1, 10);
      actual_packet(2, 21);
      actual_packet(3, 30);
      actual_packet(4, 40);
      `FAIL_UNLESS_STR_EQUAL(checks(), "2 1")
      `FAIL_UNLESS_STR_EQUAL(problems(), "1 1 0 0 0 0")
      forget_checks();
   `SVTEST_END

   `SVTEST(out_of_order_equal_items_with_one_key_match_oldest_first)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      advance(30ns);
      expect_packet(1, 10);
      advance(10ns);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(latencies(), "40 40 40")
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(latencies(), "10 25 40")
   `SVTEST_END

   `SVTEST(out_of_order_an_unknown_key_is_unexpected)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      actual_packet(2, 10);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 1 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 stream 0: 1 expected and 0 actual items are waiting")
   `SVTEST_END

   `SVTEST(out_of_order_a_known_key_without_an_equal_item_mismatches_the_oldest)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(1, 11);
      actual_packet(1, 12);
      `FAIL_UNLESS_STR_EQUAL(problems(), "1 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected: | id=1 data=10 | ",
          "actual: | id=1 data=12"})
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 1")
   `SVTEST_END

   `SVTEST(in_order_per_key_keeps_the_order_within_a_key_only)
      build_scoreboard(HEXK_SB_IN_ORDER_PER_KEY);
      expect_packet(1, 10);
      expect_packet(1, 11);
      expect_packet(2, 20);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 0")
      actual_packet(1, 11);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 2")
   `SVTEST_END

   `SVTEST(expected_items_that_are_left_over_are_reported_in_check_phase)
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      expect_packet(3, 30);
      actual_packet(1, 10);
      scoreboard.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 1 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"3 expected, 1 actual, 1 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "2 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(actual_items_that_are_left_over_are_reported_in_check_phase)
      allow_unexpected();
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      actual_packet(1, 10);
      expect_packet(2, 20);
      scoreboard.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 2 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"1 expected, 1 actual, 0 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "1 expected and 1 actual left over"})
   `SVTEST_END

   `SVTEST(the_leftover_report_prints_no_more_items_than_the_limit)
      set_limit("leftover_print_limit", 2);
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      expect_packet(3, 30);
      expect_packet(4, 40);
      scoreboard.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(headline(), "stream 0: 4 expected items never got an actual item; the first 2:")
      `FAIL_UNLESS_STR_EQUAL(message_lines(), "5")
   `SVTEST_END

   `SVTEST(the_leftover_report_of_a_stream_with_keys_stops_at_the_limit_within_a_key)
      set_limit("leftover_print_limit", 3);
      allow_unexpected();
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      actual_packet(5, 50);
      actual_packet(5, 51);
      actual_packet(6, 60);
      actual_packet(6, 61);
      scoreboard.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: 4 actual items never got an expected item; the first 3: | actual: | id=5 data=50 | ",
          "actual: | id=5 data=51 | actual: | id=6 data=60"})
   `SVTEST_END

   `SVTEST(a_scoreboard_without_leftovers_reports_only_the_summary)
      build_scoreboard();
      expect_packet(1, 10);
      actual_packet(1, 10);
      scoreboard.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(summary_start(60), " | stream 0: 1 expected, 1 actual, 1 matched, 0 mismatched, ")
   `SVTEST_END

   `SVTEST(latency_is_measured_from_the_expected_to_the_actual_item)
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(2, 20);
      expect_packet(3, 30);
      advance(10ns);
      actual_packet(2, 20);
      advance(10ns);
      actual_packet(1, 10);
      advance(10ns);
      actual_packet(3, 30);
      `FAIL_UNLESS_STR_EQUAL(latencies(), "10 20 30")
   `SVTEST_END

   `SVTEST(a_pair_that_takes_longer_than_max_latency_is_an_error_and_still_a_match)
      set_max_latency(30ns);
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      advance(30ns);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
      advance(1ns);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 1 0 0")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"2 expected, 2 actual, 2 matched, 0 mismatched, 0 unexpected, 0 dropped, 1 late, ",
          "0 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(get_timestamp_ps_decides_where_the_latency_starts)
      build_scoreboard();
      expect_seen_earlier(70ns);
      advance(5ns);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(latencies(), "75 75 75")
   `SVTEST_END

   `SVTEST(on_reset_drops_the_waiting_items)
      allow_unexpected();
      build_scoreboard(HEXK_SB_OUT_OF_ORDER);
      expect_packet(1, 10);
      expect_packet(2, 20);
      actual_packet(3, 30);
      scoreboard.on_reset();
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 ")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"2 expected, 1 actual, 0 matched, 0 mismatched, 0 unexpected, 3 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
      scoreboard.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
   `SVTEST_END

   `SVTEST(on_reset_keeps_the_items_when_flush_on_reset_is_clear)
      clear_flag("flush_on_reset");
      build_scoreboard();
      expect_packet(1, 10);
      scoreboard.on_reset();
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 0")
   `SVTEST_END

   `SVTEST(streams_do_not_see_each_other)
      build_scoreboard(HEXK_SB_IN_ORDER, 2);
      expect_packet(1, 10, 0);
      actual_packet(1, 10, 1);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 1 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(headline(), "stream 1: an actual item has no expected item")
      expect_packet(2, 20, 1);
      actual_packet(2, 20, 1);
      actual_packet(1, 10, 0);
      `FAIL_UNLESS_STR_EQUAL(pairs(0), "1 0")
      `FAIL_UNLESS_STR_EQUAL(pairs(1), "1 0")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"2 expected, 3 actual, 2 matched, 0 mismatched, 1 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(a_stream_that_does_not_exist_is_an_error)
      build_scoreboard(HEXK_SB_IN_ORDER, 2);
      expect_packet(1, 10, 2);
      actual_packet(1, 10, -1);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 2")
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"0 expected, 0 actual, 0 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(the_counters_of_a_stream_that_does_not_exist_are_an_error_and_zero)
      build_scoreboard(HEXK_SB_IN_ORDER, 2);
      expect_packet(1, 10, 1);
      `FAIL_UNLESS_STR_EQUAL(stats(2),
         {"0 expected, 0 actual, 0 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 1")
      `FAIL_UNLESS_STR_EQUAL(stats(1),
         {"1 expected, 0 actual, 0 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(a_write_before_the_build_phase_is_an_error)
      expect_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 1")
      `FAIL_UNLESS_STR_EQUAL(headline(),
         "stream 0 does not exist; the scoreboard has 0 streams and was not built yet")
   `SVTEST_END

   `SVTEST(zero_streams_is_an_error_and_gives_one_stream)
      build_scoreboard(HEXK_SB_IN_ORDER, 0);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 1")
      expect_packet(1, 10);
      actual_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(pairs(), "1 0")
   `SVTEST_END

   `SVTEST(items_arrive_through_the_exports_of_their_stream)
      build_scoreboard(HEXK_SB_IN_ORDER, 3);
      write_through_ports(0);
      write_through_ports(2);
      `FAIL_UNLESS_STR_EQUAL(pairs(0), "1 0")
      `FAIL_UNLESS_STR_EQUAL(pairs(1), "0 0")
      `FAIL_UNLESS_STR_EQUAL(pairs(2), "1 0")
   `SVTEST_END

   `SVTEST(the_scoreboard_is_busy_while_items_wait)
      build_scoreboard();
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 ")
      expect_packet(1, 10);
      expect_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 stream 0: 2 expected and 0 actual items are waiting")
      actual_packet(1, 10);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 ")
   `SVTEST_END

   `SVTEST(in_order_mode_does_not_use_the_key_type)
      `FAIL_UNLESS_STR_EQUAL(in_order_with_a_four_state_key(), "1 1 0 0")
   `SVTEST_END

   `SVTEST(without_hold_objection_the_scoreboard_is_never_busy)
      clear_flag("hold_objection");
      build_scoreboard();
      expect_packet(1, 10);
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 stream 0: 1 expected and 0 actual items are waiting")
   `SVTEST_END

   `SVTEST(the_scoreboard_registers_with_its_aggregator)
      build_scoreboard();
      `FAIL_UNLESS_STR_EQUAL(hexk_str::truncate(register_with_aggregator(), 62, 0, ""),
         "sb: busy: stream 0: 1 expected and 0 actual items are waiting,")
   `SVTEST_END

   `SVTEST(hold_objection_without_an_aggregator_is_a_warning)
      build_scoreboard();
      scoreboard.end_of_elaboration_phase(null);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", catcher.get_count("^HEXK_SB_AGGREGATOR$", UVM_WARNING)), "1")
   `SVTEST_END

   `SVTEST(more_waiting_items_than_max_outstanding_is_an_error_once_per_excursion)
      set_limit("max_outstanding", 2);
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 0 0")
      expect_packet(3, 30);
      expect_packet(4, 40);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 1 0")
      actual_packet(1, 10);
      actual_packet(2, 20);
      actual_packet(3, 30);
      expect_packet(5, 50);
      expect_packet(6, 60);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 2 0")
   `SVTEST_END

   `SVTEST(an_excursion_ends_when_the_stream_drains_to_max_outstanding)
      set_limit("max_outstanding", 1);
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 1 0")
      actual_packet(1, 10);
      expect_packet(3, 30);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 2 0")
   `SVTEST_END

   `SVTEST(an_excursion_of_waiting_actual_items_ends_when_an_expected_item_takes_one)
      set_limit("max_outstanding", 1);
      allow_unexpected();
      build_scoreboard();
      actual_packet(1, 10);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 1 0")
      expect_packet(1, 10);
      actual_packet(3, 30);
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0 0 2 0")
   `SVTEST_END

   `SVTEST(after_max_errors_the_items_are_no_longer_printed)
      set_limit("max_errors", 1);
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL(message_lines(), "5")
      actual_packet(2, 21);
      `FAIL_UNLESS_STR_EQUAL(problems(), "2 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(message(),
         "stream 0: the actual item differs from the expected item (items are not printed after 1 errors)")
   `SVTEST_END

   `SVTEST(the_text_of_an_item_is_built_only_when_it_is_printed)
      set_limit("max_errors", 1);
      build_scoreboard();
      expect_packet(1, 10);
      expect_packet(2, 20);
      actual_packet(1, 11);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", scoreboard.texts_built), "2")
      actual_packet(2, 21);
      actual_packet(3, 30);
      `FAIL_UNLESS_STR_EQUAL(problems(), "2 1 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", scoreboard.texts_built), "2")
   `SVTEST_END

   `SVTEST(transform_expected_can_drop_an_item)
      build_scoreboard();
      expect_packet(1, DROPPED_DATA);
      expect_packet(2, 20);
      actual_packet(2, 20);
      `FAIL_UNLESS_STR_EQUAL(stats(),
         {"1 expected, 1 actual, 1 matched, 0 mismatched, 0 unexpected, 0 dropped, 0 late, ",
          "0 expected and 0 actual left over"})
   `SVTEST_END

   `SVTEST(a_new_cfg_has_the_defaults_and_a_clone_has_every_setting)
      `FAIL_UNLESS_STR_EQUAL(cfg_texts(),
         {"mode=HEXK_SB_IN_ORDER num_streams=1 max_errors=10 max_outstanding=0 max_latency_ps=0",
          " allow_unexpected=0 hold_objection=1 flush_on_reset=1 leftover_print_limit=20 clone_expected=0 / ",
          "mode=HEXK_SB_OUT_OF_ORDER num_streams=3 max_errors=4 max_outstanding=5 max_latency_ps=6000",
          " allow_unexpected=1 hold_objection=0 flush_on_reset=0 leftover_print_limit=8 clone_expected=1"})
   `SVTEST_END

   `SVTEST(without_clone_expected_a_change_after_the_write_reaches_the_kept_item)
      build_scoreboard();
      `FAIL_UNLESS_STR_EQUAL(reused_expected(), "1 0 0")
   `SVTEST_END

   `SVTEST(with_clone_expected_a_change_after_the_write_does_not_reach_the_kept_item)
      clone_expected();
      build_scoreboard();
      `FAIL_UNLESS_STR_EQUAL(reused_expected(), "0 1 0")
      `FAIL_UNLESS_STR_EQUAL(message(),
         {"stream 0: the actual item differs from the expected item | expected: | id=1 data=10 | ",
          "actual: | id=1 data=20"})
   `SVTEST_END

   `SVTEST(an_expected_item_that_cannot_be_cloned_is_an_error_and_kept_itself)
      clone_expected();
      build_scoreboard();
      `FAIL_UNLESS_STR_EQUAL(reused_expected(1), "1 0 1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_scoreboard_unit_test
