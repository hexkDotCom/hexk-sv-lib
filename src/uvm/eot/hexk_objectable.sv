// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_objectable.sv
//
// Interface class for objects that can keep a run-time phase from ending: a scoreboard with
// expected items outstanding, a model with a transfer in flight, a monitor inside a burst.
// Implement is_busy and busy_reason in a class and register an object of it with
// hexk_objection_aggregator::register. The aggregator asks is_busy when a phase is ready to
// end and holds the phase while the answer is 1; busy_reason goes into the report of who is
// still busy. Both functions are called often and from the phasing code: they must be cheap
// and must not report, block or change state.
//
//! @module    hexk_objection_aggregator
//! @since     0.7.0
//! @stability experimental
//! @serves    OBJ-2
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_OBJECTABLE_SV
`define HEXK_OBJECTABLE_SV

interface class hexk_objectable;

   // The formatter breaks a pure virtual prototype over three lines.
   // verilog_format: off

   // 1 while the object has work outstanding that must finish before the phase may end.
   pure virtual function bit is_busy();

   // What the object is waiting for, for the report of busy objects; may have several lines.
   pure virtual function string busy_reason();

   // verilog_format: on

endclass : hexk_objectable

`endif  // HEXK_OBJECTABLE_SV
