// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_csr_util_example.sv
//
// Minimal use of hexk_csr_util on a register model with two registers: ctrl with the field
// en, and status with the fields done and an error counter that the example excludes from
// the reset check. The registers reach a register file of this module through a frontdoor
// that takes 10 ns per access, in place of a bus agent; the "DUT" sets done 50 ns after en
// was written. The example checks the reset values, starts the DUT, waits for done with a
// spin-wait and checks status with a mask.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_csr_util_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_csr_util;
   import hexk_uvm_pkg::HEXK_CSR_RESET_CHECK;
   `include "uvm_macros.svh"

   // The register file of the DUT: ctrl at 0, status at 4.
   bit [31:0] dut_regs[int unsigned];

   // Frontdoor of one register: 10 ns per access to the register file.
   class hexk_example_frontdoor extends uvm_reg_frontdoor;
      local int unsigned address;

      `uvm_object_utils(hexk_example_frontdoor)

      function new(string name = "hexk_example_frontdoor");
         super.new(name);
      endfunction : new

      // The address of the register in the register file.
      function void set_address(int unsigned value);
         address = value;
      endfunction : set_address

      virtual task body();
         #10ns;
         if (rw_info.kind == UVM_WRITE) begin
            dut_regs[address] = 32'(rw_info.value[0]);
         end else begin
            rw_info.value[0] = 64'(dut_regs[address]);
         end
         rw_info.status = UVM_IS_OK;
      endtask : body
   endclass : hexk_example_frontdoor

   // A register of 32 bits whose fields the block adds.
   class hexk_example_reg extends uvm_reg;
      `uvm_object_utils(hexk_example_reg)

      function new(string name = "hexk_example_reg");
         super.new(name, 32, UVM_NO_COVERAGE);
      endfunction : new
   endclass : hexk_example_reg

   // ctrl: en (RW, bit 0); status: done (RO, bit 0), errors (RO, bits 15:8, reset 0, counts as the DUT runs).
   class hexk_example_block extends uvm_reg_block;
      hexk_example_reg ctrl;
      hexk_example_reg status;
      uvm_reg_field en;
      uvm_reg_field done;
      uvm_reg_field errors;

      `uvm_object_utils(hexk_example_block)

      function new(string name = "hexk_example_block");
         super.new(name, UVM_NO_COVERAGE);
      endfunction : new

      function void build();
         default_map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
         ctrl        = new_reg("ctrl", 0);
         en          = new_field(ctrl, "en", 1, 0, "RW");
         status      = new_reg("status", 4);
         done        = new_field(status, "done", 1, 0, "RO");
         errors      = new_field(status, "errors", 8, 8, "RO");
         lock_model();
         // The frontdoors after lock_model(): UVM warns that a map is not initialized when one is set before.
         ctrl.set_frontdoor(new_frontdoor("ctrl", 0));
         status.set_frontdoor(new_frontdoor("status", 4));
      endfunction : build

      local function hexk_example_reg new_reg(string name, int unsigned address);
         hexk_example_reg rg = hexk_example_reg::type_id::create(name);
         rg.configure(this);
         default_map.add_reg(rg, uvm_reg_addr_t'(address), "RW");
         return rg;
      endfunction : new_reg

      local function hexk_example_frontdoor new_frontdoor(string name, int unsigned address);
         hexk_example_frontdoor fd = hexk_example_frontdoor::type_id::create({"fd_", name});
         fd.set_address(address);
         return fd;
      endfunction : new_frontdoor

      local function uvm_reg_field new_field(hexk_example_reg rg, string name, int unsigned width, int unsigned lsb,
                                             string access);
         uvm_reg_field field = uvm_reg_field::type_id::create(name);
         field.configure(rg, width, lsb, access, 0, 0, 1, 1, 0);
         return field;
      endfunction : new_field
   endclass : hexk_example_block

   hexk_example_block regmodel;
   hexk_csr_util csr;

   // The DUT: done 50 ns after en is set; the error counter of a run that went wrong once.
   initial begin
      dut_regs[0] = 0;
      dut_regs[4] = 'h300;
      wait (dut_regs[0][0] == 1'b1);
      #50ns;
      dut_regs[4][0] = 1'b1;
   end

   initial begin
      bit seen;
      regmodel = hexk_example_block::type_id::create("regmodel");
      regmodel.build();
      csr                  = hexk_csr_util::type_id::create("csr");
      csr.poll_interval_ps = `hexk_ps(20ns);
      csr.timeout_ps       = `hexk_ps(1us);

      // The error counter is no reset value but a count; it does not take part in the reset check.
      hexk_csr_util::exclude ("regmodel.status.errors", HEXK_CSR_RESET_CHECK);
      csr.check_reset_values(regmodel);

      // Start the DUT, wait for done, and check that done is set and en still is.
      csr.write(regmodel.ctrl, 1);
      csr.spinwait_field(regmodel.done, 1, "EXAMPLE_DONE", seen);
      `uvm_info("EXAMPLE", $sformatf("done seen: %0b at %0t", seen, $time), UVM_NONE)
      csr.read_check(regmodel.status, 'h1, "EXAMPLE_STATUS", 'hFF);
      csr.read_field_check(regmodel.en, 1, "EXAMPLE_EN");
   end

endmodule : hexk_csr_util_example
