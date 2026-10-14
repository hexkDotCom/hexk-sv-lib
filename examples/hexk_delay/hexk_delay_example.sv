// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_example.sv
//
// Minimal use of hexk_delay: a driver loop that waits a random number of clock cycles
// between two items. The delay cfg would normally be a member of the agent cfg; here it is
// made bursty by hand: bursts of 2 to 4 items back to back, then a gap of 5 to 10 cycles.
// A second generator with the same cfg and another name gets other delays of the same kind.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_delay_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay;
   import hexk_uvm_pkg::hexk_delay_cfg;
   import hexk_uvm_pkg::HEXK_DELAY_BURSTY;
   `include "uvm_macros.svh"

   localparam int unsigned NUM_ITEMS = 12;

   bit            clk;
   hexk_delay_cfg gap_cfg;
   hexk_delay     gap;
   hexk_delay     response_time;

   always #5ns clk = !clk;

   initial begin
      gap_cfg               = hexk_delay_cfg::type_id::create("gap_cfg");
      gap_cfg.mode          = HEXK_DELAY_BURSTY;
      gap_cfg.burst_on_min  = 2;
      gap_cfg.burst_on_max  = 4;
      gap_cfg.burst_off_min = 5;
      gap_cfg.burst_off_max = 10;
      gap                   = new(gap_cfg, "driver.gap");
      response_time         = new(gap_cfg, "responder.time");
      `uvm_info("EXAMPLE", gap.convert2string(), UVM_NONE)

      repeat (NUM_ITEMS) begin
         // The count is used as clock cycles.
         repeat (gap.next()) begin
            @(posedge clk);
         end
         `uvm_info("EXAMPLE", $sformatf("item sent at %0t", $realtime), UVM_NONE)
         @(posedge clk);
      end

      // The same kind of count used as a time: the delay times 100 ps.
      response_time.wait_time(`hexk_ps(100ps));
      `uvm_info("EXAMPLE", $sformatf("response at %0t", $realtime), UVM_NONE)
      $finish;
   end

endmodule : hexk_delay_example
