// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_scoreboard.sv
//
// Generic matcher and checker: pairs each actual item with an expected item, compares the
// two, and reports mismatches, unexpected items and, at the end of the test, items that were
// left over on either side. T is the item class; KEY is the type of the key for matching out
// of order. A predictor or a reference monitor writes expected items to expected_export, the
// DUT monitor writes actual items to actual_export. hexk_scoreboard_cfg selects the mode:
// in order, out of order by key, or in order per key, and the number of independent streams.
// Three questions are answered apart: which items may be partners (get_key(), and in mode
// HEXK_SB_OUT_OF_ORDER is_partner()), in which order they meet (the mode), and whether a pair
// agrees (compare_items()). Derive a class to answer them; the defaults compare with compare()
// of the item and need no derived class for a plain in-order scoreboard. Every comparison
// of a pair counts as a check in hexk_check_stats, under the ID HEXK_SB_MISMATCH.
// The scoreboard is busy for hexk_objection_aggregator while items wait, so the test does
// not end before the last item has arrived; on_reset() drops what is waiting.
//
//! @module    hexk_scoreboard
//! @since     0.7.0
//! @stability experimental
//! @serves    CHK-2 CHK-3 CHK-4 CHK-5 CHK-6 OBJ-2 MSG-7
//! @emits     HEXK_SB_MISMATCH:error HEXK_SB_UNEXPECTED:error HEXK_SB_LEFTOVER:error HEXK_SB_LATENCY:error
//! @emits     HEXK_SB_OUTSTANDING:error HEXK_SB_STREAM:error HEXK_SB_AGGREGATOR:warning
//! @emits     HEXK_SB_SUMMARY:info HEXK_SB_FLUSH:info HEXK_SB_CLONE:error
//! @plusargs  (none)

`ifndef HEXK_SCOREBOARD_SV
`define HEXK_SCOREBOARD_SV

// The two imp classes of the scoreboard; a lint rule wants every class in a file of its own name.
// verilator lint_off DECLFILENAME
`hexk_analysis_imp_indexed_decl(expected_idx)
`hexk_analysis_imp_indexed_decl(actual_idx)
// verilator lint_on DECLFILENAME

