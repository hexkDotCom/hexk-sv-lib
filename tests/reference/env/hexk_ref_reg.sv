// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_reg.sv
//
// One register of the register model of the reference DUT: a 32-bit uvm_reg whose fields its
// block adds with new_field(), so that one class serves every register.

`ifndef HEXK_REF_REG_SV
`define HEXK_REF_REG_SV

// A register whose fields its block adds with new_field().
class hexk_ref_reg extends uvm_reg;

   `uvm_object_utils(hexk_ref_reg)

   // Creates a 32-bit register.
   function new(string name = "hexk_ref_reg");
      super.new(name, 32, UVM_NO_COVERAGE);
   endfunction : new

   // Adds a field and returns it, created through the factory under the name of this register. Its field is not
   // individually accessible: a write of one field is a write of the whole register.
   function uvm_reg_field new_field(string field_name, int unsigned size, int unsigned lsb, string access,
                                    uvm_reg_data_t reset_value = 0, bit is_volatile = 0, bit with_reset = 1);
      uvm_reg_field field = uvm_reg_field::type_id::create(field_name, null, get_full_name());
      field.configure(this, size, lsb, access, is_volatile, reset_value, with_reset, 1, 0);
      return field;
   endfunction : new_field

endclass : hexk_ref_reg

`endif  // HEXK_REF_REG_SV
