// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_commit_item.sv
//
// One code word that the DUT writes to its RAM: the word address and the 39-bit code word. The
// monitor sees it on the commit port; the predictor expects it, delayed by the pipeline.

`ifndef HEXK_REF_COMMIT_ITEM_SV
`define HEXK_REF_COMMIT_ITEM_SV

class hexk_ref_commit_item extends uvm_sequence_item;

   // Word address in the RAM; four-state, as the monitor samples it, so that X or Z does not compare equal.
   logic [ 5:0] addr;

   // The code word; four-state, as the address.
   logic [38:0] code;

   `uvm_object_utils(hexk_ref_commit_item)

   // Creates an item.
   function new(string name = "hexk_ref_commit_item");
      super.new(name);
   endfunction : new

   // Address and code word on one line.
   function string convert2string();
      return $sformatf("commit [%0d] = 39'h%010h", addr, code);
   endfunction : convert2string

   // UVM hook of copy() and clone().
   function void do_copy(uvm_object rhs);
      hexk_ref_commit_item other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("REF_COPY", "do_copy from another class")
         return;
      end
      addr = other.addr;
      code = other.code;
   endfunction : do_copy

   // UVM hook of compare(): both members, through the comparer.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_ref_commit_item other;
      bit                  same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      same = comparer.compare_field_int("addr", 64'(addr), 64'(other.addr), $bits(addr));
      same &= comparer.compare_field_int("code", 64'(code), 64'(other.code), $bits(code));
      return same;
   endfunction : do_compare

   // UVM hook of print() and sprint(): the address and the code word.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_field("addr", uvm_bitstream_t'(addr), $bits(addr), UVM_DEC);
      printer.print_field("code", uvm_bitstream_t'(code), $bits(code), UVM_HEX);
   endfunction : do_print

endclass : hexk_ref_commit_item

`endif  // HEXK_REF_COMMIT_ITEM_SV
