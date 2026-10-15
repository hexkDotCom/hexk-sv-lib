// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_wait_macros.svh
//
// Waits that cannot hang: wait for a condition, or run some statements, with a time limit
// after which a UVM error (or fatal) with the caller's message ID is reported.
// `hexk_wait_timeout(vif.ready, 10us, "MY_READY") waits for the condition and reports when
// it is not true after the timeout; execution continues after the macro in both cases.
// `hexk_spinwait(wait_for_idle();, 1ms, "MY_IDLE") runs the statements and ends them when
// they take longer. The timeout is a time in the scope of the caller, best written as a
// literal with a unit. `hexk_ps(T) turns such a time into the whole picoseconds that the
// classes of the library take (hexk_wait_util, the watchdog, the scoreboard). Each macro is
// one complete statement like the `uvm_* macros: write no semicolon after it. The macros are
// tasks in effect: use them where time may pass.
// Threads that the caller started before the macro are never killed by it.
// Include this file through hexk_macros.svh.
//
//! @module    hexk_wait_macros
//! @since     0.7.0
//! @stability experimental
//! @serves    OBJ-7 MSG-8
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_WAIT_MACROS_SVH
`define HEXK_WAIT_MACROS_SVH

// The timers of the macros wait through hexk_wait_util::wait_ps(), with TIMEOUT in whole picoseconds of the
// calling scope: a delay written in a class with a type parameter is in the wrong unit on VCS X-2025.06, and a
// limit after hexk_wait_util::LAST_PS is never reached. At the timeout they wait for the nonblocking assignments of
// that time step before they decide (one round of them): a condition set by them counts.

// Internal: waits for a condition with a time limit and reports with the given severity.
// A condition that is X or Z is not true: wait() goes on waiting for it, so the timeout must report it too.
`define hexk_wait_or_report(COND, TIMEOUT, ID, SEVERITY) \
   begin \
      fork \
         begin \
            fork \
               wait (COND); \
               begin \
                  hexk_uvm_pkg::hexk_wait_util::wait_ps(`hexk_ps(TIMEOUT)); \
                  uvm_pkg::uvm_wait_for_nba_region(); \
                  if (COND) begin \
                  end else begin \
                     `hexk_check_report(SEVERITY, ID, $sformatf("timeout after %0t waiting for: %s", \
                        TIMEOUT, `"COND`")) \
                  end \
               end \
            join_any \
            disable fork; \
         end \
      join \
   end

// Internal: runs statements with a time limit and reports with the given severity.
`define hexk_spin_or_report(BODY, TIMEOUT, ID, SEVERITY) \
   begin \
      fork \
         begin \
            fork \
               begin \
                  BODY \
               end \
               begin \
                  hexk_uvm_pkg::hexk_wait_util::wait_ps(`hexk_ps(TIMEOUT)); \
                  uvm_pkg::uvm_wait_for_nba_region(); \
                  `hexk_check_report(SEVERITY, ID, $sformatf("timeout after %0t: the statements did not finish", \
                     TIMEOUT)) \
               end \
            join_any \
            disable fork; \
         end \
      join \
   end

// The time T of the calling scope as a whole number of picoseconds, for the _ps arguments of the library.
// Dividing by 1s gives seconds whatever the time unit of the caller is.
`define hexk_ps(T) longint'(((T) / 1s) * 1.0e12)

// Waits until COND is true; reports an error with ID if it is not true after TIMEOUT.
`define hexk_wait_timeout(COND, TIMEOUT, ID) `hexk_wait_or_report(COND, TIMEOUT, ID, uvm_pkg::UVM_ERROR)

// Waits until COND is true; reports a fatal with ID if it is not true after TIMEOUT.
`define hexk_wait_timeout_fatal(COND, TIMEOUT, ID) `hexk_wait_or_report(COND, TIMEOUT, ID, uvm_pkg::UVM_FATAL)

// Runs BODY, one or more statements with their semicolons; ends them with an error if they take longer than TIMEOUT.
`define hexk_spinwait(BODY, TIMEOUT, ID) `hexk_spin_or_report(BODY, TIMEOUT, ID, uvm_pkg::UVM_ERROR)

`endif  // HEXK_WAIT_MACROS_SVH
