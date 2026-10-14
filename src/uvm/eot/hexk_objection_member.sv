// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_objection_member.sv
//
// One object registered with hexk_objection_aggregator: its handle, its name in reports and
// the raise() calls that are outstanding for it. Internal to hexk_objection_aggregator; users
// go through register(), raise() and drop().
//
//! @module    hexk_objection_aggregator
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_OBJECTION_MEMBER_SV
`define HEXK_OBJECTION_MEMBER_SV

class hexk_objection_member;

   // The registered object.
   hexk_objectable obj;

   // Name given at registration, used in reports.
   string label;

   // Number of raise() calls that have not been matched by a drop() yet.
   int unsigned raise_count;

   // Reason given with the latest raise().
   string why;

endclass : hexk_objection_member

`endif  // HEXK_OBJECTION_MEMBER_SV
