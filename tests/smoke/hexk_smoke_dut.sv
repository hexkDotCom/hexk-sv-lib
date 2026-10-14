// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_dut.sv
//
// DUT of the smoke testbench: a FIFO with a valid/ready channel at its input and one at its
// output, and two control pins that the tests use to make it misbehave.
// corrupt inverts bit 0 of every word at the output, so that the scoreboard sees an error.
// stall keeps in_ready at 0, so that nothing moves any more and the watchdog has to end the
// test. The FIFO itself is plain: DEPTH words, first in first out.

`ifndef HEXK_SMOKE_DUT_SV
`define HEXK_SMOKE_DUT_SV

module hexk_smoke_dut #(
    int WIDTH = 8,
    int DEPTH = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             in_valid,
    output logic             in_ready,
    input  logic [WIDTH-1:0] in_data,
    output logic             out_valid,
    input  logic             out_ready,
    output logic [WIDTH-1:0] out_data,
    input  logic             corrupt,
    input  logic             stall
);
   timeunit 1ns; timeprecision 1ps;

   logic        [WIDTH-1:0] store [DEPTH];
   int unsigned             count;
   int unsigned             head;
   int unsigned             tail;
   logic                    push;
   logic                    pop;

   assign in_ready  = (count < $unsigned(DEPTH)) && (stall !== 1'b1);
   assign out_valid = (count != 0);
   assign out_data  = store[head] ^ WIDTH'(corrupt === 1'b1);
   assign push      = in_valid && in_ready;
   assign pop       = out_valid && out_ready;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         count <= 0;
         head  <= 0;
         tail  <= 0;
      end else begin
         if (push) begin
            store[tail] <= in_data;
            tail        <= (tail + 1) % $unsigned(DEPTH);
         end
         if (pop) begin
            head <= (head + 1) % $unsigned(DEPTH);
         end
         count <= count + 32'(push) - 32'(pop);
      end
   end

endmodule : hexk_smoke_dut

`endif  // HEXK_SMOKE_DUT_SV
