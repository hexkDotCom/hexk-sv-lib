// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_macros_example.sv
//
// Minimal use of the static report macros in a module: an info and an error that go through
// UVM reporting, so they obey the verbosity, are counted and can be caught, without the
// module importing uvm_pkg. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_report_macros_example;
   timeunit 1ns / 1ps;

   localparam int unsigned FIFO_DEPTH = 8;

   int unsigned level = FIFO_DEPTH + 1;

   initial begin
      `hexk_static_info("EXAMPLE_FIFO", $sformatf("depth is %0d", FIFO_DEPTH), uvm_pkg::UVM_LOW)
      if (level > FIFO_DEPTH) begin
         `hexk_static_error("EXAMPLE_FIFO_OVERFLOW", $sformatf("level %0d is above the depth %0d", level, FIFO_DEPTH))
      end
   end

endmodule : hexk_report_macros_example
