// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_watchdog.sv
//
// Watchdog component: ends a test that hangs with one fatal that says what was still going
// on. It has two limits, in whole picoseconds. global_timeout_ps is the longest time the run
// phase may take, a safety net and not the way a test ends; +hexk_timeout=<number><unit>
// overrides it from the command line. inactivity_limit_ps is the longest time without a
// heartbeat; components call
// heartbeat() whenever they make progress, so a test that stops moving is ended long before
// the global timeout. The fatal message holds the reason, the busy objects of the objection
// aggregator given in the member aggregator, and the last heartbeat of every source.
// Create one in the base test and set the limits before the run phase starts.
//
//! @module    hexk_watchdog
//! @since     0.7.0
//! @stability experimental
//! @serves    OBJ-7
//! @emits     HEXK_WATCHDOG:fatal HEXK_WATCHDOG_START:info HEXK_WATCHDOG_ARG:error
//! @plusargs  +hexk_timeout

`ifndef HEXK_WATCHDOG_SV
`define HEXK_WATCHDOG_SV

class hexk_watchdog extends uvm_component;

   // Longest time in picoseconds the run phase may take, counted from its start (1 ms); 0 switches it off.
   longint unsigned          global_timeout_ps          = 1_000_000_000;

   // Longest time in picoseconds without a heartbeat; 0 switches this limit off.
   longint unsigned          inactivity_limit_ps        = 0;

   // Aggregator whose report of busy objects goes into the fatal message; may be null.
   hexk_objection_aggregator aggregator;

   // Time in picoseconds of the latest heartbeat or change of the inactivity limit.
   local longint unsigned    last_activity_ps;

   // Per heartbeat source: time of the latest heartbeat and number of heartbeats; the queue
   // keeps the sources in the order of their first heartbeat.
   local longint unsigned    last_times_ps[string];
   local int unsigned        beat_counts[string];
   local string              sources               [$];

   // Number of calls of set_inactivity_limit(): the inactivity watch waits for it to change. A count and not an
   // event: a wait for a changed count cannot miss a change, and Verilator 5.046 keeps an event that nobody waited
   // for as triggered until the next wait for it.
   local int unsigned        limit_changes;

   `uvm_component_utils(hexk_watchdog)

   // Creates the watchdog; the limits are read when the run phase starts.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Says that the source made progress; any component may call it, as often as it likes.
   function void heartbeat(string source);
      if (!beat_counts.exists(source)) begin
         beat_counts[source] = 0;
         sources.push_back(source);
      end
      beat_counts[source]++;
      last_times_ps[source] = $time;
      last_activity_ps      = $time;
   endfunction : heartbeat

   // Sets the longest time in picoseconds without a heartbeat, counted from now; 0 switches the limit off.
   function void set_inactivity_limit(longint unsigned limit_ps);
      inactivity_limit_ps = limit_ps;
      last_activity_ps    = $time;
      limit_changes       = limit_changes + 1;
   endfunction : set_inactivity_limit

   // Converts a text such as "500us" or "1.5ms" to whole picoseconds, rounded; returns 0 when the text is not
   // <number><unit>, when the time is 2**63 ps or more, and when a time above 0 rounds to 0 ps.
   static function bit parse_timeout(string text, output longint unsigned timeout_ps);
      // 2**63 ps (about 106 days): the times from here on do not fit a longint.
      real             too_long_ps = 9223372036854775808.0;
      int              split = text.len();
      int unsigned     digits = 0;
      int unsigned     dots = 0;
      hexk_time_unit_e unit;
      real             time_ps;
      timeout_ps = 0;
      // The number ends at the first character that is neither a digit nor a decimal point.
      for (int i = 0; i < text.len(); i++) begin
         if (text[i] >= "0" && text[i] <= "9") begin
            digits++;
         end else if (text[i] == ".") begin
            dots++;
         end else begin
            split = i;
            break;
         end
      end
      if (digits == 0 || dots > 1 || !hexk_report_cfg::time_unit_of(text.substr(split, text.len() - 1), unit)) begin
         return 0;
      end
      time_ps = text.substr(0, split - 1).atoreal() * hexk_report_cfg::ps_per_unit(unit);
      if (time_ps >= too_long_ps || (time_ps > 0.0 && time_ps < 0.5)) begin
         return 0;
      end
      timeout_ps = longint'(time_ps);
      return 1;
   endfunction : parse_timeout

   // UVM callback: reads +hexk_timeout and watches both limits until the run phase ends.
   task run_phase(uvm_phase phase);
      apply_plusargs();
      last_activity_ps = $time;
      `uvm_info("HEXK_WATCHDOG_START", $sformatf("global timeout %s, inactivity limit %s", limit_text(global_timeout_ps
                                                 ), limit_text(inactivity_limit_ps)), UVM_MEDIUM)
      fork
         watch_global();
         watch_inactivity();
      join
   endtask : run_phase

   // Takes global_timeout_ps from +hexk_timeout=<number><unit> when the plusarg is given.
   local function void apply_plusargs();
      string           text = hexk_plusarg::get_str("hexk_timeout", "");
      longint unsigned timeout_ps;
      if (text.len() == 0) begin
         return;
      end
      if (parse_timeout(text, timeout_ps)) begin
         global_timeout_ps = timeout_ps;
      end else begin
         `uvm_error("HEXK_WATCHDOG_ARG", $sformatf(
                    "+hexk_timeout=%s is not <number><unit> with unit fs, ps, ns, us, ms or s %s; keeping %s",
                    text,
                    "from 1 ps to below 2**63 ps",
                    limit_text(
                        global_timeout_ps
                    )
                    ))
      end
   endfunction : apply_plusargs

   // Ends the test when the run phase has taken global_timeout_ps.
   local task watch_global();
      if (global_timeout_ps == 0) begin
         return;
      end
      hexk_wait_util::wait_ps(global_timeout_ps);
      expire($sformatf("global timeout of %s reached", time_text(global_timeout_ps)));
   endtask : watch_global

   // Ends the test when there was no heartbeat for inactivity_limit_ps.
   local task watch_inactivity();
      longint unsigned deadline_ps;
      int unsigned     changes;
      forever begin
         changes = limit_changes;
         if (inactivity_limit_ps == 0) begin
            wait (limit_changes != changes);
            continue;
         end
         // A deadline past the largest number is the largest number, which hexk_wait_util never reaches.
         deadline_ps = (last_activity_ps > ~inactivity_limit_ps) ? ~64'd0 : last_activity_ps + inactivity_limit_ps;
         if (deadline_ps > $time) begin
            // Until the deadline or a new limit, then the deadline is computed again: a heartbeat may have moved it.
            // The outer fork keeps "disable fork" to these two branches.
            fork
               begin
                  fork
                     hexk_wait_util::wait_ps(deadline_ps - $time);
                     wait (limit_changes != changes);
                  join_any
                  disable fork;
               end
            join
            continue;
         end
         expire($sformatf("no heartbeat for %s", time_text(inactivity_limit_ps)));
         // Only reached when the fatal was demoted: watch again when a limit is set.
         wait (limit_changes != changes);
      end
   endtask : watch_inactivity

   // Reports the fatal with everything that helps to see why the test did not end.
   local function void expire(string reason);
      string busy = (aggregator == null) ? "no objection aggregator is connected" : aggregator.report_busy();
      `uvm_fatal("HEXK_WATCHDOG", $sformatf(
                 "%s\nBusy objects:\n  %s\nHeartbeats:\n  %s",
                 reason,
                 hexk_str::replace(
                     busy, "\n", "\n  "
                 ),
                 heartbeat_report()
                 ))
   endfunction : expire

   // One line per heartbeat source, in the order of their first heartbeat.
   local function string heartbeat_report();
      string lines[$];
      foreach (sources[i]) begin
         lines.push_back($sformatf(
                         "%s: %0d heartbeats, last at %s, %s ago",
                         sources[i],
                         beat_counts[sources[i]],
                         time_text(
                             last_times_ps[sources[i]]
                         ),
                         time_text(
                             $time - last_times_ps[sources[i]]
                         )
                         ));
      end
      if (lines.size() == 0) begin
         return "no heartbeat was given";
      end
      return hexk_str::join_str(lines, "\n  ");
   endfunction : heartbeat_report

   // A time in picoseconds as nanoseconds with three decimals, such as "1500.000ns".
   local function string time_text(longint unsigned value_ps);
      return $sformatf("%0d.%sns", value_ps / 1000, hexk_str::pad($sformatf("%0d", value_ps % 1000), 3, 0, "0"));
   endfunction : time_text

   // A limit in picoseconds as a time, or "off".
   local function string limit_text(longint unsigned limit_ps);
      if (limit_ps == 0) begin
         return "off";
      end
      return time_text(limit_ps);
   endfunction : limit_text

endclass : hexk_watchdog

`endif  // HEXK_WATCHDOG_SV
