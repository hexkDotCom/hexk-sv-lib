// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_knobs_example.sv
//
// Minimal use of hexk_knobs: the base test defines three test-wide knobs, a derived test
// changes one, lock() makes them final at the end of build_phase, and the run phase reads
// them. Try +num_items=3, +gate_level, +hexk_knobs_help, or +num_itms=3 together with
// +hexk_knobs_strict on the command line. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_knobs_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_enum_knob;
   `include "uvm_macros.svh"

   // Kind of netlist that is simulated; on the command line +netlist=rtl, +netlist=gate or +netlist=power.
   typedef enum {
      HEXK_EXAMPLE_NETLIST_RTL,
      HEXK_EXAMPLE_NETLIST_GATE,
      HEXK_EXAMPLE_NETLIST_POWER
   } hexk_example_netlist_e;

   class hexk_example_base_test extends uvm_test;
      hexk_knobs knobs;

      `uvm_component_utils(hexk_example_base_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      // Hook for derived tests (guide rule TST-2); it runs before the knobs are locked.
      virtual function void modify_knobs();
      endfunction : modify_knobs

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         knobs = hexk_knobs::get();
         knobs.add_int("num_items", 10, "items per sequence", 1, 1000);
         knobs.add_bit("gate_level", 0, "gate-level netlist: no backdoor access");
         hexk_enum_knob#(hexk_example_netlist_e)::add("netlist", HEXK_EXAMPLE_NETLIST_RTL, "kind of netlist");
         modify_knobs();
         knobs.lock();
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         `uvm_info("EXAMPLE", $sformatf("sending %0d items, gate_level=%0b", knobs.get_int("num_items"), knobs.get_bit(
                                        "gate_level")), UVM_NONE)
         #10ns;
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_base_test

   class hexk_example_long_test extends hexk_example_base_test;
      `uvm_component_utils(hexk_example_long_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function void modify_knobs();
         knobs.set_int("num_items", 500);
      endfunction : modify_knobs
   endclass : hexk_example_long_test

   // Code outside the UVM phases waits until the knobs are final.
   initial begin
      hexk_example_netlist_e netlist;
      hexk_knobs::wait_locked();
      netlist = hexk_enum_knob#(hexk_example_netlist_e)::get("netlist");
      if (netlist != HEXK_EXAMPLE_NETLIST_RTL) begin
         $info("netlist is %s: no backdoor access", netlist.name());
      end
   end

   initial begin
      run_test("hexk_example_long_test");
   end

endmodule : hexk_knobs_example
