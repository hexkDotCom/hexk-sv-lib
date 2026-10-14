// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_base_test_example.sv
//
// A whole small testbench on hexk_base_test and hexk_tb_top_inc.svh.
// The top module has no initial block: the include installs the report server, calls
// publish_interfaces(), which is named by HEXK_TB_PRE_RUN_TEST, and then run_test().
// The block base test extends hexk_base_test: it adds a knob in define_knobs(), fetches the
// interface and widens the watchdog limit. The test drives a few values and checks each
// one, so the last line of the log is TEST PASSED with the number of checks.
// Run it with +UVM_TESTNAME=hexk_example_smoke_test; try +num_items=0 to see a test that
// fails because it checked nothing, and +hexk_knobs_help for the knobs.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

interface hexk_example_dut_if (
    input logic clk
);
   logic [7:0] data_in;
   logic [7:0] data_out;
endinterface : hexk_example_dut_if

module hexk_base_test_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_base_test;

   // Base test of this block: knobs, interface and limits that all its tests share.
   class hexk_example_block_base_test extends hexk_base_test;
      virtual hexk_example_dut_if vif;

      `uvm_component_utils(hexk_example_block_base_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function void define_knobs();
         knobs.add_int("num_items", 4, "values to send through the DUT", 0, 1000);
      endfunction : define_knobs

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         `hexk_vif_get_or_fatal(hexk_example_dut_if, "dut_vif", vif)
         watchdog.global_timeout_ps = `hexk_ps(10us);
      endfunction : build_phase
   endclass : hexk_example_block_base_test

   // Sends values and checks that each comes out incremented.
   class hexk_example_smoke_test extends hexk_example_block_base_test;
      `uvm_component_utils(hexk_example_smoke_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      task run_phase(uvm_phase phase);
         int unsigned num_items = 32'(knobs.get_int("num_items"));
         phase.raise_objection(this, "stimulus");
         for (int unsigned i = 0; i < num_items; i++) begin
            vif.data_in = 8'(10 * i);
            @(posedge vif.clk);
            `hexk_check_eq(vif.data_out, 8'(10 * i + 1), "SMOKE_DATA")
         end
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_smoke_test

   bit clk;
   hexk_example_dut_if dut_if (.clk(clk));

   always #5ns clk = !clk;

   // The input is idle until the test drives it.
   initial dut_if.data_in = '0;

   // Stands for the DUT: the output is the input plus one.
   assign dut_if.data_out = dut_if.data_in + 8'd1;

   // Called by the include before run_test().
   function automatic void publish_interfaces();
      `hexk_vif_set(hexk_example_dut_if, "uvm_test_top", "dut_vif", dut_if)
   endfunction : publish_interfaces

   `define HEXK_TB_PRE_RUN_TEST publish_interfaces
   `include "base/hexk_tb_top_inc.svh"

endmodule : hexk_base_test_example
