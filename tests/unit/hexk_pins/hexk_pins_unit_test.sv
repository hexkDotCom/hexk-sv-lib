// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_pins_unit_test.sv
//
// SVUnit tests of hexk_pins_if with four pins.
// The test module plays the DUT: it drives each pin, or leaves it alone, through a driver
// with an enable. A test changes the settings of the interface and of the DUT and looks at
// the pins one nanosecond later, as text, pin 3 first. One test uses the interface from a
// class through a virtual interface handle, which is how a test or a sequence uses it.
// The interface needs nets with several drivers, drive strengths and force. They are missing
// in Verilator 5.046: there hexk_pins_if is compiled without them, and one test checks that
// it says so and leaves the pins to the DUT. The other tests, and the DUT with its enables,
// are compiled for the other simulators.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_pins.

`include "svunit_defines.svh"

module hexk_pins_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   localparam int unsigned WIDTH = 4;

   // What a test or a sequence does: it holds a handle of the interface and calls its functions.
   class hexk_ut_pins_user;
      virtual hexk_pins_if #(WIDTH) vif;

      // Drives pin 1 to 1 and pulls pin 2 down.
      function void set_up();
         vif.drive_pin(1, 1'b1);
         vif.pull_down(4'b0100);
      endfunction : set_up

      // What the pins hold.
      function string pins_text();
         return $sformatf("%b", vif.sample());
      endfunction : pins_text
   endclass : hexk_ut_pins_user

   string          name = "hexk_pins_ut";
   svunit_testcase svunit_ut;

   hexk_pins_if #(.WIDTH(WIDTH)) pins_if ();

   hexk_report_catcher catcher;
   hexk_ut_pins_user   user;
   string              result;

`ifdef VERILATOR
   // Without a pin model the DUT is the only driver.
   assign pins_if.pins = 4'b0110;
`else
   // The DUT: drives the pins whose enable is set.
   logic [WIDTH-1:0] dut_value = '0;
   bit   [WIDTH-1:0] dut_enable = '0;

   for (genvar i = 0; i < WIDTH; i++) begin : gen_dut_pin
      assign pins_if.pins[i] = dut_enable[i] ? dut_value[i] : 1'bz;
   end : gen_dut_pin
`endif

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
      user      = new();
      user.vif  = pins_if;
   endfunction : build

   // Every test starts with an interface that drives, pulls and forces nothing, and a DUT that drives nothing.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_PINS_INDEX$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_PINS_UNSUPPORTED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      result = "";
`ifndef VERILATOR
      pins_if.release_pins();
      pins_if.float_pins();
      pins_if.pull_none();
      dut_enable = '0;
      #1ns;
`endif
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // Errors of the interface in this test, as "<index> <unsupported>".
   function automatic string errors();
      return $sformatf("%0d %0d", catcher.get_count("^HEXK_PINS_INDEX$"), catcher.get_count("^HEXK_PINS_UNSUPPORTED$"));
   endfunction : errors

   // The pins one nanosecond from now, pin 3 first.
   task automatic look();
      #1ns;
      result = $sformatf("%b", pins_if.sample());
   endtask : look

`ifndef VERILATOR
   // The DUT drives the pins of mask to the bits of value and leaves the others alone.
   function automatic void dut_drives(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask);
      dut_value  = value;
      dut_enable = mask;
   endfunction : dut_drives

   // Starts a wait for the pins of mask to hold value and notes the nanoseconds it took in result; "waiting"
   // until then.
   task automatic start_wait_value(logic [WIDTH-1:0] value, bit [WIDTH-1:0] mask);
      realtime began = $realtime;
      result = "waiting";
      fork
         begin
            pins_if.wait_value(value, mask);
            result = $sformatf("%0d", int'(($realtime - began) / 1ns));
         end
      join_none
   endtask : start_wait_value

   // Starts a wait for a change of the pins of mask and notes the nanoseconds it took in result.
   task automatic start_wait_change(bit [WIDTH-1:0] mask);
      realtime began = $realtime;
      result = "waiting";
      fork
         begin
            pins_if.wait_change(mask);
            result = $sformatf("%0d", int'(($realtime - began) / 1ns));
         end
      join_none
   endtask : start_wait_change

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // What the functions for one pin give for pin 2 and for a pin that does not exist:
   // "<pin 2> <pin 9> <mask of pin 2> <mask of pin 9>".
   function automatic string pin_functions();
      return $sformatf("%b %b %b %b", pins_if.sample_pin(2), pins_if.sample_pin(9), pins_if.mask_of(2),
                       pins_if.mask_of(9));
   endfunction : pin_functions
`endif

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

