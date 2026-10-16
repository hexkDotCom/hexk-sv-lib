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
// not end before the last item has arrived; on_reset() drops what is waiting. With
// cfg.max_wait_ps, an item that waits longer for its partner is an error and is dropped
// (run_phase watches the waiting items; a derived class that overrides run_phase calls
// super.run_phase).
//
//! @module    hexk_scoreboard
//! @since     0.7.0
//! @stability experimental
//! @serves    CHK-2 CHK-3 CHK-4 CHK-5 CHK-6 OBJ-2 MSG-7
//! @emits     HEXK_SB_MISMATCH:error HEXK_SB_UNEXPECTED:error HEXK_SB_LEFTOVER:error HEXK_SB_LATENCY:error
//! @emits     HEXK_SB_OUTSTANDING:error HEXK_SB_STREAM:error HEXK_SB_AGGREGATOR:warning
//! @emits     HEXK_SB_SUMMARY:info HEXK_SB_FLUSH:info HEXK_SB_CLONE:error HEXK_SB_TIMEOUT:error
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

   // cfg.max_wait_ps at the build phase; 0 when items may wait without a limit.
   local longint unsigned                                        max_wait_ps;

   // Triggered when an item starts to wait, for run_phase while it has nothing to watch.
   local event                                                   item_stored;

   // Key of every item in mode HEXK_SB_IN_ORDER, where the streams ignore keys: the value a KEY
   // has without an assignment. A lint rule reports a variable that is never assigned.
   // verilator lint_off UNDRIVEN
   local KEY                                                     common_key;
   // verilator lint_on UNDRIVEN

   // Number of errors that were reported with the items printed.
   local int unsigned                                            detailed_errors;

   // The comparer of the default compare_items(), one for all comparisons: compare() starts it afresh.
   local uvm_comparer                                            default_comparer;

   // The last pair that the default is_partner() compared, and whether it was equal. find_partner() clears it
   // before a search and reads it for the pair it returns, so that a pair found equal is not compared again.
   local T                                                       partner_exp;
   local T                                                       partner_act;
   local bit                                                     partner_equal;

   `uvm_component_param_utils(hexk_scoreboard#(T, KEY))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_scoreboard";
   endfunction : get_type_name

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
      return hexk_wait_util::now_ps();
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
      stream_t         stream = stream_of(idx);
      T                item;
      T                actual;
      KEY              key;
      int              position;
      bit              known_equal;
      longint unsigned arrived_ps;
      if (stream == null) begin
         return;
      end
      item = transform_expected(t);
      if (item == null) begin
         return;
      end
      stream.stats.expected_count++;
      drop_overdue_before_write(idx);
      key      = key_of(item);
      position = find_partner(stream, key, item, 1, known_equal);
      if (position >= 0) begin
         // The actual item came first: the latency runs from the timestamp of the expected item to its arrival.
         actual = stream.take_actual(key, $unsigned(position), arrived_ps);
         finish_pair(stream, idx, item, actual, get_timestamp_ps(item), arrived_ps, known_equal);
         check_outstanding(stream, idx);
         return;
      end
      stream.store_expected(key, kept_expected(item), get_timestamp_ps(item));
      if (max_wait_ps != 0) begin
         ->item_stored;
      end
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
      bit              known_equal;
      longint unsigned stamp_ps;
      T                expected;
      if (stream == null || t == null) begin
         return;
      end
      stream.stats.actual_count++;
      drop_overdue_before_write(idx);
      key      = key_of(t);
      position = find_partner(stream, key, t, 0, known_equal);
      if (position < 0 && cfg.allow_unexpected) begin
         stream.store_actual(key, t, hexk_wait_util::now_ps());
         if (max_wait_ps != 0) begin
            ->item_stored;
         end
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
         position    = 0;
         known_equal = 0;
      end
      expected = stream.take_expected(key, $unsigned(position), stamp_ps);
      finish_pair(stream, idx, expected, t, stamp_ps, hexk_wait_util::now_ps(), known_equal);
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

   // A copy of the counters of one stream, or of all streams together when stream is below 0; later items do not
   // change it. A stream that does not exist is an error and gives counters that are all 0.
   function hexk_sb_stats get_stats(int stream = -1);
      hexk_sb_stats total = new();
      stream_t      one;
      if (stream >= 0) begin
         one = stream_of(stream);
         if (one != null) begin
            total.add(one.stats);
         end
         return total;
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
         oldest_ps = streams[i].oldest_expected_stamp_ps(found);
         lines.push_back($sformatf(
                         "stream %0d: %0d expected and %0d actual items are waiting%s",
                         i,
                         streams[i].num_expected,
                         streams[i].num_actual,
                         found ? {", the oldest expected one since ", hexk_wait_util::format_ps(
                             oldest_ps
                         )} : ""
                         ));
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : busy_reason

   // UVM callback: takes the cfg that was assigned, else the one in uvm_config_db under "cfg", else one with the
   // defaults; then creates the streams and their exports.
   function void build_phase(uvm_phase phase);
      int unsigned count;
      super.build_phase(phase);
      if (cfg == null) begin
         void'(uvm_config_db#(hexk_scoreboard_cfg)::get(this, "", "cfg", cfg));
      end
      if (cfg == null) begin
         cfg = hexk_scoreboard_cfg::type_id::create("cfg");
      end
      mode        = cfg.mode;
      max_wait_ps = cfg.max_wait_ps;
      count       = cfg.num_streams;
      if (count == 0) begin
         `uvm_error("HEXK_SB_STREAM", "cfg.num_streams is 0; one stream is created")
         count = 1;
      end
      for (int unsigned i = 0; i < count; i++) begin
         stream_t stream = new(mode != HEXK_SB_IN_ORDER, max_wait_ps != 0);
         hexk_analysis_imp_indexed_expected_idx #(
             .T  (T),
             .IMP(this_t)
         ) expected_imp;
         hexk_analysis_imp_indexed_actual_idx #(
             .T  (T),
             .IMP(this_t)
         ) actual_imp;
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

   // UVM callback: with cfg.max_wait_ps, drops every item when it has waited that long for its partner, with an
   // error. It sleeps until the oldest waiting item reaches the limit, or until an item starts to wait.
   task run_phase(uvm_phase phase);
      longint unsigned next_ps;
      super.run_phase(phase);
      if (max_wait_ps == 0) begin
         return;
      end
      forever begin
         if (drop_overdue(next_ps)) begin
            hexk_wait_util::wait_ps(next_ps - hexk_wait_util::now_ps());
         end else begin
            @(item_stored);
         end
      end
   endtask : run_phase

   // UVM callback: reports the items that were left over on either side, and the summary.
   function void check_phase(uvm_phase phase);
      string lines[$];
      super.check_phase(phase);
      foreach (streams[i]) begin
         report_leftovers(i);
         lines.push_back($sformatf(
                         "stream %0d: %s; latency min %s, mean %s, max %s",
                         i,
                         streams[i].stats.convert2string(),
                         hexk_wait_util::format_ps(
                             streams[i].stats.latency_min_ps
                         ),
                         hexk_wait_util::format_ps(
                             streams[i].stats.latency_avg_ps()
                         ),
                         hexk_wait_util::format_ps(
                             streams[i].stats.latency_max_ps
                         )
                         ));
      end
      `uvm_info("HEXK_SB_SUMMARY", {"\n", hexk_str::join_str(lines, "\n")}, UVM_LOW)
   endfunction : check_phase

   // The stream with this number, or null and an error.
   local function stream_t stream_of(int idx);
      // A string variable and not ?: of two literals in the arguments, where the literals are packed values and the
      // shorter one is padded with NULs.
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

   // Position of the waiting partner of an item under its key, or -1 when there is none. With as_expected the item
   // is an expected one and looks among the actual items, otherwise the reverse. known_equal is 1 when the default
   // is_partner() found the returned pair equal, so that it need not be compared again.
   local function int find_partner(stream_t stream, KEY key, T item, bit as_expected, output bit known_equal);
      int unsigned count = as_expected ? stream.num_actual_for(key) : stream.num_expected_for(key);
      T            expected;
      T            actual;
      known_equal = 0;
      if (count == 0) begin
         return -1;
      end
      if (mode != HEXK_SB_OUT_OF_ORDER) begin
         return 0;
      end
      partner_equal = 0;
      for (int unsigned i = 0; i < count; i++) begin
         expected = as_expected ? item : stream.peek_expected(key, i);
         actual   = as_expected ? stream.peek_actual(key, i) : item;
         if (is_partner(expected, actual)) begin
            known_equal = partner_equal && partner_exp == expected && partner_act == actual;
            return int'(i);
         end
      end
      return -1;
   endfunction : find_partner

   // Compares a pair, counts it here and as a check in hexk_check_stats, and reports a mismatch or a latency above
   // the limit. The latency runs from stamp_ps, the timestamp of the expected item, to arrived_ps, the arrival of
   // the actual item. With known_equal the search for the pair has compared it already, and it is not compared again.
   local function void finish_pair(stream_t stream, int idx, T expected, T actual, longint unsigned stamp_ps,
                                   longint unsigned arrived_ps, bit known_equal);
      string           diff;
      // A timestamp after the arrival, such as that of an expected item written after its actual item, is a latency
      // of 0.
      longint unsigned latency_ps = (arrived_ps > stamp_ps) ? arrived_ps - stamp_ps : 0;
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
         report_problem("HEXK_SB_LATENCY", $sformatf(
                        "stream %0d: an item was matched after %s, the limit is %s",
                        idx,
                        hexk_wait_util::format_ps(
                            latency_ps
                        ),
                        hexk_wait_util::format_ps(
                            cfg.max_latency_ps
                        )
                        ), expected, null);
      end
   endfunction : finish_pair

   // Reports an error about one or two items, either may be null; diff may explain a difference.
   // The items are printed for the first cfg.max_errors errors only, and their text is built only then.
   local function void report_problem(string id, string headline, T expected, T actual, string diff = "");
      if (detailed_errors >= cfg.max_errors) begin
         `uvm_error(id, $sformatf("%s (items are not printed after %0d errors)", headline, cfg.max_errors))
         return;
      end
      detailed_errors++;
      // The macro builds the text only when the error is reported.
      `uvm_error(id, problem_text(headline, expected, actual, diff))
   endfunction : report_problem

   // The text of an error of report_problem(): the headline, then each item that is not null, then the difference.
   local function string problem_text(string headline, T expected, T actual, string diff);
      string details[$];
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
      return hexk_str::join_str(details, "\n");
   endfunction : problem_text

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

   // Drops the items that have waited longer than max_wait_ps, with an error each. Returns 1 when items still wait,
   // with next_ps the time in picoseconds at which the oldest of them is overdue.
   local function bit drop_overdue(output longint unsigned next_ps);
      longint unsigned due_ps;
      bit              waiting = 0;
      next_ps = 0;
      foreach (streams[i]) begin
         if (drop_overdue_in(i, due_ps) && (!waiting || due_ps < next_ps)) begin
            next_ps = due_ps;
            waiting = 1;
         end
      end
      return waiting;
   endfunction : drop_overdue

   // Before a write is matched: drops the overdue items of its stream, so that whether an item is overdue does not
   // depend on whether run_phase or the writer runs first in a time step.
   local function void drop_overdue_before_write(int idx);
      longint unsigned due_ps;
      if (max_wait_ps != 0) begin
         void'(drop_overdue_in(idx, due_ps));
      end
   endfunction : drop_overdue_before_write

   // drop_overdue() for one stream: 1 when items still wait in it, with due_ps the time it is overdue, in
   // picoseconds.
   // A function of its own, which ends with return: Verilator 5.046 loses the effect of a break out of this
   // loop inside the loop over the streams.
   local function bit drop_overdue_in(int idx, output longint unsigned due_ps);
      stream_t         stream = streams[idx];
      KEY              key;
      bit              is_actual;
      int unsigned     position;
      longint unsigned written_ps;
      longint unsigned stamp_ps;
      T                item;
      due_ps = 0;
      while (stream.oldest_wait(
          key, is_actual, position, written_ps
      )) begin
         // Overdue 1 ps after the limit: an item may wait max_wait_ps. A time after hexk_wait_util::LAST_PS is never
         // reached, here as in the waits of run_phase: the item then never times out.
         due_ps = (max_wait_ps == ~64'd0 || hexk_wait_util::ends_after_last(max_wait_ps + 1, written_ps)) ? ~64'd0 :
             written_ps + max_wait_ps + 1;
         if (due_ps > hexk_wait_util::now_ps()) begin
            return 1;
         end
         stream.stats.timed_out++;
         if (is_actual) begin
            item = stream.take_actual(key, position, stamp_ps);
            report_problem("HEXK_SB_TIMEOUT", $sformatf(
                           "stream %0d: an actual item got no expected item within %s (waiting since %s); dropped",
                           idx,
                           hexk_wait_util::format_ps(
                               max_wait_ps
                           ),
                           hexk_wait_util::format_ps(
                               written_ps
                           )
                           ), null, item);
         end else begin
            item = stream.take_expected(key, position, stamp_ps);
            report_problem("HEXK_SB_TIMEOUT", $sformatf(
                           "stream %0d: an expected item got no actual item within %s (waiting since %s); dropped",
                           idx,
                           hexk_wait_util::format_ps(
                               max_wait_ps
                           ),
                           hexk_wait_util::format_ps(
                               written_ps
                           )
                           ), item, null);
         end
         check_outstanding(stream, idx);
      end
      return 0;
   endfunction : drop_overdue_in

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
            lines.push_back($sformatf(
                            "expected%s, waiting since %s:\n%s",
                            uid_text(
                                items[i]
                            ),
                            hexk_wait_util::format_ps(
                                stamps_ps[i]
                            ),
                            item_text(
                                items[i]
                            )
                            ));
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
