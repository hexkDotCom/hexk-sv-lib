// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_meta_item_unit_test.sv
//
// SVUnit tests of hexk_meta_item, with a small item class as T.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_meta_item.

`include "svunit_defines.svh"
`include "uvm_macros.svh"

module hexk_meta_item_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_meta_item;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;

   // Item with one compared field.
   class hexk_ut_packet extends uvm_object;
      int unsigned data;

      function new(string object_name = "hexk_ut_packet");
         super.new(object_name);
      endfunction : new

      virtual function string convert2string();
         return $sformatf("data=%0d", data);
      endfunction : convert2string

      virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_ut_packet other;
         return $cast(other, rhs) && other.data == data;
      endfunction : do_compare
   endclass : hexk_ut_packet

   typedef hexk_meta_item#(hexk_ut_packet) hexk_ut_meta_t;

   // A meta item that the factory test puts in place of hexk_meta_item #(uvm_object), which no other test uses.
   class hexk_ut_object_meta extends hexk_meta_item #(uvm_object);
      `uvm_object_utils(hexk_ut_object_meta)

      function new(string object_name = "hexk_ut_object_meta");
         super.new(object_name);
      endfunction : new
   endclass : hexk_ut_object_meta

   string           name = "hexk_meta_item_ut";
   svunit_testcase  svunit_ut;

   longint unsigned start_ps;

   function automatic void build();
      svunit_ut = new(name);
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      hexk_uid_pool::reset_for_test();
      start_ps = hexk_uvm_pkg::hexk_wait_util::now_ps();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_uid_pool::reset_for_test();
   endtask : teardown

   // A packet with the given data.
   function automatic hexk_ut_packet packet_of(int unsigned data);
      hexk_ut_packet packet = new();
      packet.data = data;
      return packet;
   endfunction : packet_of

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // What wrap() stores: "<same item> <nanoseconds since the start of the test> <source> <uid>".
   function automatic string wrapped();
      hexk_uid_pool  pool = hexk_uid_pool::get();
      hexk_uid       uid = pool.new_uid("pkt");
      hexk_ut_packet packet = packet_of(7);
      hexk_ut_meta_t meta = hexk_ut_meta_t::wrap(packet, "env.monitor", uid);
      return $sformatf(
          "%0d %0dns %s %s",
          meta.item == packet,
          (meta.timestamp_ps - start_ps) / 1000,
          meta.source,
          meta.uid.convert2string()
      );
   endfunction : wrapped

   // "equal" or "different" for two meta items whose packets hold the given data and whose meta data differ.
   function automatic string compare_packets(int unsigned first_data, int unsigned second_data);
      hexk_ut_meta_t first = hexk_ut_meta_t::wrap(packet_of(first_data), "monitor_a");
      hexk_ut_meta_t second = hexk_ut_meta_t::wrap(packet_of(second_data), "monitor_b");
      second.timestamp_ps = first.timestamp_ps + 5000;
      if (first.compare(second)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_packets

   // "equal" or "different" for meta items of which none, one or both have no item.
   function automatic string compare_empty(bit first_empty, bit second_empty);
      hexk_ut_meta_t first = hexk_ut_meta_t::wrap(first_empty ? null : packet_of(1));
      hexk_ut_meta_t second = hexk_ut_meta_t::wrap(second_empty ? null : packet_of(1));
      if (first.compare(second)) begin
         return "equal";
      end
      return "different";
   endfunction : compare_empty

   // The text of a meta item without the time, which depends on the simulation.
   function automatic string text_of(bit with_uid, bit with_source, bit with_item);
      hexk_uid_pool pool = hexk_uid_pool::get();
      hexk_uid uid = with_uid ? pool.new_uid("pkt") : null;
      hexk_ut_meta_t meta = hexk_ut_meta_t::wrap(
          with_item ? packet_of(9) : null, with_source ? "env.monitor" : "", uid
      );
      string text;
      string time_text;
      meta.timestamp_ps = 0;
      text              = meta.convert2string();
      time_text         = $sformatf("@%0t", meta.timestamp_ps);
      return hexk_core_pkg::hexk_str::replace(text, time_text, "@T");
   endfunction : text_of

   // "same" when a clone refers to the item and ID of the original and has its time and source.
   function automatic string clone_shares();
      hexk_uid_pool  pool = hexk_uid_pool::get();
      hexk_ut_meta_t meta = hexk_ut_meta_t::wrap(packet_of(3), "src", pool.new_uid("pkt"));
      hexk_ut_meta_t cloned;
      uvm_object     copied = meta.clone();
      void'($cast(cloned, copied));
      if (cloned.item == meta.item && cloned.uid == meta.uid && cloned.timestamp_ps == meta.timestamp_ps &&
          cloned.source == "src") begin
         return "same";
      end
      return "not the same";
   endfunction : clone_shares

   // The type name of an object and its fields as the line printer shows them, from the opening brace on; the
   // instance number before it differs from run to run.
   function automatic string printed_fields(uvm_object object);
      uvm_line_printer printer = new();
      string           text = object.sprint(printer);
      int              brace = hexk_core_pkg::hexk_str::find(text, "{");
      return {object.get_type_name(), " ", hexk_core_pkg::hexk_str::strip(text.substr(brace, text.len() - 1))};
   endfunction : printed_fields

   // A meta item without an item as the printer shows it.
   function automatic string printed_meta();
      hexk_uid_pool  pool = hexk_uid_pool::get();
      hexk_ut_meta_t meta = hexk_ut_meta_t::wrap(null, "env.monitor", pool.new_uid("pkt"));
      meta.timestamp_ps = 25000;
      return printed_fields(meta);
   endfunction : printed_meta

   // The class of the meta item that wrap() creates while a type override replaces the meta item of objects.
   function automatic string wrapped_class();
      hexk_meta_item#(uvm_object)::type_id::set_type_override(hexk_ut_object_meta::get_type());
      return hexk_meta_item#(uvm_object)::wrap(packet_of(1)).get_type_name();
   endfunction : wrapped_class

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(wrap_keeps_the_item_and_stamps_it_with_the_time)
      advance(25ns);
      `FAIL_UNLESS_STR_EQUAL(wrapped(), "1 25ns env.monitor pkt:000000")
   `SVTEST_END

   `SVTEST(compare_looks_at_the_items_only)
      `FAIL_UNLESS_STR_EQUAL(compare_packets(4, 4), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_packets(4, 5), "different")
   `SVTEST_END

   `SVTEST(two_meta_items_without_an_item_are_equal)
      `FAIL_UNLESS_STR_EQUAL(compare_empty(1, 1), "equal")
      `FAIL_UNLESS_STR_EQUAL(compare_empty(1, 0), "different")
      `FAIL_UNLESS_STR_EQUAL(compare_empty(0, 1), "different")
   `SVTEST_END

   `SVTEST(the_text_has_id_time_source_and_item)
      `FAIL_UNLESS_STR_EQUAL(text_of(1, 1, 1), "pkt:000000 @T from env.monitor: data=9")
      `FAIL_UNLESS_STR_EQUAL(text_of(0, 0, 1), "@T: data=9")
      `FAIL_UNLESS_STR_EQUAL(text_of(0, 1, 0), "@T from env.monitor: null")
   `SVTEST_END

   `SVTEST(a_meta_item_prints_id_time_source_and_item)
      `FAIL_UNLESS_STR_EQUAL(printed_meta(),
         "hexk_meta_item { uid: pkt:000000  timestamp_ps: 'd25000  source: env.monitor  item: <null>  }")
   `SVTEST_END

   `SVTEST(wrap_creates_the_meta_item_through_the_factory)
      `FAIL_UNLESS_STR_EQUAL(wrapped_class(), "hexk_ut_object_meta")
   `SVTEST_END

   `SVTEST(a_clone_refers_to_the_same_item_and_id)
      `FAIL_UNLESS_STR_EQUAL(clone_shares(), "same")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_meta_item_unit_test