class hexk_scoreboard #(
    type T   = uvm_sequence_item,
    type KEY = int
) extends uvm_scoreboard implements hexk_objectable;

   typedef hexk_scoreboard#(T, KEY) this_t;
   typedef hexk_sb_stream#(T, KEY) stream_t;

   // Settings; assign before the build phase, or a cfg with the defaults is created.
   hexk_scoreboard_cfg                                           cfg;

   // Aggregator the scoreboard registers with when cfg.hold_objection is set; assign before end_of_elaboration.
   hexk_objection_aggregator                                     aggregator;

   // Analysis exports of stream 0, for a scoreboard with one stream.
   hexk_analysis_imp_indexed_expected_idx #(.T(T), .IMP(this_t)) expected_export;
   hexk_analysis_imp_indexed_actual_idx #(.T(T), .IMP(this_t))   actual_export;

   // Analysis exports of every stream, by stream number.
   hexk_analysis_imp_indexed_expected_idx #(.T(T), .IMP(this_t)) expected_exports [$];
   hexk_analysis_imp_indexed_actual_idx #(.T(T), .IMP(this_t))   actual_exports   [$];

   local stream_t                                                streams          [$];

   // The mode of cfg at the build phase: the streams are created for it.
   local hexk_sb_mode_e                                          mode;

   // Key of every item in mode HEXK_SB_IN_ORDER, where the streams ignore keys: the value a KEY
   // has without an assignment. A lint rule reports a variable that is never assigned.
   // verilator lint_off UNDRIVEN
   local KEY                                                     common_key;
   // verilator lint_on UNDRIVEN

   // Number of errors that were reported with the items printed.
   local int unsigned                                            detailed_errors;

   // The comparer of the default compare_items(), one for all comparisons: compare() starts it afresh.
   local uvm_comparer                                            default_comparer;

   // The last pair that the default is_partner() compared, and whether it was equal, so that the pair it
   // chooses is not compared a second time.
   local T                                                       partner_exp;
   local T                                                       partner_act;
   local bit                                                     partner_equal;

   `uvm_component_param_utils(hexk_scoreboard#(T, KEY))

   // Creates the scoreboard; streams and exports are created in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      default_comparer           = new();
      // The scoreboard reports a mismatch itself, with both items. The comparer prints no field; UVM 2020 also
      // prints a line MISCMP for every unequal compare(), with the verbosity of the comparer, which would be one
      // line per candidate of an out-of-order search.
      default_comparer.show_max  = 0;
      default_comparer.verbosity = UVM_DEBUG;
   endfunction : new

   // Hook: the key of an item for the modes that match by key; the default gives every item the same key.
   virtual function KEY get_key(T item);
      return common_key;
   endfunction : get_key

   // Hook: 1 when the actual item is what the expected item asks for; diff may explain a difference. The default
   // gives in diff what the comparer noted: the fields that differ, for an item whose do_compare() uses it.
   virtual function bit compare_items(T exp, T act, output string diff);
      bit same = exp.compare(act, default_comparer);
      diff = same ? "" : hexk_str::strip(default_comparer.miscompares);
      return same;
   endfunction : compare_items

   // Hook of mode HEXK_SB_OUT_OF_ORDER: 1 when the actual item is the partner of the expected item, both with
   // the same key. The scoreboard pairs an item with the oldest waiting item for which it is 1 and then calls
   // compare_items() on the pair. The default is compare_items(): the partner is an equal item, and that pair
   // is not compared again. Override it to pair by an ID, so that a wrong payload is reported as a mismatch.
   virtual function bit is_partner(T exp, T act);
      string diff;
      partner_exp   = exp;
      partner_act   = act;
      partner_equal = compare_items(exp, act, diff);
      return partner_equal;
   endfunction : is_partner

   // Hook: turns an item written to an expected export into the item to wait for; null means nothing is expected.
   virtual function T transform_expected(T item);
      return item;
   endfunction : transform_expected

   // Hook: the time in picoseconds from which the latency of an expected item counts; the default is the time
   // of the write. An override returns a time in picoseconds, such as hexk_meta_item::timestamp_ps.
   virtual function longint unsigned get_timestamp_ps(T item);
      return $time;
   endfunction : get_timestamp_ps

   // Hook: the unique ID of an item for messages; the default is none.
   virtual function hexk_uid get_uid(T item);
      return null;
   endfunction : get_uid

   // Hook: the text of an item in messages; the default is convert2string(), or sprint() for an item without one.
   virtual function string item_text(T item);
      string text = item.convert2string();
      return (text.len() != 0) ? text : item.sprint();
   endfunction : item_text

   // Analysis write of an expected export: the item waits for its actual item, or meets one that came early.
   function void write_expected_idx(int idx, T t);
      stream_t stream = stream_of(idx);
      T        item;
      T        actual;
      KEY      key;
      int      position;
      if (stream == null) begin
         return;
      end
      item = transform_expected(t);
      if (item == null) begin
         return;
      end
      stream.stats.expected_count++;
      key      = key_of(item);
      position = find_partner(stream, key, item, 1);
      if (position >= 0) begin
         actual = stream.take_actual(key, $unsigned(position));
         finish_pair(stream, idx, item, actual, get_timestamp_ps(item), found_equal(item, actual));
         check_outstanding(stream, idx);
         return;
      end
      stream.store_expected(key, kept_expected(item), get_timestamp_ps(item));
      check_outstanding(stream, idx);
   endfunction : write_expected_idx

   // The expected item that a stream keeps: the item itself, or a clone of it with cfg.clone_expected. An item
   // whose class cannot be cloned is kept itself, after an error.
   local function T kept_expected(T item);
      T kept;
      if (!cfg.clone_expected) begin
         return item;
      end
      if (!$cast(kept, item.clone()) || kept == null) begin
         `uvm_error("HEXK_SB_CLONE",
                    $sformatf(
                        "an expected item of class %s cannot be cloned, the scoreboard keeps the item itself: %s",
                        item.get_type_name(),
                        "register the class with the factory and give it a do_copy(), or clear cfg.clone_expected"))
         return item;
      end
      return kept;
   endfunction : kept_expected

   // Analysis write of an actual export: the item is compared with the expected item it belongs to.
   function void write_actual_idx(int idx, T t);
      stream_t         stream = stream_of(idx);
      KEY              key;
      int              position;
      longint unsigned stamp_ps;
      T                expected;
      if (stream == null || t == null) begin
         return;
      end
      stream.stats.actual_count++;
      key      = key_of(t);
      position = find_partner(stream, key, t, 0);
      if (position < 0 && cfg.allow_unexpected) begin
         stream.store_actual(key, t);
         check_outstanding(stream, idx);
         return;
      end
      if (stream.num_expected_for(key) == 0) begin
         stream.stats.unexpected++;
         report_problem("HEXK_SB_UNEXPECTED", $sformatf("stream %0d: an actual item has no expected item", idx), null,
                        t);
         return;
      end
      // No expected item of this key is a partner: the actual item is compared with the oldest one.
      if (position < 0) begin
         position = 0;
      end
      expected = stream.take_expected(key, $unsigned(position), stamp_ps);
      finish_pair(stream, idx, expected, t, stamp_ps, found_equal(expected, t));
      check_outstanding(stream, idx);
   endfunction : write_actual_idx

   // Reset of the DUT: drops all waiting items when cfg.flush_on_reset is set.
   function void on_reset();
      int unsigned flushed;
      if (cfg == null || !cfg.flush_on_reset) begin
         return;
      end
      foreach (streams[i]) begin
         flushed = streams[i].clear();
         streams[i].stats.dropped += flushed;
         if (flushed != 0) begin
            `uvm_info("HEXK_SB_FLUSH", $sformatf("stream %0d: %0d waiting items dropped on reset", i, flushed),
                      UVM_MEDIUM)
         end
      end
   endfunction : on_reset

   // The counters of one stream, or of all streams together when stream is below 0.
   // A stream that does not exist is an error and gives counters that are all 0.
   function hexk_sb_stats get_stats(int stream = -1);
      hexk_sb_stats total = new();
      stream_t      one;
      if (stream >= 0) begin
         one = stream_of(stream);
         return (one == null) ? total : one.stats;
      end
      foreach (streams[i]) begin
         total.add(streams[i].stats);
      end
      return total;
   endfunction : get_stats

   // hexk_objectable: 1 while items are waiting and cfg.hold_objection is set.
   virtual function bit is_busy();
      if (cfg == null || !cfg.hold_objection) begin
         return 0;
      end
      foreach (streams[i]) begin
         if (streams[i].num_expected != 0 || streams[i].num_actual != 0) begin
            return 1;
         end
      end
      return 0;
   endfunction : is_busy

   // hexk_objectable: per stream, how many items are waiting and since when.
   virtual function string busy_reason();
      string           lines     [$];
      longint unsigned oldest_ps;
      bit              found;
      foreach (streams[i]) begin
         if (streams[i].num_expected == 0 && streams[i].num_actual == 0) begin
            continue;
         end
         oldest_ps = streams[i].oldest_expected_time_ps(found);
         lines.push_back($sformatf(
                         "stream %0d: %0d expected and %0d actual items are waiting%s",
                         i,
                         streams[i].num_expected,
                         streams[i].num_actual,
                         found ? $sformatf(
                             ", the oldest expected one since %0t", oldest_ps
                         ) : ""
                         ));
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : busy_reason

   // UVM callback: creates the cfg if none was assigned, the streams and their exports.
   function void build_phase(uvm_phase phase);
      int unsigned count;
      super.build_phase(phase);
      if (cfg == null) begin
         cfg = hexk_scoreboard_cfg::type_id::create("cfg");
      end
      mode  = cfg.mode;
      count = cfg.num_streams;
      if (count == 0) begin
         `uvm_error("HEXK_SB_STREAM", "cfg.num_streams is 0; one stream is created")
         count = 1;
      end
      for (int unsigned i = 0; i < count; i++) begin
         stream_t                                                      stream = new(mode != HEXK_SB_IN_ORDER);
         hexk_analysis_imp_indexed_expected_idx #(.T(T), .IMP(this_t)) expected_imp;
         hexk_analysis_imp_indexed_actual_idx #(.T(T), .IMP(this_t))   actual_imp;
         expected_imp = new($sformatf("expected_export_%0d", i), this, int'(i));
         actual_imp   = new($sformatf("actual_export_%0d", i), this, int'(i));
         streams.push_back(stream);
         expected_exports.push_back(expected_imp);
         actual_exports.push_back(actual_imp);
      end
      expected_export = expected_exports[0];
      actual_export   = actual_exports[0];
   endfunction : build_phase

   // UVM callback: registers with the aggregator when cfg.hold_objection is set.
   function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      if (!cfg.hold_objection) begin
         return;
      end
      if (aggregator == null) begin
         `uvm_warning("HEXK_SB_AGGREGATOR", {
                      "cfg.hold_objection is set, but no aggregator was assigned: the scoreboard does not keep ",
                      "the phase alive; assign the member aggregator or clear hold_objection"})
         return;
      end
      aggregator.register(this, get_full_name());
   endfunction : end_of_elaboration_phase

   // UVM callback: reports the items that were left over on either side, and the summary.
   function void check_phase(uvm_phase phase);
      string lines[$];
      super.check_phase(phase);
      foreach (streams[i]) begin
         report_leftovers(i);
         lines.push_back($sformatf(
                         "stream %0d: %s; latency min %0t, mean %0t, max %0t",
                         i,
                         streams[i].stats.convert2string(),
                         streams[i].stats.latency_min_ps,
                         streams[i].stats.latency_avg_ps(),
                         streams[i].stats.latency_max_ps
                         ));
      end
      `uvm_info("HEXK_SB_SUMMARY", {"\n", hexk_str::join_str(lines, "\n")}, UVM_LOW)
   endfunction : check_phase

   // The stream with this number, or null and an error.
   local function stream_t stream_of(int idx);
      // A string variable: a conditional of two literals of different lengths is padded with NULs on one tool.
      string state = "built";
      if (idx < 0 || idx >= streams.size()) begin
         if (streams.size() == 0) begin
            state = "not built yet";
         end
         `uvm_error("HEXK_SB_STREAM", $sformatf("stream %0d does not exist; the scoreboard has %0d streams and was %s",
                                                idx, streams.size(), state))
         return null;
      end
      return streams[idx];
   endfunction : stream_of

   // The key under which an item is stored: its own in the keyed modes, one for all in mode HEXK_SB_IN_ORDER.
   local function KEY key_of(T item);
      return (mode == HEXK_SB_IN_ORDER) ? common_key : get_key(item);
   endfunction : key_of

   // Position of the waiting partner of an item under its key, or -1 when there is none.
   // With as_expected the item is an expected one and looks among the actual items, otherwise the reverse.
   local function int find_partner(stream_t stream, KEY key, T item, bit as_expected);
      int unsigned count = as_expected ? stream.num_actual_for(key) : stream.num_expected_for(key);
      string       diff;
      if (count == 0) begin
         return -1;
      end
      if (mode != HEXK_SB_OUT_OF_ORDER) begin
         return 0;
      end
      for (int unsigned i = 0; i < count; i++) begin
         if (as_expected ? is_partner(
                 item, stream.peek_actual(key, i)
             ) : is_partner(
                 stream.peek_expected(key, i), item
             )) begin
            return int'(i);
         end
      end
      return -1;
   endfunction : find_partner

   // 1 when the default is_partner() has just found this pair equal, so that it need not be compared again.
   local function bit found_equal(T expected, T actual);
      return mode == HEXK_SB_OUT_OF_ORDER && partner_equal && partner_exp == expected && partner_act == actual;
   endfunction : found_equal

   // Compares a pair, counts it here and as a check in hexk_check_stats, and reports a mismatch or a latency above
   // the limit. With known_equal the search for the pair has compared it already, and it is not compared again.
   local function void finish_pair(stream_t stream, int idx, T expected, T actual, longint unsigned stamp_ps,
                                   bit known_equal);
      string           diff;
      // A timestamp of an override that lies in the future counts as a latency of 0.
      longint unsigned latency_ps = ($time > stamp_ps) ? $time - stamp_ps : 0;
      if (!known_equal && !compare_items(expected, actual, diff)) begin
         hexk_check_stats::record_fail("HEXK_SB_MISMATCH");
         stream.stats.mismatched++;
         report_problem("HEXK_SB_MISMATCH", $sformatf("stream %0d: the actual item differs from the expected item", idx
                        ), expected, actual, diff);
         return;
      end
      hexk_check_stats::record_pass("HEXK_SB_MISMATCH");
      stream.stats.matched++;
      stream.stats.add_latency_ps(latency_ps);
      if (cfg.max_latency_ps != 0 && latency_ps > cfg.max_latency_ps) begin
         stream.stats.late++;
         report_problem(
             "HEXK_SB_LATENCY", $sformatf(
             "stream %0d: an item was matched after %0t, the limit is %0t", idx, latency_ps, cfg.max_latency_ps),
             expected, null);
      end
   endfunction : finish_pair

   // Reports an error about one or two items, either may be null; diff may explain a difference.
   // The items are printed for the first cfg.max_errors errors only, and their text is built only then.
   local function void report_problem(string id, string headline, T expected, T actual, string diff = "");
      string details[$];
      if (detailed_errors >= cfg.max_errors) begin
         uvm_report_error(id, $sformatf("%s (items are not printed after %0d errors)", headline, cfg.max_errors),
                          UVM_NONE, `uvm_file, `uvm_line);
         return;
      end
      detailed_errors++;
      details.push_back(headline);
      if (expected != null) begin
         details.push_back({"expected", uid_text(expected), ":\n", item_text(expected)});
      end
      if (actual != null) begin
         details.push_back({"actual", uid_text(actual), ":\n", item_text(actual)});
      end
      if (diff.len() != 0) begin
         details.push_back({"difference: ", diff});
      end
      uvm_report_error(id, hexk_str::join_str(details, "\n"), UVM_NONE, `uvm_file, `uvm_line);
   endfunction : report_problem

   // Reports a stream that holds more waiting items than cfg.max_outstanding, once per excursion.
   // Called whenever the number of waiting items of the stream changed, so that an excursion is seen to end.
   local function void check_outstanding(stream_t stream, int idx);
      int unsigned waiting = stream.num_expected + stream.num_actual;
      if (cfg.max_outstanding == 0 || waiting <= cfg.max_outstanding) begin
         stream.outstanding_reported = 0;
         return;
      end
      if (!stream.outstanding_reported) begin
         stream.outstanding_reported = 1;
         `uvm_error("HEXK_SB_OUTSTANDING", $sformatf("stream %0d: %0d items are waiting, the limit is %0d", idx,
                                                     waiting, cfg.max_outstanding))
      end
   endfunction : check_outstanding

   // Reports the expected and the actual items of a stream that never met a partner.
   local function void report_leftovers(int idx);
      stream_t         stream = streams[idx];
      T                items                 [$];
      longint unsigned stamps_ps             [$];
      string           lines                 [$];
      stream.stats.leftover_expected = stream.num_expected;
      stream.stats.leftover_actual   = stream.num_actual;
      if (stream.num_expected != 0) begin
         stream.list_expected(items, stamps_ps, cfg.leftover_print_limit);
         foreach (items[i]) begin
            lines.push_back(
                $sformatf("expected%s, waiting since %0t:\n%s", uid_text(items[i]), stamps_ps[i], item_text(items[i])));
         end
         `uvm_error("HEXK_SB_LEFTOVER",
                    $sformatf("stream %0d: %0d expected items never got an actual item; the first %0d:\n%s", idx,
                              stream.num_expected, items.size(), hexk_str::join_str(lines, "\n")))
      end
      if (stream.num_actual != 0) begin
         items.delete();
         lines.delete();
         stream.list_actual(items, cfg.leftover_print_limit);
         foreach (items[i]) begin
            lines.push_back($sformatf("actual%s:\n%s", uid_text(items[i]), item_text(items[i])));
         end
         `uvm_error("HEXK_SB_LEFTOVER",
                    $sformatf("stream %0d: %0d actual items never got an expected item; the first %0d:\n%s", idx,
                              stream.num_actual, items.size(), hexk_str::join_str(lines, "\n")))
      end
   endfunction : report_leftovers

   // " (<uid>)" for an item that has a unique ID, otherwise nothing.
   local function string uid_text(T item);
      hexk_uid uid = get_uid(item);
      return (uid == null) ? "" : {" (", uid.convert2string(), ")"};
   endfunction : uid_text

endclass : hexk_scoreboard

`endif  // HEXK_SCOREBOARD_SV
