// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_pins_example.sv
//
// Minimal use of hexk_pins_if: three pins of a DUT without a protocol. Pin 0 is a strap that
// the test sets, pin 1 an interrupt output that is open drain and needs a pull-up, pin 2 a
// bidirectional pin that the DUT drives after a while. The test holds a virtual interface
// handle and calls the functions of the interface: it drives the strap, pulls the interrupt
// up and waits for it with a time limit, then forces the bidirectional pin against the DUT.
// Needs UVM, src/uvm/hexk_uvm.f and src/agents/hexk_pins/hexk_pins.f.

`include "hexk_macros.svh"

// The DUT: copies its strap to the bidirectional pin from 60 ns on, and pulls its interrupt low from 20 to 40 ns.
module hexk_pins_example_dut (
    input wire strap,
    inout wire irq_n,
    inout wire gpio
);
   timeunit 1ns / 1ps;

   bit irq_active;
   bit gpio_driven;

   assign irq_n = irq_active ? 1'b0 : 1'bz;
   assign gpio  = gpio_driven ? strap : 1'bz;

   initial begin
      #20ns;
      irq_active = 1'b1;
      #20ns;
      irq_active = 1'b0;
      #20ns;
      gpio_driven = 1'b1;
   end
endmodule : hexk_pins_example_dut

module hexk_pins_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   `include "uvm_macros.svh"

   localparam int unsigned NUM_PINS = 3;
   localparam int unsigned STRAP_PIN = 0;
   localparam bit [NUM_PINS-1:0] IRQ_MASK = 3'b010;
   localparam bit [NUM_PINS-1:0] GPIO_MASK = 3'b100;

   hexk_pins_if #(.WIDTH(NUM_PINS)) pins_if ();

   hexk_pins_example_dut dut (
       .strap(pins_if.pins[0]),
       .irq_n(pins_if.pins[1]),
       .gpio (pins_if.pins[2])
   );

   class hexk_example_test extends uvm_test;
      virtual hexk_pins_if #(NUM_PINS) pins;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         if (!uvm_config_db#(virtual hexk_pins_if #(NUM_PINS))::get(this, "", "pins_vif", pins)) begin
            `uvm_fatal("EXAMPLE", "no pins_vif in the config database")
         end
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         phase.raise_objection(this, "pins");
         pins.drive_pin(STRAP_PIN, 1'b1);
         pins.pull_up(IRQ_MASK);
         `hexk_spinwait(pins.wait_value('0, IRQ_MASK);, 100ns, "EXAMPLE_IRQ")
         `uvm_info("EXAMPLE", $sformatf("interrupt at %0t: %s", $realtime, pins.convert2string()), UVM_NONE)
         `hexk_spinwait(pins.wait_value('1, IRQ_MASK);, 100ns, "EXAMPLE_IRQ")
         `uvm_info("EXAMPLE", $sformatf("interrupt gone at %0t", $realtime), UVM_NONE)
         `hexk_spinwait(pins.wait_value('1, GPIO_MASK);, 100ns, "EXAMPLE_GPIO")
         `uvm_info("EXAMPLE", $sformatf("the DUT drives its strap to pin 2 at %0t", $realtime), UVM_NONE)
         pins.force_pins('0, GPIO_MASK);
         #1ns;
         `uvm_info("EXAMPLE", $sformatf("forced against the DUT: %s", pins.convert2string()), UVM_NONE)
         pins.release_pins(GPIO_MASK);
         #1ns;
         `uvm_info("EXAMPLE", $sformatf("released: %s", pins.convert2string()), UVM_NONE)
         phase.drop_objection(this, "pins done");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      uvm_config_db#(virtual hexk_pins_if #(NUM_PINS))::set(null, "uvm_test_top", "pins_vif", pins_if);
      run_test("hexk_example_test");
   end

endmodule : hexk_pins_example
