// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_analysis_fifo_example.sv
//
// Minimal use of hexk_delay_analysis_fifo: a monitor at the input of a DUT with a pipeline
// of three clock cycles writes what it sees; the predictor must get each input when the DUT
// has it at its output. The FIFO between the two holds every item for three clock events,
// so the predictor needs no knowledge of the pipeline and the monitor is never blocked.
// The FIFO is registered with the objection aggregator: the run phase does not end while an
// item is still on its way. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_delay_analysis_fifo_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay_analysis_fifo;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   `include "uvm_macros.svh"

   localparam int unsigned PIPELINE_DEPTH = 3;
   localparam int unsigned NUM_ITEMS = 4;

   bit   clk;
   event clk_event;

   always #5ns clk = !clk;
   always @(posedge clk) begin
      ->clk_event;
   end

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator       objections;
      hexk_delay_analysis_fifo #(int) pipeline_fifo;
      uvm_analysis_port #(int)        monitor_port;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections    = hexk_objection_aggregator::type_id::create("objections", this);
         pipeline_fifo = hexk_delay_analysis_fifo#(int)::type_id::create("pipeline_fifo", this);
         monitor_port  = new("monitor_port", this);
         pipeline_fifo.latency_cycles = PIPELINE_DEPTH;
         pipeline_fifo.set_clock(clk_event);
         objections.register(pipeline_fifo, pipeline_fifo.get_full_name());
         objections.poll_interval_ps = `hexk_ps(10ns);
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         monitor_port.connect(pipeline_fifo.analysis_export);
      endfunction : connect_phase

      task run_phase(uvm_phase phase);
         super.run_phase(phase);
         // The predictor: takes every item when it leaves the pipeline.
         fork
            forever begin
               int item;
               pipeline_fifo.get(item);
               `uvm_info("EXAMPLE", $sformatf("predictor got %0d at %0t", item, $realtime), UVM_NONE)
            end
         join_none
         // The monitor: sees one input per clock cycle.
         phase.raise_objection(this, "stimulus");
         for (int unsigned i = 0; i < NUM_ITEMS; i++) begin
            @(posedge clk);
            monitor_port.write(int'(100 + i));
            `uvm_info("EXAMPLE", $sformatf("monitor saw %0d at %0t", 100 + i, $realtime), UVM_NONE)
         end
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_delay_analysis_fifo_example
