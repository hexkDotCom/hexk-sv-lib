// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_checkable.sv
//
// Interface class for objects that have something to check at the end of the test but are
// not components and so have no check_phase: reference models, memory models, the
// bookkeeping of sequences. Implement eot_check in a class and register an object of it
// with hexk_eot_registry::register. The registry calls eot_check once, in check_phase.
// eot_check reports what is left over or wrong with `uvm_error; it must not consume time.
//
//! @module    hexk_eot_registry
//! @since     0.7.0
//! @stability experimental
//! @serves    CHK-5
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CHECKABLE_SV
`define HEXK_CHECKABLE_SV

interface class hexk_checkable;

   // Called once in check_phase: report leftovers and a wrong final state with `uvm_error.
   // The formatter breaks a pure virtual prototype over three lines.
   // verilog_format: off
   pure virtual function void eot_check();
   // verilog_format: on

endclass : hexk_checkable

`endif  // HEXK_CHECKABLE_SV
