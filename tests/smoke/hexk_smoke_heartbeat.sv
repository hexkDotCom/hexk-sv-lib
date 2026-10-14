// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_heartbeat.sv
//
// Subscriber of the smoke environment that gives the watchdog a heartbeat for every word
// that leaves the FIFO. The environment connects it to the monitor at the output and
// assigns the watchdog; without one it does nothing.

`ifndef HEXK_SMOKE_HEARTBEAT_SV
`define HEXK_SMOKE_HEARTBEAT_SV

class hexk_smoke_heartbeat extends uvm_subscriber #(hexk_smoke_item_t);

   // The watchdog of the test; assigned by the environment.
   hexk_watchdog watchdog;

   `uvm_component_utils(hexk_smoke_heartbeat)

   // Creates the subscriber.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Analysis write: one heartbeat per word.
   function void write(hexk_smoke_item_t t);
      if (watchdog != null) begin
         watchdog.heartbeat(get_full_name());
      end
   endfunction : write

endclass : hexk_smoke_heartbeat

`endif  // HEXK_SMOKE_HEARTBEAT_SV
