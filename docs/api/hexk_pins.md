# hexk_pins

## 1. Summary

Interface for miscellaneous pins of a DUT, such as GPIO, straps and interrupts: drives,
pulls, forces and samples each pin on its own, from a test or a sequence, through a virtual
interface and without an agent.

## 2. When to use / when not to use

Use one `hexk_pins_if` for a group of pins that have no protocol: straps that a test sets
before reset, mode and test pins, interrupt outputs that a test waits for, bidirectional
GPIO, pins with a pull-up that an open-drain output pulls low. The test or a virtual
sequence calls the functions of the interface through a virtual interface handle; nothing
is built or configured.

Do not use it for pins with a protocol and a clock: a channel with a handshake belongs to an
agent (`hexk_valid_ready`), a clock and a reset to `hexk_clk_rst`. Do not use it to reach a
signal inside the DUT; that is `hexk_hdl_macros`. Do not use it where a monitor, coverage or
a scoreboard is needed: it has none, on purpose.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/agents/hexk_pins/hexk_pins_if.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/agents/hexk_pins/hexk_pins_if.sv`:

```systemverilog
// 1 where the simulator cannot model the pins; says so once, as an error.
function automatic bit is_unsupported();
// Drives the pins of mask to the bits of value, until float_pins() or the next drive().
function automatic void drive(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
// Stops driving the pins of mask.
function automatic void float_pins(bit [WIDTH-1:0] mask = '1);
// Pulls the pins of mask up; a pull gives way to anything that drives the pin.
function automatic void pull_up(bit [WIDTH-1:0] mask = '1);
// Pulls the pins of mask down; a pull gives way to anything that drives the pin.
function automatic void pull_down(bit [WIDTH-1:0] mask = '1);
// Takes the pull from the pins of mask.
function automatic void pull_none(bit [WIDTH-1:0] mask = '1);
// Forces the pins of mask to the bits of value against everything else that drives them, also the DUT.
function automatic void force_pins(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
// Ends the force on the pins of mask.
function automatic void release_pins(bit [WIDTH-1:0] mask = '1);
// What the pins hold now.
function automatic logic [WIDTH-1:0] sample ();
// 1 when the pins of mask hold the bits of value, X and Z included.
function automatic bit holds(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
// Waits until the pins of mask hold the bits of value; returns at once when they do.
task automatic wait_value(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask = '1);
// Waits until one of the pins of mask changes.
task automatic wait_change(bit [WIDTH-1:0] mask = '1);
// The mask of one pin; an index of WIDTH or above is an error and gives an empty mask.
function automatic bit [WIDTH-1:0] mask_of(int unsigned index);
// Drives one pin, by its number.
function automatic void drive_pin(int unsigned index, logic value);
// Stops driving one pin, by its number.
function automatic void float_pin(int unsigned index);
// What one pin holds now; X for a pin that does not exist.
function automatic logic sample_pin(int unsigned index);
// What the interface does to each pin and what the pins hold, on one line, pin WIDTH-1 first: drive and force show the value or "-", pull shows "u", "d" or "-".
function automatic string convert2string();
```
<!-- HEXK_GEN:END api -->

The interface is `hexk_pins_if #(int WIDTH = 1)`, without ports. Its one signal for the
testbench is `wire [WIDTH-1:0] pins`: connect each bit to a pin of the DUT, an input, an
output or a bidirectional one. The variables of the interface hold its settings; do not
write them, use the functions. `is_unsupported()` is for the interface itself.

There is no package and no class. Compile `src/uvm/hexk_uvm.f` and then
`src/agents/hexk_pins/hexk_pins.f`, or `src/hexk_all.f` for everything: the interface
reports its errors through UVM.

## 4. Behaviour and invariants

- `pins` is a bundle of wires. Each bit is one pin; a pin has the value that its drivers
  give it, by the rules of the language for nets. The interface is one of the drivers; the
  DUT and other parts of the testbench may be others.
- A call takes effect in its time step, not at once: the pins have their new value after
  the events of that time step. `sample()` right after `drive()`, without a delay, returns
  the old value. There is no clock.
- A mask selects pins: bit `n` of a mask stands for `pins[n]`, and the default selects all.
  Bits of `value` outside the mask are ignored.
- At the start the interface drives, pulls and forces nothing: a pin that nothing else
  drives is Z.
- **Drive.** `drive(value, mask)` drives the selected pins with the strength of an ordinary
  driver until `float_pins()` for them or the next `drive()`. An X bit drives X. A Z bit
  drives nothing, like `float_pins()` for that pin. Against a DUT that drives the same pin
  to the other value the pin is X, as on a board.
- **Pull.** A pull-up or pull-down decides the value of a pin only while nothing drives
  it: the interface, the DUT, or anything else. A pin has at most one pull; the latest call
  for it counts, and `pull_none()` takes it away.
- **Force.** `force_pins(value, mask)` gives the selected pins the value whatever else
  drives them, the DUT included, until `release_pins()`; it is the `force` statement of the
  language. The drive and the pull settings of a forced pin are kept and count again after
  the release.
- **Sample.** `sample()` returns the pins as they are, X and Z included. `holds(value,
  mask)` is 1 when the selected pins equal the bits of `value`, compared with `===`.
  `wait_value()` waits until they do, and returns at once when they already do: a Z or an X
  in `value` waits for a Z or an X on the pin. `wait_change()` returns at the next change of
  a selected pin, also between X, Z and a level. Neither has a time limit; wrap them in
  `` `hexk_spinwait `` where a pin may never change.
- **One pin.** `drive_pin()`, `float_pin()` and `sample_pin()` do the same as the functions
  with a mask that has only that bit; `mask_of(index)` is that mask, for the other
  functions. An `index` of `WIDTH` or above is the error `HEXK_PINS_INDEX`: the mask is
  empty, nothing is driven, and `sample_pin()` returns X.
- `convert2string()` gives one character per pin, pin `WIDTH-1` first, for what the
  interface does and for what the pins hold, such as
  `drive=--1- pull=u--d force=-1-- pins=1110`: the driven or forced value or `-`, and `u`,
  `d` or `-` for the pull.
- `WIDTH` is at least 1. Interfaces with different `WIDTH` are different types for a virtual
  interface handle.

Simulators:

- The interface needs nets with several drivers, drive strengths and `force` on a net.
  Verilator 5.046 has none of them (probed): it rejects a drive strength on one bit of a net
  and a `force` on such a net, and it does not resolve the drivers of a pin. Where
  `HEXK_SIM_NO_PIN_MODEL` of `hexk_sim_compat.svh` is defined, which is on Verilator, the
  interface is compiled without them: the functions that would change a pin do nothing, the
  first call of one is the error `HEXK_PINS_UNSUPPORTED`, and `sample()`, `holds()` and the
  two waits see what the DUT drives.

## 5. Configuration

| Parameter | Default | Meaning |
|---|---|---|
| `WIDTH` | 1 | Number of pins. |

There are no plusargs. `HEXK_SIM_NO_PIN_MODEL` is set by `hexk_sim_compat.svh` for Verilator;
it is not a switch for the user.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_PINS_INDEX` | error |  |
| `HEXK_PINS_UNSUPPORTED` | error |  |
<!-- HEXK_GEN:END emits -->

| ID | Meaning |
|---|---|
| `HEXK_PINS_INDEX` | A pin number is not below `WIDTH`. |
| `HEXK_PINS_UNSUPPORTED` | The simulator cannot model the pins; the interface changes none. Once per interface. |

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_pins/hexk_pins_example.sv`, elaborated in Gate 1:

```systemverilog
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
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Sampling in the same time step as a change**, as in `vif.drive(v); x = vif.sample();`.
  The pins change after the call; let time pass, or wait with `wait_value()`.
- **`force_pins()` where `drive()` would do.** A force hides what the DUT drives, also a
  bug that makes the DUT drive a pin it should not. Drive straps and inputs; force only to
  override an output of the DUT on purpose, and release it.
- **Leaving a force in place at the end of a sequence.** The next sequence finds pins that
  ignore the DUT. Release what you force.
- **Driving a pin that the DUT also drives** to "win". Two ordinary drivers give X. Use a
  pull for a default that the DUT may override, or a force to override the DUT.
- **A wait without a time limit** for a pin that the DUT may never change. Wrap it:
  `` `hexk_spinwait(vif.wait_value('1, mask);, 1ms, "MY_IRQ") ``.
- **Pins with a clocked protocol.** There is no clock and no sampling point here; write an
  agent, or use `hexk_valid_ready`.
- **Running a test that uses the pins on Verilator.** The interface says
  `HEXK_PINS_UNSUPPORTED` and changes nothing there.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests and the
example run on Questa and VCS. On Verilator the interface is compiled without the pin model, and one
unit test checks that it reports that and leaves the pins to the DUT; nothing else of this
module is simulated there.
