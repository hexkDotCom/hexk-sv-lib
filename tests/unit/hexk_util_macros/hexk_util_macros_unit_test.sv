// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_util_macros_unit_test.sv
//
// SVUnit tests of the macros in hexk_util_macros.svh.
// Each macro is used the way a testbench uses it: a singleton class, a component with three
// indexed analysis imps that are connected to three analysis ports, a small interface whose
// virtual interface travels through uvm_config_db, and a class with random address ranges.
// The fatal of `hexk_vif_get_or_fatal is demoted by a report catcher and counted.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_util_macros.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

// Interface for the virtual interface macros.
interface hexk_ut_util_if;
   logic [7:0] data;
endinterface : hexk_ut_util_if

module hexk_util_macros_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   localparam int unsigned NUM_STREAMS = 3;
   localparam int unsigned NUM_RANGES  = 4;

   // Singleton with a counter that shows which object answers.
   class hexk_ut_registry;
      int unsigned entries;

      `hexk_singleton_decl(hexk_ut_registry)
   endclass : hexk_ut_registry

   `hexk_analysis_imp_indexed_decl(stream)

   // Component with one imp per stream; it notes which index delivered which value.
   class hexk_ut_collector extends uvm_component;
      hexk_analysis_imp_indexed_stream #(.T(int), .IMP(hexk_ut_collector)) stream_imps[NUM_STREAMS];
      string                                                               received;
      virtual hexk_ut_util_if                                              vif;

      function new(string component_name, uvm_component parent);
         super.new(component_name, parent);
         foreach (stream_imps[i]) begin
            stream_imps[i] = new($sformatf("stream_imp_%0d", i), this, i);
         end
      endfunction : new

      function void write_stream(int idx, int t);
         received = {received, $sformatf("%0d:%0d ", idx, t)};
      endfunction : write_stream

      // Fetches the virtual interface with the given name; vif is null in a new collector.
      function void fetch_vif(string vif_name);
         `hexk_vif_get_or_fatal(hexk_ut_util_if, vif_name, vif)
      endfunction : fetch_vif
   endclass : hexk_ut_collector

   // Address ranges that must not overlap.
   class hexk_ut_map;
      rand bit [7:0] lo[NUM_RANGES];
      rand bit [7:0] hi[NUM_RANGES];

      `hexk_constraint_no_overlap(lo, hi)
   endclass : hexk_ut_map

   string          name = "hexk_util_macros_ut";
   svunit_testcase svunit_ut;

   hexk_ut_util_if util_if ();

   hexk_report_catcher      catcher;
   hexk_ut_collector        collector;
   uvm_analysis_port #(int) ports     [NUM_STREAMS];
   int unsigned             created;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   // Every test gets a fresh collector; components cannot be deleted, so each has its own name.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_VIF_GET$", UVM_FATAL, "", 0, -1, UVM_INFO);
      hexk_ut_registry::reset_for_test();
      created++;
      collector = new($sformatf("ut_collector_%0d", created), null);
      foreach (ports[i]) begin
         ports[i] = new($sformatf("ut_port_%0d_%0d", created, i), null);
         ports[i].connect(collector.stream_imps[i]);
         ports[i].resolve_bindings();
      end
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      hexk_ut_registry::reset_for_test();
      catcher.clear();
   endtask : teardown

   // Adds to the counter of the singleton and returns the counter.
   function automatic string count_entry();
      hexk_ut_registry registry = hexk_ut_registry::get();
      registry.entries++;
      return $sformatf("%0d", registry.entries);
   endfunction : count_entry

   // "same" when two calls of get() return one object.
   function automatic string get_twice();
      hexk_ut_registry first = hexk_ut_registry::get();
      hexk_ut_registry second = hexk_ut_registry::get();
      return (first == second) ? "same" : "different";
   endfunction : get_twice

   // Sends a value through the port of a stream.
   function automatic void send(int unsigned stream, int value);
      ports[stream].write(value);
   endfunction : send

   // Puts the interface of this module into uvm_config_db for the current collector.
   function automatic void publish_vif(string vif_name);
      `hexk_vif_set(hexk_ut_util_if, collector.get_full_name(), vif_name, util_if)
   endfunction : publish_vif

   // "found" when the collector got the interface of this module, "null" when it got none.
   function automatic string fetch(string vif_name);
      collector.fetch_vif(vif_name);
      if (collector.vif == null) begin
         return "null";
      end
      return (collector.vif == util_if) ? "found" : "other";
   endfunction : fetch

   // Number of HEXK_VIF_GET fatals in this test.
   function automatic string vif_fatals();
      return $sformatf("%0d", catcher.get_count("^HEXK_VIF_GET$", UVM_FATAL));
   endfunction : vif_fatals

   // Randomizes the address map a number of times; "ok" when every solution has ordered ranges that do not overlap.
   function automatic string check_maps(int unsigned rounds);
      hexk_ut_map map = new();
      repeat (rounds) begin
         if (map.randomize() != 1) begin
            return "randomize failed";
         end
         foreach (map.lo[i]) begin
            if (map.lo[i] > map.hi[i]) begin
               return $sformatf("range %0d is not in order", i);
            end
            foreach (map.lo[k]) begin
               if (k > i && map.lo[i] <= map.hi[k] && map.lo[k] <= map.hi[i]) begin
                  return $sformatf("ranges %0d and %0d overlap", i, k);
               end
            end
         end
      end
      return "ok";
   endfunction : check_maps

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(a_singleton_is_one_object)
      `FAIL_UNLESS_STR_EQUAL(get_twice(), "same")
      `FAIL_UNLESS_STR_EQUAL(count_entry(), "1")
      `FAIL_UNLESS_STR_EQUAL(count_entry(), "2")
   `SVTEST_END

   `SVTEST(reset_for_test_makes_get_create_a_new_object)
      `FAIL_UNLESS_STR_EQUAL(count_entry(), "1")
      hexk_ut_registry::reset_for_test();
      `FAIL_UNLESS_STR_EQUAL(count_entry(), "1")
   `SVTEST_END

   `SVTEST(an_indexed_imp_passes_its_index_with_the_item)
      send(2, 70);
      send(0, 50);
      send(2, 71);
      send(1, 60);
      `FAIL_UNLESS_STR_EQUAL(collector.received, "2:70 0:50 2:71 1:60 ")
   `SVTEST_END

   `SVTEST(an_indexed_imp_has_the_type_name_of_its_class)
      `FAIL_UNLESS_STR_EQUAL(collector.stream_imps[0].get_type_name(), "hexk_analysis_imp_indexed_stream")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", collector.stream_imps[2].index), "2")
   `SVTEST_END

   `SVTEST(a_virtual_interface_that_was_set_is_found)
      publish_vif("util_vif");
      `FAIL_UNLESS_STR_EQUAL(fetch("util_vif"), "found")
      `FAIL_UNLESS_STR_EQUAL(vif_fatals(), "0")
   `SVTEST_END

   `SVTEST(a_virtual_interface_that_was_not_set_is_fatal)
      publish_vif("util_vif");
      `FAIL_UNLESS_STR_EQUAL(fetch("other_vif"), "null")
      `FAIL_UNLESS_STR_EQUAL(vif_fatals(), "1")
   `SVTEST_END

   `SVTEST(ranges_under_the_no_overlap_constraint_never_overlap)
      `FAIL_UNLESS_STR_EQUAL(check_maps(50), "ok")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_util_macros_unit_test
