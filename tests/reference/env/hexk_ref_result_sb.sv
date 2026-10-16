// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_result_sb.sv
//
// The scoreboard of the packet results: hexk_scoreboard keyed by the packet number, with the
// latency counted from the moment the predictor knew the result (the timestamp of its meta item).

`ifndef HEXK_REF_RESULT_SB_SV
`define HEXK_REF_RESULT_SB_SV

// The scoreboard of packet results: keyed by the packet number, with the latency counted from the
// moment the predictor knew the result.
class hexk_ref_result_sb extends hexk_scoreboard #(
    .T  (hexk_ref_meta_result_t),
    .KEY(int unsigned)
);

   `uvm_component_utils(hexk_ref_result_sb)

   // Creates the scoreboard.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Hook: the packet number.
   virtual function int unsigned get_key(hexk_ref_meta_result_t item);
      return item.item.number;
   endfunction : get_key

   // Hook: the time at which the predictor wrapped the expected result.
   virtual function longint unsigned get_timestamp_ps(hexk_ref_meta_result_t item);
      return item.timestamp_ps;
   endfunction : get_timestamp_ps

endclass : hexk_ref_result_sb

`endif  // HEXK_REF_RESULT_SB_SV
