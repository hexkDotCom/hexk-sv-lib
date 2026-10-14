// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_meta_item_example.sv
//
// Minimal use of hexk_meta_item: a monitor wraps each packet it sees together with the
// time, an ID and its own name. The receiver compares two meta items, which compares the
// packets, and uses the timestamps for the latency between request and response.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_meta_item_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_meta_item;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   `include "uvm_macros.svh"

   class hexk_example_packet extends uvm_object;
      int unsigned data;

      `uvm_object_utils(hexk_example_packet)

      function new(string name = "hexk_example_packet");
         super.new(name);
      endfunction : new

      function void set_data(int unsigned value);
         data = value;
      endfunction : set_data

      virtual function string convert2string();
         return $sformatf("data=%0d", data);
      endfunction : convert2string

      virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_example_packet other;
         return $cast(other, rhs) && other.data == data;
      endfunction : do_compare
   endclass : hexk_example_packet

   typedef hexk_meta_item#(hexk_example_packet) hexk_example_meta_packet_t;

   // Stands for a monitor: wraps a packet with the time, an ID and a source name.
   function automatic hexk_example_meta_packet_t observe(string monitor, int unsigned data);
      hexk_uid_pool       pool = hexk_uid_pool::get();
      hexk_example_packet packet = hexk_example_packet::type_id::create("packet");
      packet.set_data(data);
      return hexk_example_meta_packet_t::wrap(packet, monitor, pool.new_uid("pkt"));
   endfunction : observe

   initial begin
      hexk_example_meta_packet_t request;
      hexk_example_meta_packet_t response;
      request = observe("env.in_monitor", 42);
      #30ns;
      response = observe("env.out_monitor", 42);
      `uvm_info("EXAMPLE", request.convert2string(), UVM_NONE)
      `uvm_info("EXAMPLE", response.convert2string(), UVM_NONE)
      if (request.compare(response)) begin
         `uvm_info("EXAMPLE", $sformatf("match after %0d ps", response.timestamp_ps - request.timestamp_ps), UVM_NONE)
      end else begin
         `uvm_error("EXAMPLE", "the packets differ")
      end
   end

endmodule : hexk_meta_item_example
