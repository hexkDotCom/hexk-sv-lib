// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uid_example.sv
//
// Minimal use of hexk_uid: two write sequences each take an ID from the pool and give every
// item they create a child of it. A message that prints the ID of an item then says which
// item of which sequence it is, however the two sequences are interleaved.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_uid_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   `include "uvm_macros.svh"

   // Stands for a sequence: it has an ID, and its items get children of that ID.
   class hexk_example_sequence;
      hexk_uid uid;

      function new();
         hexk_uid_pool pool = hexk_uid_pool::get();
         uid = pool.new_uid("seq_wr");
      endfunction : new

      // Creates the ID of the next item of this sequence and reports it.
      function void send_item();
         hexk_uid item_uid = uid.new_child("item");
         `uvm_info("EXAMPLE", $sformatf("sending %s", item_uid.convert2string()), UVM_NONE)
      endfunction : send_item
   endclass : hexk_example_sequence

   initial begin
      hexk_example_sequence first;
      hexk_example_sequence second;
      first  = new();
      second = new();
      first.send_item();
      second.send_item();
      first.send_item();
      first.send_item();
      second.send_item();
   end

endmodule : hexk_uid_example
