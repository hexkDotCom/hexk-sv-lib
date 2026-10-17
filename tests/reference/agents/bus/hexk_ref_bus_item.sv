// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_item.sv
//
// One access of the register bus of the reference DUT: what the driver drives and what the
// monitor saw. A read gives its data in rdata. The driver sets status: whether the access got its
// ack, or ended without one, or was cut off by a reset.

`ifndef HEXK_REF_BUS_ITEM_SV
`define HEXK_REF_BUS_ITEM_SV

// How an access ended, as the driver saw it.
typedef enum bit [1:0] {
   HEXK_REF_BUS_OK,
   HEXK_REF_BUS_NO_ACK,
   HEXK_REF_BUS_RESET
} hexk_ref_bus_status_e;

class hexk_ref_bus_item extends uvm_sequence_item;

   // 1 for a write.
   rand bit                     we;

   // Byte address, word aligned.
   rand bit              [ 8:0] addr;

   // Data of a write, and its byte enables.
   rand bit              [31:0] wdata;
   rand bit              [ 3:0] wstrb     = 4'hF;

   // Data of a read, set by the driver and the monitor; four-state, so that X or Z read from the DUT is seen.
   logic                 [31:0] rdata;

   // Set by the monitor: the time in picoseconds of the rising edge at which the DUT took the access.
   longint unsigned             taken_ps;

   // Set by the driver: how the access ended.
   hexk_ref_bus_status_e        status;

   `uvm_object_utils(hexk_ref_bus_item)

   constraint aligned_cstr {addr[1:0] == 2'b00;}

   // Creates an item.
   function new(string name = "hexk_ref_bus_item");
      super.new(name);
   endfunction : new

   // 1 when the access ended with its ack and, for a read, with data without X or Z bits.
   function bit is_ok();
      return status == HEXK_REF_BUS_OK && (we || !$isunknown(rdata));
   endfunction : is_ok

   // The access on one line.
   function string convert2string();
      string ending = (status == HEXK_REF_BUS_OK) ? "" : $sformatf(" (%s)", status.name());
      if (we) begin
         return $sformatf("write 0x%03h = 0x%08h strb %04b%s", addr, wdata, wstrb, ending);
      end
      return $sformatf("read 0x%03h = 0x%08h%s", addr, rdata, ending);
   endfunction : convert2string

   // UVM hook of copy() and clone().
   function void do_copy(uvm_object rhs);
      hexk_ref_bus_item other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("REF_COPY", "do_copy from another class")
         return;
      end
      we       = other.we;
      addr     = other.addr;
      wdata    = other.wdata;
      wstrb    = other.wstrb;
      rdata    = other.rdata;
      taken_ps = other.taken_ps;
      status   = other.status;
   endfunction : do_copy

   // UVM hook of compare(): the access, through the comparer; taken_ps and status are not compared, and of the data
   // only that of the direction (wdata of a write, rdata of a read, X and Z bits included).
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_ref_bus_item other;
      bit               same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      same = comparer.compare_field_int("we", 64'(we), 64'(other.we), 1);
      same &= comparer.compare_field_int("addr", 64'(addr), 64'(other.addr), $bits(addr));
      same &= comparer.compare_field_int("wstrb", 64'(wstrb), 64'(other.wstrb), $bits(wstrb));
      if (we) begin
         same &= comparer.compare_field_int("wdata", 64'(wdata), 64'(other.wdata), $bits(wdata));
      end else begin
         same &= comparer.compare_field("rdata", uvm_bitstream_t'(rdata), uvm_bitstream_t'(other.rdata), $bits(rdata));
      end
      return same;
   endfunction : do_compare

   // UVM hook of print() and sprint(): every member.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_field_int("we", 64'(we), 1, UVM_BIN);
      printer.print_field_int("addr", 64'(addr), $bits(addr), UVM_HEX);
      printer.print_field_int("wdata", 64'(wdata), $bits(wdata), UVM_HEX);
      printer.print_field_int("wstrb", 64'(wstrb), $bits(wstrb), UVM_BIN);
      printer.print_field("rdata", uvm_bitstream_t'(rdata), $bits(rdata), UVM_HEX);
      printer.print_field_int("taken_ps", taken_ps, 64, UVM_DEC);
      printer.print_string("status", status.name());
   endfunction : do_print

endclass : hexk_ref_bus_item

`endif  // HEXK_REF_BUS_ITEM_SV
