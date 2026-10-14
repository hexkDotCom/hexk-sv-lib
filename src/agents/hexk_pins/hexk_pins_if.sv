// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_pins_if.sv
//
// Interface for miscellaneous pins of a DUT, such as GPIO, straps and interrupts: drives,
// pulls, forces and samples each pin on its own, without an agent.
// Instantiate one per group of pins in the testbench top, connect each bit of pins to a pin
// of the DUT, and call the functions below from a test or a sequence through a virtual
// interface handle. A mask selects the pins that a call is for. A pin has the value that its
// drivers give it: this interface, the DUT and whatever else is connected. A pull decides
// only while nothing drives the pin; a force wins against every driver. Nothing is clocked:
// a call takes effect in its time step.
// The interface needs nets with several drivers, drive strengths and force. Where
// HEXK_SIM_NO_PIN_MODEL of hexk_sim_compat.svh is defined, the functions do nothing and
// the first call that would change a pin is an error.
//
//! @module    hexk_pins
//! @since     0.7.0
//! @stability experimental
//! @serves    IFC-1 IFC-8
//! @emits     HEXK_PINS_INDEX:error HEXK_PINS_UNSUPPORTED:error
//! @plusargs  (none)

`ifndef HEXK_PINS_IF_SV
`define HEXK_PINS_IF_SV

`include "hexk_sim_compat.svh"
`include "hexk_macros.svh"

interface hexk_pins_if #(
    int WIDTH = 1
);
   timeunit 1ns; timeprecision 1ps;

   `include "uvm_macros.svh"

   // The pins: connect each bit to a pin of the DUT, an input, an output or a bidirectional one.
   // A lint rule reports a net that nothing in the interface drives, which is so without the pin model.
   // verilator lint_off UNDRIVEN
   wire  [WIDTH-1:0] pins;
   // verilator lint_on UNDRIVEN

   // What the interface drives, and on which pins.
   logic [WIDTH-1:0] drive_value;
   bit   [WIDTH-1:0] drive_enable;

   // Which pins have a pull, and whether it is a pull-up.
   bit   [WIDTH-1:0] pull_enable;
   bit   [WIDTH-1:0] pull_high;

   // What the interface forces, and on which pins.
   logic [WIDTH-1:0] force_value;
   bit   [WIDTH-1:0] force_enable;

   // Set when HEXK_PINS_UNSUPPORTED has been reported, so that it is reported once.
   bit               unsupported_reported;

`ifndef HEXK_SIM_NO_PIN_MODEL
   for (genvar i = 0; i < WIDTH; i++) begin : gen_pin
      // An ordinary driver while the pin is driven; a Z bit of the value drives nothing.
      assign pins[i] = drive_enable[i] ? drive_value[i] : 1'bz;

      // A weaker driver while the pin has a pull: it gives way to every ordinary driver.
      assign (pull1, pull0) pins[i] = pull_enable[i] ? pull_high[i] : 1'bz;

      // A force names its target at compile time, hence one block per pin.
      always @(force_enable[i] or force_value[i]) begin : force_pin
         if (force_enable[i]) begin
            force pins[i] = force_value[i];
         end else begin
            release pins[i];
         end
      end : force_pin
   end : gen_pin
`endif

   // 1 where the simulator cannot model the pins; says so once, as an error.
   function automatic bit is_unsupported();
`ifdef HEXK_SIM_NO_PIN_MODEL
      if (!unsupported_reported) begin
         unsupported_reported = 1'b1;
         `hexk_static_error("HEXK_PINS_UNSUPPORTED", {
                            "this simulator has no nets with several drivers, drive strengths and force; ",
                            "the pins interface drives, pulls and forces nothing"})
      end
      return 1'b1;
`else
      return 1'b0;
