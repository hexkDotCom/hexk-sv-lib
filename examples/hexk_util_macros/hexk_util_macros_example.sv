// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_util_macros_example.sv
//
// Minimal use of the macros of hexk_util_macros.svh in one small testbench:
// the testbench module hands a virtual interface to the test with `hexk_vif_set, the test
// fetches it with `hexk_vif_get_or_fatal; a scoreboard receives the items of two monitors
// through one indexed imp type and knows which stream an item came from; an address map is
// randomized with ranges that cannot overlap; a statistics object is a singleton.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

interface hexk_example_bus_if (
    input logic clk
);
   logic [7:0] data;
endinterface : hexk_example_bus_if

module hexk_util_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;

   localparam int unsigned NUM_STREAMS = 2;
   localparam int unsigned NUM_REGIONS = 3;

   // Counts items for the whole testbench.
   class hexk_example_stats;
      int unsigned items;

      `hexk_singleton_decl(hexk_example_stats)
   endclass : hexk_example_stats

   // Memory regions of a test; no two may share an address.
   class hexk_example_map extends uvm_object;
      rand bit [15:0] first_addr[NUM_REGIONS];
      rand bit [15:0] last_addr [NUM_REGIONS];

      `hexk_constraint_no_overlap(first_addr, last_addr)

      `uvm_object_utils(hexk_example_map)

      function new(string name = "hexk_example_map");
         super.new(name);
      endfunction : new
   endclass : hexk_example_map

   `hexk_analysis_imp_indexed_decl(stream)

   // Scoreboard with one imp per stream, all of one type.
   class hexk_example_scoreboard extends uvm_scoreboard;
      hexk_analysis_imp_indexed_stream #(
          .T  (int),
          .IMP(hexk_example_scoreboard)
      ) stream_imps[NUM_STREAMS];

      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
         foreach (stream_imps[i]) begin
            stream_imps[i] = new($sformatf("stream_imp_%0d", i), this, i);
         end
      endfunction : new

      function void write_stream(int idx, int t);
         hexk_example_stats stats = hexk_example_stats::get();
         stats.items++;
         `uvm_info("EXAMPLE", $sformatf("stream %0d delivered %0d", idx, t), UVM_NONE)
      endfunction : write_stream
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      virtual hexk_example_bus_if vif;
      hexk_example_scoreboard     scoreboard;
      hexk_example_map            map;
      uvm_analysis_port #(int)    monitor_ports[NUM_STREAMS];

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         `hexk_vif_get_or_fatal(hexk_example_bus_if, "bus_vif", vif)
         scoreboard = hexk_example_scoreboard::type_id::create("scoreboard", this);
         map        = hexk_example_map::type_id::create("map");
         foreach (monitor_ports[i]) begin
            monitor_ports[i] = new($sformatf("monitor_port_%0d", i), this);
         end
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         foreach (monitor_ports[i]) begin
            monitor_ports[i].connect(scoreboard.stream_imps[i]);
         end
      endfunction : connect_phase

      task run_phase(uvm_phase phase);
         hexk_example_stats stats = hexk_example_stats::get();
         phase.raise_objection(this, "stimulus");
         if (map.randomize() != 1) begin
            `uvm_error("EXAMPLE", "randomization of the map failed")
         end
         foreach (map.first_addr[i]) begin
            `uvm_info("EXAMPLE", $sformatf("region %0d: 0x%04h to 0x%04h", i, map.first_addr[i], map.last_addr[i]),
                      UVM_NONE)
         end
         @(posedge vif.clk);
         monitor_ports[1].write(11);
         monitor_ports[0].write(22);
         `uvm_info("EXAMPLE", $sformatf("%0d items counted", stats.items), UVM_NONE)
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   bit clk;
   hexk_example_bus_if bus_if (.clk(clk));

   always #5ns clk = !clk;

   initial begin
      `hexk_vif_set(hexk_example_bus_if, "uvm_test_top", "bus_vif", bus_if)
      run_test("hexk_example_test");
   end

endmodule : hexk_util_macros_example
