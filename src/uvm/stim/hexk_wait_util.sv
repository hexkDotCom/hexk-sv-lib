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
// `hexk_ps(10us) or as 10_000_000. now_ps() gives the simulation time in picoseconds.
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

   // The simulation time in picoseconds.
   static function longint unsigned now_ps();
      // The time unit of the package is 1ps, so $time is a number of picoseconds here.
      return $time;
   endfunction : now_ps

   // Waits until flag is 1 or timeout_ps has passed; timed_out is 1 when the timeout came first.
   static task wait_or_timeout(ref bit flag, input longint unsigned timeout_ps, output bit timed_out);
      bit expired;
      // The timer thread may only use local variables: a ref argument must not be used in a
      // join_none block. The outer fork keeps "disable fork" away from the caller's threads.
      fork
         begin
            fork
               begin
                  #(timeout_ps);
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
                  #(timeout_ps);
                  expired = 1;
               end
            join_any
            disable fork;
         end
      join
      timed_out = expired;
   endtask : wait_event_or_timeout

endclass : hexk_wait_util

`endif  // HEXK_WAIT_UTIL_SV