`endif
   endfunction : is_unsupported

   // Drives the pins of mask to the bits of value, until float_pins() or the next drive().
   function automatic void drive(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      // Bit by bit: a bitwise operator would turn a Z bit of the value into X.
      for (int unsigned i = 0; i < WIDTH; i++) begin
         if (mask[i]) begin
            drive_value[i]  = value[i];
            drive_enable[i] = 1'b1;
         end
      end
   endfunction : drive

   // Stops driving the pins of mask.
   function automatic void float_pins(bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      drive_enable = drive_enable & ~mask;
   endfunction : float_pins

   // Pulls the pins of mask up; a pull gives way to anything that drives the pin.
   function automatic void pull_up(bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      pull_enable = pull_enable | mask;
      pull_high   = pull_high | mask;
   endfunction : pull_up

   // Pulls the pins of mask down; a pull gives way to anything that drives the pin.
   function automatic void pull_down(bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      pull_enable = pull_enable | mask;
      pull_high   = pull_high & ~mask;
   endfunction : pull_down

   // Takes the pull from the pins of mask.
   function automatic void pull_none(bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      pull_enable = pull_enable & ~mask;
   endfunction : pull_none

   // Forces the pins of mask to the bits of value against everything else that drives them, also the DUT.
   function automatic void force_pins(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      for (int unsigned i = 0; i < WIDTH; i++) begin
         if (mask[i]) begin
            force_value[i]  = value[i];
            force_enable[i] = 1'b1;
         end
      end
   endfunction : force_pins

   // Ends the force on the pins of mask.
   function automatic void release_pins(bit [WIDTH-1:0] mask = '1);
      if (is_unsupported()) begin
         return;
      end
      force_enable = force_enable & ~mask;
   endfunction : release_pins

   // What the pins hold now.
   function automatic logic [WIDTH-1:0] sample ();
      return pins;
   endfunction : sample

   // 1 when the pins of mask hold the bits of value, X and Z included.
   function automatic bit holds(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
      for (int unsigned i = 0; i < WIDTH; i++) begin
         if (mask[i] && pins[i] !== value[i]) begin
            return 1'b0;
         end
      end
      return 1'b1;
   endfunction : holds

   // Waits until the pins of mask hold the bits of value; returns at once when they do.
   task automatic wait_value(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
      while (!holds(
          value, mask
      )) begin
         @(pins);
      end
   endtask : wait_value

   // Waits until one of the pins of mask changes.
   task automatic wait_change(bit [WIDTH-1:0] mask = '1);
      logic [WIDTH-1:0] first = pins;
      do begin
         @(pins);
      end while (holds(
          first, mask
      ));
   endtask : wait_change

   // The mask of one pin; an index of WIDTH or above is an error and gives an empty mask.
   function automatic bit [WIDTH-1:0] mask_of(int unsigned index);
      bit [WIDTH-1:0] mask = '0;
      if (index >= WIDTH) begin
         `hexk_static_error("HEXK_PINS_INDEX", $sformatf("pin %0d does not exist; the interface has %0d pins", index,
                                                         WIDTH))
         return mask;
      end
      mask[index] = 1'b1;
      return mask;
   endfunction : mask_of

   // Drives one pin, by its number.
   function automatic void drive_pin(int unsigned index, logic value);
      drive({WIDTH{value}}, mask_of(index));
   endfunction : drive_pin

   // Stops driving one pin, by its number.
   function automatic void float_pin(int unsigned index);
      float_pins(mask_of(index));
   endfunction : float_pin

   // What one pin holds now; X for a pin that does not exist.
   function automatic logic sample_pin(int unsigned index);
      bit [WIDTH-1:0] mask = mask_of(index);
      return (mask == '0) ? 1'bx : pins[index];
   endfunction : sample_pin

   // What the interface does to each pin and what the pins hold, on one line, pin WIDTH-1 first:
   // drive and force show the value or "-", pull shows "u", "d" or "-".
   function automatic string convert2string();
      string driven;
      string pulled;
      string forced;
      for (int i = WIDTH - 1; i >= 0; i--) begin
         driven = {driven, drive_enable[i] ? $sformatf("%b", drive_value[i]) : "-"};
         forced = {forced, force_enable[i] ? $sformatf("%b", force_value[i]) : "-"};
         if (!pull_enable[i]) begin
            pulled = {pulled, "-"};
         end else begin
            pulled = {pulled, pull_high[i] ? "u" : "d"};
         end
      end
      return $sformatf("drive=%s pull=%s force=%s pins=%b", driven, pulled, forced, pins);
   endfunction : convert2string

endinterface : hexk_pins_if

`endif  // HEXK_PINS_IF_SV
