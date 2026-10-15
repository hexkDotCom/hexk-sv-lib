// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_sb_stats.sv
//
// Counters of one stream of a hexk_scoreboard, or of all its streams together: how many
// items were written, matched, mismatched, unexpected, dropped by a flush, timed out or left
// over, and the latency between an expected item and its actual item.
// hexk_scoreboard::get_stats() returns one. A test uses it for the positive proof that work
// happened (guide rule TST-6): no errors and a matched count above zero.
//
//! @module    hexk_scoreboard
//! @since     0.7.0
//! @stability experimental
//! @serves    TST-6
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_SB_STATS_SV
`define HEXK_SB_STATS_SV

class hexk_sb_stats;

   // Expected items written, after transform_expected().
   int unsigned expected_count;

   // Actual items written.
   int unsigned actual_count;

   // Pairs that compared equal.
   int unsigned matched;

   // Pairs that did not compare equal.
   int unsigned mismatched;

   // Actual items that had no expected item and were not allowed to wait.
   int unsigned unexpected;

   // Waiting items that on_reset() dropped.
   int unsigned dropped;

   // Matched pairs whose latency was above max_latency_ps.
   int unsigned late;

   // Waiting items that were dropped because they waited longer than max_wait_ps.
   int unsigned timed_out;

   // Expected and actual items that were still waiting in check_phase.
   int unsigned leftover_expected;
   int unsigned leftover_actual;

   // Smallest, largest and summed latency of the matched pairs, in picoseconds.
   longint unsigned latency_min_ps;
   longint unsigned latency_max_ps;
   longint unsigned latency_sum_ps;

   // Notes the latency in picoseconds of one matched pair.
   function void add_latency_ps(longint unsigned latency_ps);
      if (matched == 1 || latency_ps < latency_min_ps) begin
         latency_min_ps = latency_ps;
      end
      if (matched == 1 || latency_ps > latency_max_ps) begin
         latency_max_ps = latency_ps;
      end
      latency_sum_ps += latency_ps;
   endfunction : add_latency_ps

   // Mean latency of the matched pairs in picoseconds, rounded down; 0 when there is none.
   function longint unsigned latency_avg_ps();
      if (matched == 0) begin
         return 0;
      end
      return latency_sum_ps / longint'(matched);
   endfunction : latency_avg_ps

   // Adds the counts of another stream to these.
   function void add(hexk_sb_stats other);
      if (other.matched != 0) begin
         if (matched == 0 || other.latency_min_ps < latency_min_ps) begin
            latency_min_ps = other.latency_min_ps;
         end
         if (matched == 0 || other.latency_max_ps > latency_max_ps) begin
            latency_max_ps = other.latency_max_ps;
         end
      end
      expected_count += other.expected_count;
      actual_count += other.actual_count;
      matched += other.matched;
      mismatched += other.mismatched;
      unexpected += other.unexpected;
      dropped += other.dropped;
      late += other.late;
      timed_out += other.timed_out;
      leftover_expected += other.leftover_expected;
      leftover_actual += other.leftover_actual;
      latency_sum_ps += other.latency_sum_ps;
   endfunction : add

   // The counts on one line, without the latency.
   function string convert2string();
      return $sformatf(
          "%0d expected, %0d actual, %0d matched, %0d mismatched, %0d unexpected, %0d dropped, %0d late, %s",
          expected_count,
          actual_count,
          matched,
          mismatched,
          unexpected,
          dropped,
          late,
          $sformatf(
              "%0d timed out, %0d expected and %0d actual left over", timed_out, leftover_expected, leftover_actual
          )
      );
   endfunction : convert2string

endclass : hexk_sb_stats

`endif  // HEXK_SB_STATS_SV
