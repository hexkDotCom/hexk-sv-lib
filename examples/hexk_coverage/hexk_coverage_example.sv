// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_coverage_example.sv
//
// Minimal use of the coverage helpers: a monitor of a valid/ready stream writes one
// hexk_handshake_cycle_t per clock cycle to its port cycle_ap, where the test connects a
// hexk_handshake_coverage, and has a covergroup of its own for the transferred data, which it
// creates with `hexk_cg_new. The test defines the knob coverage, drives the stream with random
// gaps and backpressure for 300 cycles, and prints both coverage numbers at the end. With
// +coverage=0 on the command line no covergroup is created and the test says so.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_coverage_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_handshake_coverage;
   import hexk_uvm_pkg::hexk_handshake_cycle_t;
   `include "hexk_macros.svh"

   // The stream that is covered.
   bit       clk;
   bit       rst_n;
   bit       valid;
   bit       ready;
   bit [7:0] data;

   always #5ns clk = !clk;

   class hexk_example_monitor extends uvm_component;
      // One record per rising edge of the clock.
      uvm_analysis_port #(hexk_handshake_cycle_t) cycle_ap;

      // verilator lint_off COVERIGN
      // verilator lint_off UNDRIVEN
      covergroup data_cg with function sample (bit [7:0] value);
         option.per_instance = 1;
         option.get_inst_coverage = 1;
         value_cp: coverpoint value {bins zero = {0}; bins low = {[1 : 127]}; bins high = {[128 : 255]};}
      endgroup : data_cg
      // verilator lint_on UNDRIVEN
      // verilator lint_on COVERIGN

      `uvm_component_utils(hexk_example_monitor)

      function new(string name, uvm_component parent);
         super.new(name, parent);
         cycle_ap = new("cycle_ap", this);
         // Where "data_cg = new();" would stand: created unless the knob coverage is 0.
         `hexk_cg_new(data_cg)
      endfunction : new

      task run_phase(uvm_phase phase);
         hexk_handshake_cycle_t cycle;
         bit                    was_in_reset;
         forever begin
            @(posedge clk);
            cycle.reset_began = !rst_n && !was_in_reset;
            cycle.in_reset    = !rst_n;
            cycle.valid       = valid;
            cycle.ready       = ready;
            cycle_ap.write(cycle);
            was_in_reset = !rst_n;
            if (rst_n && valid && ready && data_cg != null) begin
               data_cg.sample(data);
            end
         end
      endtask : run_phase

      // Coverage of the data with one decimal, or "off".
      function string data_coverage();
         if (data_cg == null) begin
            return "off";
         end
         return $sformatf("%0.1f%%", data_cg.get_inst_coverage());
      endfunction : data_coverage
   endclass : hexk_example_monitor

   class hexk_example_test extends uvm_test;
      hexk_example_monitor    monitor;
      hexk_handshake_coverage handshake;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         hexk_knobs knobs = hexk_knobs::get();
         super.build_phase(phase);
         // The knob must be final before the first covergroup is created.
         knobs.add_bit("coverage", 1, "functional coverage: covergroups are created");
         knobs.lock();
         monitor   = hexk_example_monitor::type_id::create("monitor", this);
         handshake = hexk_handshake_coverage::type_id::create("handshake", this);
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         monitor.cycle_ap.connect(handshake.analysis_export);
      endfunction : connect_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "stimulus");
         repeat (2) @(negedge clk);
         rst_n = 1;
         repeat (300) begin
            @(negedge clk);
            // A sender that is held keeps valid and data; otherwise it sends in two cycles of three.
            if (!(valid && !ready)) begin
               valid = ($urandom_range(0, 2) != 0);
               data  = 8'($urandom_range(0, 255));
            end
            ready = ($urandom_range(0, 2) != 0);
         end
         phase.drop_objection(this, "stimulus");
      endtask : run_phase

      function void report_phase(uvm_phase phase);
         if (!handshake.is_enabled()) begin
            `uvm_info("EXAMPLE", $sformatf("coverage is off; %0d cycles seen", handshake.num_samples()), UVM_NONE)
         end else begin
            `uvm_info("EXAMPLE", $sformatf(
                      "%0d cycles: handshake coverage %0.1f%%, data coverage %s",
                      handshake.num_samples(),
                      handshake.get_coverage(),
                      monitor.data_coverage()
                      ), UVM_NONE)
         end
      endfunction : report_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_coverage_example
