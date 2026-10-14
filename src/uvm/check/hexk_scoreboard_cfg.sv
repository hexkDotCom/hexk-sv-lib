// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_scoreboard_cfg.sv
//
// Configuration of one hexk_scoreboard: how items are matched, how many independent streams
// it has, and what it reports. The env creates it, sets what differs from the defaults and
// assigns it to the member cfg of the scoreboard before the build phase of the scoreboard.
// The defaults give an in-order scoreboard with one stream that treats an actual item
// without an expected one as an error and keeps the test alive while items are outstanding.
//
//! @module    hexk_scoreboard
//! @since     0.7.0
//! @stability experimental
//! @serves    CFG-1 CHK-4
//! @emits     HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_SCOREBOARD_CFG_SV
`define HEXK_SCOREBOARD_CFG_SV

// How a hexk_scoreboard pairs an actual item with an expected one.
typedef enum {
   // The oldest expected item of the stream.
   HEXK_SB_IN_ORDER,
   // An expected item with the same key that compares equal, the oldest such one.
   HEXK_SB_OUT_OF_ORDER,
   // The oldest expected item with the same key.
   HEXK_SB_IN_ORDER_PER_KEY
} hexk_sb_mode_e;

class hexk_scoreboard_cfg extends uvm_object;

   // How actual and expected items are paired.
   hexk_sb_mode_e   mode                 = HEXK_SB_IN_ORDER;

   // Number of independent pairs of an expected and an actual stream.
   int unsigned     num_streams          = 1;

   // Number of errors that are reported with the items printed; later ones are reported in one line.
   int unsigned     max_errors           = 10;

   // Largest number of items that may wait in one stream; more is an error. 0 means no limit.
   int unsigned     max_outstanding      = 0;

   // Longest time in picoseconds between an expected item and the actual item it is matched with; a pair that
   // took longer is an error at the moment it is matched. 0 means no limit. This is no deadline: an expected
   // item that never gets its actual item is reported in the check phase, and a watchdog ends a test that
   // waits for it.
   longint unsigned max_latency_ps       = 0;

   // When 1, an actual item may come before its expected item and waits for it; when 0 that is an error.
   bit              allow_unexpected     = 0;

   // When 1, the scoreboard is busy for the objection aggregator while items are waiting.
   bit              hold_objection       = 1;

   // When 1, on_reset() drops all waiting items.
   bit              flush_on_reset       = 1;

   // Number of leftover items per stream and direction that check_phase prints.
   int unsigned     leftover_print_limit = 20;

   // When 1, the scoreboard keeps a clone of an expected item that has to wait, for a producer that reuses or
   // changes its objects after writing them; when 0 it keeps the handle it was given.
   bit              clone_expected       = 0;

   `uvm_object_utils(hexk_scoreboard_cfg)

   // Creates a cfg with the defaults.
   function new(string name = "hexk_scoreboard_cfg");
      super.new(name);
   endfunction : new

   // All settings on one line.
   function string convert2string();
      // Two calls with literal formats: Verilator 5.046 garbles $sformatf with a format that is a concatenation.
      string sizes = $sformatf(
          "mode=%s num_streams=%0d max_errors=%0d max_outstanding=%0d max_latency_ps=%0d",
          mode.name(),
          num_streams,
          max_errors,
          max_outstanding,
          max_latency_ps
      );
      return {
         sizes,
         $sformatf(
             " allow_unexpected=%0d hold_objection=%0d flush_on_reset=%0d leftover_print_limit=%0d clone_expected=%0d",
             allow_unexpected,
             hold_objection,
             flush_on_reset,
             leftover_print_limit,
             clone_expected
         )
      };
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member.
   function void do_copy(uvm_object rhs);
      hexk_scoreboard_cfg other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      mode                 = other.mode;
      num_streams          = other.num_streams;
      max_errors           = other.max_errors;
      max_outstanding      = other.max_outstanding;
      max_latency_ps       = other.max_latency_ps;
      allow_unexpected     = other.allow_unexpected;
      hold_objection       = other.hold_objection;
      flush_on_reset       = other.flush_on_reset;
      leftover_print_limit = other.leftover_print_limit;
      clone_expected       = other.clone_expected;
   endfunction : do_copy

endclass : hexk_scoreboard_cfg

`endif  // HEXK_SCOREBOARD_CFG_SV
