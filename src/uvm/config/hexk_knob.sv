// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_knob.sv
//
// One knob of hexk_knobs: its kind, value, where the value came from, and the limits a value
// must keep. Internal to hexk_knobs; users go through its add, set and get functions.
//
//! @module    hexk_knobs
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_KNOB_SV
`define HEXK_KNOB_SV

class hexk_knob;

   // What a knob holds: an integer, a bit, any string, or one string of a list.
   typedef enum bit [1:0] {
      HEXK_KNOB_INT,
      HEXK_KNOB_BIT,
      HEXK_KNOB_STR,
      HEXK_KNOB_ENUM_STR
   } kind_e;

   // Where the value of a knob came from, from the weakest to the strongest.
   typedef enum bit [1:0] {
      HEXK_KNOB_FROM_DEFAULT,
      HEXK_KNOB_FROM_SET,
      HEXK_KNOB_FROM_PLUSARG
   } source_e;

   // Name of the knob, which is also the name of its plusarg.
   string   label;

   // Kind of the knob.
   kind_e   kind;

   // Value of an integer or bit knob.
   longint  int_value;

   // Value of a string knob.
   string   str_value;

   // Where the value came from.
   source_e source;

   // One line that says what the knob does.
   string   help_text;

   // Lower limit of an integer knob; no limits when hi is below lo.
   longint  lo;
   // Upper limit of an integer knob.
   longint  hi;

   // Legal values of a knob of kind HEXK_KNOB_ENUM_STR.
   string   legal     [$];

   // $typename of the enumeration of a knob that hexk_enum_knob defined; empty for any other knob.
   string   enum_type;

endclass : hexk_knob

`endif  // HEXK_KNOB_SV
