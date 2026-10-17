// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_reg_adapter.sv
//
// Turns register operations of the UVM register model into bus items and back. A bus item that
// timed out gives UVM_NOT_OK, which hexk_csr_util reports.

`ifndef HEXK_REF_REG_ADAPTER_SV
`define HEXK_REF_REG_ADAPTER_SV

class hexk_ref_reg_adapter extends uvm_reg_adapter;

   `uvm_object_utils(hexk_ref_reg_adapter)

   // Creates the adapter; byte enables are supported.
   function new(string name = "hexk_ref_reg_adapter");
      super.new(name);
      supports_byte_enable = 1;
      provides_responses   = 0;
   endfunction : new

   // A register operation as a bus item.
   function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
      hexk_ref_bus_item item = hexk_ref_bus_item::type_id::create("item");
      uvm_reg_addr_t    addr = rw.addr;
      // A map with an address beyond the bus would otherwise reach another register.
      void'(hexk_ref_bus_seq::is_bus_address(addr));
      item.we    = (rw.kind == UVM_WRITE);
      item.addr  = 9'(rw.addr);
      item.wdata = 32'(rw.data);
      // The byte enables as the register layer gives them: all ones for a whole register, none for a write
      // that changes no byte.
      item.wstrb = 4'(rw.byte_en);
      return item;
   endfunction : reg2bus

   // A bus item as a register operation.
   function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
      hexk_ref_bus_item item;
      if (bus_item == null || !$cast(item, bus_item)) begin
         `uvm_fatal("REF_ADAPTER", "bus2reg got null or an item of another class")
         return;
      end
      rw.kind    = item.we ? UVM_WRITE : UVM_READ;
      rw.addr    = uvm_reg_addr_t'(item.addr);
      rw.data    = item.we ? uvm_reg_data_t'(item.wdata) : uvm_reg_data_t'(item.rdata);
      rw.byte_en = uvm_reg_byte_en_t'(item.wstrb);
      // An access without ack or cut off by a reset gave no value the register model can hold, nor did a read of X or Z
      // bits, which the model gets as UVM_HAS_X (guide TRN-6).
      if (item.is_ok()) begin
         rw.status = UVM_IS_OK;
      end else if (item.status == HEXK_REF_BUS_OK) begin
         rw.status = UVM_HAS_X;
      end else begin
         rw.status = UVM_NOT_OK;
      end
   endfunction : bus2reg

endclass : hexk_ref_reg_adapter

`endif  // HEXK_REF_REG_ADAPTER_SV
