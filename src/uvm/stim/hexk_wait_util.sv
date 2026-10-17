// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_wait_util.sv
//
// Waits with a time limit as static tasks, for code that wants the outcome as a value
// instead of a reported error: wait for a bit to become 1, or for an event, and learn
// through timed_out which came first. Call them as hexk_wait_util::wait_or_timeout(...).
// Threads that the caller started before the call are never killed.
// The timeout is a whole number of picoseconds, like every time that crosses the API of the
// library, so it means the same whatever the time unit of the caller is; write it as
// `hexk_ps(10us) or as 10_000_000. now_ps() gives the simulation time in picoseconds, and
// format_ps() formats a time in picoseconds as %t does.
// To report a UVM error on timeout, use the macros of hexk_wait_macros.svh instead.
//
//! @module    hexk_wait_macros
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_WAIT_UTIL_SV
`define HEXK_WAIT_UTIL_SV

virtual class hexk_wait_util;

   // Largest simulation time in picoseconds that every simulator schedules: one of them keeps the time as a signed
   // 64-bit number of steps of the simulation resolution, which may be as fine as 1 fs (about 2.56 hours).
   localparam longint unsigned LAST_PS = 64'h7FFF_FFFF_FFFF_FFFF / 1000;

   // Never triggered: what a wait past LAST_PS waits for. A lint rule reports an event that nothing triggers.
   // verilator lint_off UNDRIVEN
   local static event never;
   // verilator lint_on UNDRIVEN

   // The simulation time in picoseconds.
   static function longint unsigned now_ps();
      // The time unit of the package is 1ps, so $time is a number of picoseconds here.
      return $time;
   endfunction : now_ps

   // A time in picoseconds as %t formats it, in the unit and format that $timeformat set. Classes with a type
   // parameter format a time through this function and read it through now_ps(): Questa 2024.1 takes $time and %t
   // in such a class in the time unit of the scope that declares the type given as parameter.
   static function string format_ps(longint unsigned value_ps);
      return $sformatf("%0t", value_ps);
   endfunction : format_ps

   // Waits duration_ps picoseconds; 0 returns at once. Classes with a type parameter delay through this task:
   // VCS X-2025.06 scales a delay written in such a class by the time unit of the scope that declares the type
   // given as parameter, and a delay here is always in picoseconds.
   static task wait_ps(longint unsigned duration_ps);
      if (duration_ps != 0) begin
         sleep_ps(duration_ps);
      end
   endtask : wait_ps

   // Waits until flag is 1 or timeout_ps has passed; timed_out is 1 when the timeout came first.
   static task wait_or_timeout(ref bit flag, input longint unsigned timeout_ps, output bit timed_out);
      bit expired;
      // The timer thread may only use local variables: a ref argument must not be used in a
      // join_none block. The outer fork keeps "disable fork" away from the caller's threads.
      fork
         begin
            fork
               begin
                  sleep_ps(timeout_ps);
                  expired = 1;
               end
            join_none
            wait (flag || expired);
            disable fork;
         end
      join
      timed_out = !flag;
   endtask : wait_or_timeout

   // Waits until the event is triggered or timeout_ps has passed; timed_out is 1 when the timeout came first.
   static task wait_event_or_timeout(event e, longint unsigned timeout_ps, output bit timed_out);
      bit expired;
      fork
         begin
            fork
               @(e);
               begin
                  sleep_ps(timeout_ps);
                  expired = 1;
               end
            join_any
            disable fork;
         end
      join
      timed_out = expired;
   endtask : wait_event_or_timeout

   // 1 when a wait of duration_ps picoseconds that starts at from_ps would end after LAST_PS, so that it never ends;
   // a wait of 0 never does.
   static function bit ends_after_last(longint unsigned duration_ps, longint unsigned from_ps);
      return duration_ps != 0 && (from_ps > LAST_PS || duration_ps > LAST_PS - from_ps);
   endfunction : ends_after_last

   // The delay of every wait: duration_ps picoseconds, or for ever when that would end after LAST_PS.
   local static task sleep_ps(longint unsigned duration_ps);
      if (ends_after_last(duration_ps, $time)) begin
         @(never);
      end else begin
         // FIL-7 waived: duration_ps counts in the time unit of the package (1ps); "* 1ps" would pass through a
         // real and lose whole picoseconds above 2**53 ps, below LAST_PS.
         #(duration_ps);
      end
   endtask : sleep_ps

endclass : hexk_wait_util

`endif  // HEXK_WAIT_UTIL_SV
