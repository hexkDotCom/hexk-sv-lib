// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_hdl_macros_example.sv
//
// Minimal use of the HDL access macros: a counter and a status net stand for a design, and
// the test reaches them by their paths as text. It checks a path before the first access,
// reads the counter, deposits a new count, forces the status net and releases it, and at the
// end reads a path with a typing error, which is reported with the path.
// Needs UVM with its DPI code, src/uvm/hexk_uvm.f, and a simulation that gives read and
// write access to the signals of this module, on Questa
// vsim -voptargs=-access=rw+hexk_hdl_macros_example. Without that access every macro reports.

module hexk_hdl_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   `include "hexk_macros.svh"

   // What stands for the design.
   bit          clk;
   bit    [7:0] count;
   wire         busy;

   // Path of this module; a testbench has the paths of its design in its configuration.
   string       scope = $sformatf("%m");

   logic  [7:0] count_seen;
   logic        busy_seen;

   assign busy = (count != 0);

   always #5ns clk = !clk;

   always @(posedge clk) begin
      count <= count + 8'd1;
   end

   // Reads both signals by path and prints them.
   task automatic show(string what);
      `hexk_hdl_read({scope, ".count"}, count_seen, "EXAMPLE_HDL")
      `hexk_hdl_read({scope, ".busy"}, busy_seen, "EXAMPLE_HDL")
      `uvm_info("EXAMPLE", $sformatf("%s: count=%0d busy=%0b", what, count_seen, busy_seen), UVM_NONE)
   endtask : show

   initial begin
      // A wrong path or missing access ends the test here, before any stimulus is spent.
      `hexk_hdl_check_path_or_fatal({scope, ".count"}, "EXAMPLE_HDL")

      #42ns;
      show("after four clocks");

      // The counter goes on from the deposited value.
      `hexk_hdl_deposit({scope, ".count"}, 8'd200, "EXAMPLE_HDL")
      #20ns;
      show("two clocks after a deposit of 200");

      // The net keeps the forced value whatever its driver says, until the release.
      `hexk_hdl_force({scope, ".busy"}, 1'b0, "EXAMPLE_HDL")
      #10ns;
      show("busy forced to 0");
      `hexk_hdl_release({scope, ".busy"}, "EXAMPLE_HDL")
      #10ns;
      show("busy released");

      // A typing error in a path is an error that names the path.
      `hexk_hdl_read({scope, ".cuont"}, count_seen, "EXAMPLE_HDL")
      $finish;
   end

endmodule : hexk_hdl_macros_example
