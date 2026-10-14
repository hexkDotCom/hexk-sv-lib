// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_tb.sv
//
// Top of the smoke testbench: the DUT, the interfaces of the three agents and of the
// control pins, and the include that installs the report server and calls run_test().
// The clock and the reset of the DUT and of the two channels come from the clock and reset
// agent. The inputs of the DUT are connected to the channel signals of the interfaces, its
// outputs to their ext_ inputs. The test is selected with +UVM_TESTNAME.

`include "hexk_macros.svh"

module hexk_smoke_tb;
   timeunit 1ns; timeprecision 1ps;

   import hexk_smoke_pkg::hexk_smoke_env_cfg;

   hexk_clk_rst_if clk_rst_if ();

   hexk_valid_ready_if #(
       .DATA_WIDTH(hexk_smoke_env_cfg::WIDTH)
   ) in_if (
       .clk  (clk_rst_if.clk),
       .rst_n(clk_rst_if.rst)
   );

   hexk_valid_ready_if #(
       .DATA_WIDTH(hexk_smoke_env_cfg::WIDTH)
   ) out_if (
       .clk  (clk_rst_if.clk),
       .rst_n(clk_rst_if.rst)
   );

   hexk_pins_if #(.WIDTH(hexk_smoke_env_cfg::NUM_CTRL_PINS)) ctrl_if ();

   hexk_smoke_dut #(
       .WIDTH(hexk_smoke_env_cfg::WIDTH)
   ) dut (
       .clk      (clk_rst_if.clk),
       .rst_n    (clk_rst_if.rst),
       .in_valid (in_if.valid),
       .in_ready (in_if.ext_ready),
       .in_data  (in_if.data),
       .out_valid(out_if.ext_valid),
       .out_ready(out_if.ready),
       .out_data (out_if.ext_data),
       .corrupt  (ctrl_if.pins[hexk_smoke_env_cfg::CORRUPT_PIN]),
       .stall    (ctrl_if.pins[hexk_smoke_env_cfg::STALL_PIN])
   );

   // Called by the include before run_test().
   function automatic void publish_interfaces();
      `hexk_vif_set(hexk_clk_rst_if, "uvm_test_top", "clk_rst_vif", clk_rst_if)
      `hexk_vif_set(hexk_valid_ready_if#(hexk_smoke_env_cfg::WIDTH), "uvm_test_top", "in_vif", in_if)
      `hexk_vif_set(hexk_valid_ready_if#(hexk_smoke_env_cfg::WIDTH), "uvm_test_top", "out_vif", out_if)
      `hexk_vif_set(hexk_pins_if#(hexk_smoke_env_cfg::NUM_CTRL_PINS), "uvm_test_top", "ctrl_vif", ctrl_if)
   endfunction : publish_interfaces

   `define HEXK_TB_PRE_RUN_TEST publish_interfaces
   `include "base/hexk_tb_top_inc.svh"

endmodule : hexk_smoke_tb