`ifdef VERILATOR
   `SVTEST(without_a_pin_model_the_interface_says_so_once_and_leaves_the_pins_to_the_dut)
      pins_if.drive(4'b1111);
      pins_if.pull_up(4'b0001);
      pins_if.force_pins(4'b0000);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "0110")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 1")
   `SVTEST_END
`else
   `SVTEST(a_pin_that_nothing_drives_is_z)
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zzzz")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0")
   `SVTEST_END

   `SVTEST(drive_sets_the_pins_of_the_mask_and_float_pins_lets_them_go)
      pins_if.drive(4'b0110, 4'b0011);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zz10")
      pins_if.drive(4'b1001, 4'b1001);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "1z11")
      pins_if.float_pins(4'b0001);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "1z1z")
      pins_if.float_pins();
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zzzz")
   `SVTEST_END

   `SVTEST(an_x_bit_drives_x_and_a_z_bit_drives_nothing)
      pins_if.pull_up(4'b0010);
      pins_if.drive(4'b1xz0);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "1x10")
   `SVTEST_END

   `SVTEST(a_pull_decides_while_nothing_drives_the_pin)
      pins_if.pull_up(4'b0011);
      pins_if.pull_down(4'b1100);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "0011")
      pins_if.drive(4'b0100, 4'b0101);
      dut_drives(4'b1000, 4'b1010);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "1100")
      pins_if.float_pins();
      dut_drives(4'b0000, 4'b0000);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "0011")
   `SVTEST_END

   `SVTEST(the_latest_pull_of_a_pin_counts_and_pull_none_takes_it_away)
      pins_if.pull_up();
      pins_if.pull_down(4'b0001);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "1110")
      pins_if.pull_none(4'b1100);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zz10")
   `SVTEST_END

   `SVTEST(two_drivers_with_different_values_give_x)
      dut_drives(4'b0001, 4'b0011);
      pins_if.drive(4'b0011, 4'b0011);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zzx1")
   `SVTEST_END

   `SVTEST(a_force_wins_against_the_dut_and_the_drive_and_ends_with_release_pins)
      dut_drives(4'b0000, 4'b0001);
      pins_if.drive(4'b0000, 4'b0010);
      pins_if.pull_down(4'b0100);
      pins_if.force_pins(4'b0111, 4'b0111);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "z111")
      pins_if.release_pins(4'b0011);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "z100")
      pins_if.release_pins();
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "z000")
   `SVTEST_END

   `SVTEST(the_functions_for_one_pin_work_by_number)
      pins_if.drive_pin(2, 1'b1);
      pins_if.drive_pin(0, 1'b0);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "z1z0")
      `FAIL_UNLESS_STR_EQUAL(pin_functions(), "1 x 0100 0000")
      pins_if.float_pin(2);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zzz0")
      `FAIL_UNLESS_STR_EQUAL(errors(), "2 0")
   `SVTEST_END

   `SVTEST(a_pin_that_does_not_exist_is_an_error_and_nothing_is_driven)
      pins_if.drive_pin(4, 1'b1);
      pins_if.float_pin(7);
      look();
      `FAIL_UNLESS_STR_EQUAL(result, "zzzz")
      `FAIL_UNLESS_STR_EQUAL(errors(), "2 0")
   `SVTEST_END

   `SVTEST(wait_value_returns_when_the_pins_of_the_mask_hold_the_value)
      pins_if.pull_up(4'b0001);
      advance(1ns);
      start_wait_value(4'b0000, 4'b0001);
      advance(5ns);
      `FAIL_UNLESS_STR_EQUAL(result, "waiting")
      dut_drives(4'b1110, 4'b1111);
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(result, "5")
      start_wait_value(4'b1110, 4'b1111);
      advance(1ns);
      `FAIL_UNLESS_STR_EQUAL(result, "0")
   `SVTEST_END

   `SVTEST(wait_value_can_wait_for_a_pin_to_be_let_go)
      dut_drives(4'b0001, 4'b0001);
      advance(1ns);
      start_wait_value(4'bzzzz, 4'b0001);
      advance(3ns);
      dut_drives(4'b0000, 4'b0000);
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(result, "3")
   `SVTEST_END

   `SVTEST(wait_change_returns_at_the_next_change_of_a_pin_of_the_mask)
      dut_drives(4'b0000, 4'b1111);
      advance(1ns);
      start_wait_change(4'b1000);
      advance(2ns);
      dut_drives(4'b0001, 4'b1111);
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(result, "waiting")
      dut_drives(4'b1001, 4'b1111);
      advance(2ns);
      `FAIL_UNLESS_STR_EQUAL(result, "4")
   `SVTEST_END

   `SVTEST(convert2string_shows_what_the_interface_does_and_what_the_pins_hold)
      pins_if.drive(4'b0010, 4'b0010);
      pins_if.pull_up(4'b1000);
      pins_if.pull_down(4'b0001);
      pins_if.force_pins(4'b0100, 4'b0100);
      advance(1ns);
      `FAIL_UNLESS_STR_EQUAL(pins_if.convert2string(), "drive=--1- pull=u--d force=-1-- pins=1110")
   `SVTEST_END

   `SVTEST(a_class_uses_the_interface_through_a_virtual_interface_handle)
      user.set_up();
      advance(1ns);
      `FAIL_UNLESS_STR_EQUAL(user.pins_text(), "z01z")
   `SVTEST_END
`endif

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_pins_unit_test
