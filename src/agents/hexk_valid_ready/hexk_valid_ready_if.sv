// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_if.sv
//
// Interface of the valid/ready agent: one data channel with a valid/ready handshake.
// Instantiate one per channel in the testbench top with the clock and the reset (active
// low) of the channel, and give the interface to the cfg of a hexk_valid_ready_agent.
// valid, ready and data are the channel: connect the inputs of the DUT to them. What the DUT
// drives is assigned to ext_valid and ext_data, or to ext_ready, and the channel follows
// these inputs on the side that no agent drives. A transfer happens at every rising edge of
// clk at which valid and ready are both 1. The agent drives and samples through the tasks
// below; testbench code uses the signals and the clocking block mon_cb. The assertions check
// the protocol whoever drives the channel, the agent or the DUT.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    IFC-6 IFC-8
//! @emits     HEXK_VALID_READY_VALID_DROPPED:error HEXK_VALID_READY_DATA_CHANGED:error
//! @emits     HEXK_VALID_READY_UNKNOWN:error
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_IF_SV
`define HEXK_VALID_READY_IF_SV

`include "hexk_macros.svh"

interface hexk_valid_ready_if #(
    int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
   timeunit 1ns; timeprecision 1ps;

   `include "uvm_macros.svh"

   // The channel: what the agents and the DUT see. Connect the inputs of the DUT to them.
   logic                  valid;
   logic                  ready;
   logic [DATA_WIDTH-1:0] data;

   // What the DUT drives: assign its valid and data, or its ready, to these. The channel follows them on the
   // side that no agent drives. A lint rule reports a signal that nothing in the design drives, as in every
   // testbench in which an agent drives that side.
   // verilator lint_off UNDRIVEN
   logic                  ext_valid;
   logic                  ext_ready;
   logic [DATA_WIDTH-1:0] ext_data;
   // verilator lint_on UNDRIVEN

   // 1 while an initiator or a responder agent drives its side of the channel; set by set_driver().
   bit                    initiator_drives;
   bit                    responder_drives;

   // The side that no agent drives follows the DUT.
   always @(ext_valid or ext_data) begin : follow_initiator_side
      if (!initiator_drives) begin
         valid = ext_valid;
         data  = ext_data;
      end
   end : follow_initiator_side

   always @(ext_ready) begin : follow_responder_side
      if (!responder_drives) begin
         ready = ext_ready;
      end
   end : follow_responder_side

   // 1 while the protocol assertions are on; set by set_checks().
   bit          checks_enabled = 1'b1;

   // Number of times the reset was asserted. A monitor that looks at the channel at the rising edges of the
   // clock compares it with the count of its last look, and so learns of a reset between two edges.
   int unsigned reset_count;

   // A lint rule wants a nonblocking assignment in an edge-triggered block; the count is read by testbench
   // code in the time step of the edge and must have changed by then.
   // verilator lint_off BLKSEQ
   always @(negedge rst_n) begin : reset_counter
      reset_count++;
   end : reset_counter
   // verilator lint_on BLKSEQ

   // The time of the latest rising edge at which the task of each side ran: a side that is not at an edge
   // waits for one before it drives.
   realtime initiator_edge_time = -1.0;
   realtime responder_edge_time = -1.0;

   // The three signals sampled at the rising edge of the clock, for testbench code.
   clocking mon_cb @(posedge clk);
      input valid, ready, data;
   endclocking : mon_cb

   // Says whether an agent drives the side of an initiator (1) or of a responder (0); the agents call it at
   // time 0. A side that is given back takes the values of the DUT.
   function automatic void set_driver(bit as_initiator, bit drives);
      if (as_initiator) begin
         initiator_drives = drives;
         if (!drives) begin
            valid = ext_valid;
            data  = ext_data;
         end
      end else begin
         responder_drives = drives;
         if (!drives) begin
            ready = ext_ready;
         end
      end
   endfunction : set_driver

   // Switches the protocol assertions on or off.
   function automatic void set_checks(bit enable);
      checks_enabled = enable;
   endfunction : set_checks

   // 1 while the reset is asserted or has no level.
   function automatic bit in_reset();
      return rst_n !== 1'b1;
   endfunction : in_reset

   // Number of times the reset was asserted so far.
   function automatic int unsigned get_reset_count();
      return reset_count;
   endfunction : get_reset_count

   // Waits until the reset is released; returns at once when it is.
   task automatic wait_reset_released();
      wait (rst_n === 1'b1);
   endtask : wait_reset_released

   // Waits until the reset is asserted; returns at once when it is.
   task automatic wait_reset_asserted();
      wait (rst_n !== 1'b1);
   endtask : wait_reset_asserted

   // Initiator: no transfer is offered. With data_x the data is X, otherwise it keeps its value.
   task automatic idle_initiator(bit data_x);
      valid <= 1'b0;
      if (data_x) begin
         data <= 'x;
      end
   endtask : idle_initiator

   // Initiator: offers one word after delay clock cycles and returns at the rising edge of its transfer.
   // valid stays 1 at the end: the caller offers the next word or calls idle_initiator() in the same time step.
   // waited is the number of rising edges at which valid was 1 and ready was not.
   task automatic send(input logic [DATA_WIDTH-1:0] word, input int unsigned delay, input bit data_x,
                       output int unsigned waited);
      if ($realtime != initiator_edge_time) begin
         @(posedge clk);
      end
      if (delay != 0) begin
         idle_initiator(data_x);
         repeat (delay) begin
            @(posedge clk);
         end
      end
      valid <= 1'b1;
      data  <= word;
      waited = 0;
      forever begin
         @(posedge clk);
         if (ready === 1'b1) begin
            break;
         end
         waited++;
      end
      initiator_edge_time = $realtime;
   endtask : send

   // Responder: no transfer is accepted.
   task automatic idle_responder();
      ready <= 1'b0;
   endtask : idle_responder

   // Responder: keeps ready 0 for delay clock cycles, then 1, and returns at the rising edge of the transfer
   // with the word. ready stays 1 at the end: the next call takes it back when it has a delay.
   // waited is the number of rising edges since the call at which valid was 1 and ready was not: what send()
   // returns for the same transfer and what the monitor counts.
   task automatic receive(input int unsigned delay, output logic [DATA_WIDTH-1:0] word, output int unsigned waited);
      waited = 0;
      if ($realtime != responder_edge_time) begin
         @(posedge clk);
         // The call came between two edges: a valid that is there at this edge waits already.
         if (valid === 1'b1 && ready !== 1'b1) begin
            waited++;
         end
      end
      if (delay != 0) begin
         ready <= 1'b0;
         repeat (delay) begin
            @(posedge clk);
            if (valid === 1'b1) begin
               waited++;
            end
         end
      end
      ready <= 1'b1;
      forever begin
         @(posedge clk);
         if (valid === 1'b1) begin
            break;
         end
      end
      word                = data;
      responder_edge_time = $realtime;
   endtask : receive

   // Monitor: waits for the next rising edge of the clock and returns what the channel holds there.
   // A valid or a ready without a level counts as 0.
   task automatic sample (output bit reset_active, output bit valid_seen, output bit ready_seen,
                          output logic [DATA_WIDTH-1:0] data_seen);
      @(posedge clk);
      reset_active = in_reset();
      valid_seen   = (valid === 1'b1);
      ready_seen   = (ready === 1'b1);
      data_seen    = data;
   endtask : sample

   // A valid that waits for ready stays until its transfer.
   valid_held_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1 || !checks_enabled) valid && !ready |=> valid)
   else begin
      // %m names the assertion in its instance, so that the message tells which channel it is.
      `hexk_static_error("HEXK_VALID_READY_VALID_DROPPED", $sformatf(
                         "%m: valid went to 0 before ready accepted the transfer"))
   end

   // The data of a valid that waits for ready does not change.
   data_held_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1 || !checks_enabled) valid && !ready |=> $stable(data))
   else begin
      `hexk_static_error("HEXK_VALID_READY_DATA_CHANGED", $sformatf("%m: data changed while valid waited for ready"))
   end

   // valid and ready have a level, and so has every bit of data while valid is 1.
   known_a :
   assert property (@(posedge clk) disable iff (rst_n !== 1'b1 || !checks_enabled) !$isunknown(
       {valid, ready}
   ) && (valid !== 1'b1 || !$isunknown(
       data
   )))
   else begin
      // The assertion looks at the values sampled at the edge; the signals may have changed since.
      `hexk_static_error("HEXK_VALID_READY_UNKNOWN", $sformatf(
                         "%m: valid, ready or the data of a valid is X or Z: valid=%b ready=%b data=0x%0h",
                         $sampled(
                             valid
                         ),
                         $sampled(
                             ready
                         ),
                         $sampled(
                             data
                         )
                         ))
   end

endinterface : hexk_valid_ready_if

`endif  // HEXK_VALID_READY_IF_SV
