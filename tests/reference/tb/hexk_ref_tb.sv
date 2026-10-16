// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_tb.sv
//
// Top of the reference testbench: the DUT, the clock and reset interface, the input channel, the
// register bus and the throttle of the input. hexk_tb_top_inc.svh publishes the interfaces and
// calls run_test(); the test is chosen with +UVM_TESTNAME.

`ifndef HEXK_REF_TB_SV
`define HEXK_REF_TB_SV

`include "hexk_macros.svh"

module hexk_ref_tb;
   timeunit 1ns; timeprecision 1ps;

   // A reference to the package makes every simulator elaborate it, and so register the tests.
   import hexk_ref_pkg::hexk_ref_base_test;

   hexk_clk_rst_if clk_rst_if ();

   hexk_valid_ready_if #(
       .DATA_WIDTH(32)
   ) in_if (
       .clk  (clk_rst_if.clk),
       .rst_n(clk_rst_if.rst)
   );

   hexk_ref_bus_if bus_if (
       .clk  (clk_rst_if.clk),
       .rst_n(clk_rst_if.rst)
   );

   logic ready_allow;

   // The strap pins: pin 0 holds the input's ready at 0 (hexk_ref_stall_test).
   hexk_pins_if #(.WIDTH(hexk_ref_pkg::hexk_ref_env_cfg::NUM_STRAPS)) strap_if ();

   hexk_ref_ready_bfm ready_bfm (
       .clk        (clk_rst_if.clk),
       .rst_n      (clk_rst_if.rst),
       .ready_allow(ready_allow)
   );

   hexk_ref_dut dut (
       .clk        (clk_rst_if.clk),
       .rst_n      (clk_rst_if.rst),
       .in_valid   (in_if.valid),
       .in_ready   (in_if.ext_ready),
       .in_data    (in_if.data),
       .ready_allow(ready_allow && strap_if.pins[hexk_ref_pkg::hexk_ref_env_cfg::STALL_PIN] !== 1'b1),
       .bus_req    (bus_if.req),
       .bus_we     (bus_if.we),
       .bus_addr   (bus_if.addr),
       .bus_wdata  (bus_if.wdata),
       .bus_wstrb  (bus_if.wstrb),
       .bus_ack    (bus_if.ack),
       .bus_rdata  (bus_if.rdata),
       .irq        (bus_if.irq),
       .commit     (bus_if.commit),
       .commit_addr(bus_if.commit_addr),
       .commit_code(bus_if.commit_code)
   );

   // Called by the include before run_test().
   function automatic void publish_interfaces();
      `hexk_vif_set(hexk_clk_rst_if, "uvm_test_top", "clk_rst_vif", clk_rst_if)
      `hexk_vif_set(hexk_valid_ready_if#(32), "uvm_test_top", "in_vif", in_if)
      `hexk_vif_set(hexk_ref_bus_if, "uvm_test_top", "bus_vif", bus_if)
      `hexk_vif_set(hexk_pins_if#(hexk_ref_pkg::hexk_ref_env_cfg::NUM_STRAPS), "uvm_test_top", "strap_vif", strap_if)
   endfunction : publish_interfaces

   `define HEXK_TB_PRE_RUN_TEST publish_interfaces
   `include "base/hexk_tb_top_inc.svh"

endmodule : hexk_ref_tb

`endif  // HEXK_REF_TB_SV
