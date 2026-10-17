// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_if.sv
//
// The register bus of the reference DUT, its interrupt and its commit port, as the testbench sees
// them. A master holds req, we, addr, wdata and wstrb until it samples ack; the slave gives ack
// for one cycle, with rdata for a read. While rst_n is low a master keeps req low; a reset during
// a request ends it. The protocol rules are checked here and reported through the root reporter
// with the library's static report macros, as an interface has no reporter of its own: a request
// does not change while it waits for ack, ack comes only to a request, and req, and while req is 1
// ack and the request (wdata for a write), have a level. The monitor checks the read data.

`ifndef HEXK_REF_BUS_IF_SV
`define HEXK_REF_BUS_IF_SV

`include "hexk_macros.svh"

interface hexk_ref_bus_if (
    input logic clk,
    input logic rst_n
);
   timeunit 1ns; timeprecision 1ps;

   logic        req;
   logic        we;
   logic [ 8:0] addr;
   logic [31:0] wdata;
   logic [ 3:0] wstrb;
   logic        ack;
   logic [31:0] rdata;
   logic        irq;
   logic        commit;
   logic [ 5:0] commit_addr;
   logic [38:0] commit_code;

   // The driver drives through this block and samples ack and the read data through it.
   clocking cb @(posedge clk);
      output req, we, addr, wdata, wstrb;
      input ack, rdata, irq, commit, commit_addr, commit_code;
   endclocking : cb

   // Signals as sampled at a rising edge, for the monitor.
   clocking mon_cb @(posedge clk);
      input req, we, addr, wdata, wstrb, ack, rdata, irq, commit, commit_addr, commit_code;
   endclocking : mon_cb

   // Drives an idle bus.
   function automatic void idle();
      req   = 1'b0;
      we    = 1'b0;
      addr  = '0;
      wdata = '0;
      wstrb = '0;
   endfunction : idle

   // A request that waits for ack keeps its command.
   req_held_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1) req && !ack |=> req && $stable(
       {we, addr, wdata, wstrb}
   ))
   else begin
      `hexk_static_error("REF_BUS_PROTOCOL", $sformatf("%m: a request changed or ended before its ack"))
   end

   // The DUT acks a request at the edge after the first edge that sees it.
   ack_next_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1) req && !ack |=> ack)
   else begin
      `hexk_static_error("REF_BUS_PROTOCOL", $sformatf("%m: no ack at the edge after the request was seen"))
   end

   // req has a level, and so have ack and the request while req is 1, wdata for a write only.
   known_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !$isunknown(
       req
   ) && (req !== 1'b1 || (!$isunknown(
       {ack, we, addr, wstrb}
   ) && (we !== 1'b1 || !$isunknown(
       wdata
   )))))
   else begin
      `hexk_static_error("REF_BUS_UNKNOWN", $sformatf("%m: req, or ack or the request while req is 1, is X or Z"))
   end

   // An ack lasts one cycle.
   ack_one_cycle_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1) ack |=> !ack)
   else begin
      `hexk_static_error("REF_BUS_PROTOCOL", $sformatf("%m: ack longer than one cycle"))
   end

   // ack answers a request.
   ack_needs_req_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1) ack |-> $past(req))
   else begin
      `hexk_static_error("REF_BUS_PROTOCOL", $sformatf("%m: ack without a request"))
   end

endinterface : hexk_ref_bus_if

`endif  // HEXK_REF_BUS_IF_SV
