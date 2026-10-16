// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_scoreboard_predictor_example.sv
//
// A scoreboard behind a predictor: the two sides of the DUT have different item types, the
// time and the ID of each request travel in a hexk_meta_item, and a reset comes in the middle
// of the traffic. The DUT model answers each request (a tag and an operand) with a response
// (the tag and the operand plus one), out of order and after a random time. A predictor turns
// every request into the response it expects. The scoreboard pairs the responses by tag, its
// key, counts the latency from the time of the request through get_timestamp_ps(), and names
// an item by the ID of its request through get_uid(). At the reset the DUT forgets the
// requests it holds and the test empties the scoreboard with on_reset(), so nothing is left
// over; the summary counts those expected items as dropped.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_scoreboard_predictor_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_meta_item;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   import hexk_uvm_pkg::HEXK_SB_OUT_OF_ORDER;
   `include "uvm_macros.svh"

   localparam int unsigned NUM_REQUESTS = 12;
   localparam int unsigned RESET_AFTER  = 6;

   // What goes into the DUT.
   class hexk_example_request extends uvm_sequence_item;
      int unsigned tag;
      int unsigned operand;

      `uvm_object_utils(hexk_example_request)

      function new(string name = "hexk_example_request");
         super.new(name);
      endfunction : new

      function void set(int unsigned request_tag, int unsigned request_operand);
         tag     = request_tag;
         operand = request_operand;
      endfunction : set

      function string convert2string();
         return $sformatf("tag=%0d operand=%0d", tag, operand);
      endfunction : convert2string
   endclass : hexk_example_request

   // What comes out of it: another type.
   class hexk_example_response extends uvm_sequence_item;
      int unsigned tag;
      int unsigned result;

      `uvm_object_utils(hexk_example_response)

      function new(string name = "hexk_example_response");
         super.new(name);
      endfunction : new

      function void set(int unsigned response_tag, int unsigned response_result);
         tag    = response_tag;
         result = response_result;
      endfunction : set

      function string convert2string();
         return $sformatf("tag=%0d result=%0d", tag, result);
      endfunction : convert2string

      function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_example_response other;
         bit                   same;
         if (!$cast(other, rhs)) begin
            return 0;
         end
         // Through the comparer, so that a mismatch names the fields that differ. compare_field_int() takes 64-bit
         // values; both fields are compared.
         same = comparer.compare_field_int("tag", 64'(tag), 64'(other.tag), $bits(tag));
         same &= comparer.compare_field_int("result", 64'(result), 64'(other.result), $bits(result));
         return same;
      endfunction : do_compare
   endclass : hexk_example_response

   typedef hexk_meta_item#(hexk_example_request) hexk_example_meta_request_t;
   typedef hexk_meta_item#(hexk_example_response) hexk_example_meta_response_t;

   // Turns each request into the response it expects, with the time and the ID of the request.
   class hexk_example_predictor extends uvm_subscriber #(hexk_example_meta_request_t);
      uvm_analysis_port #(hexk_example_meta_response_t) expected_ap;

      `uvm_component_utils(hexk_example_predictor)

      function new(string name, uvm_component parent);
         super.new(name, parent);
         expected_ap = new("expected_ap", this);
      endfunction : new

      function void write(hexk_example_meta_request_t t);
         hexk_example_response        expected = hexk_example_response::type_id::create("expected");
         hexk_example_meta_response_t meta;
         expected.set(t.item.tag, t.item.operand + 1);
         meta              = hexk_example_meta_response_t::wrap(expected, get_full_name(), t.uid);
         meta.timestamp_ps = t.timestamp_ps;
         expected_ap.write(meta);
      endfunction : write
   endclass : hexk_example_predictor

   // Pairs the responses by tag, counts the latency from the request and names an item by its ID.
   class hexk_example_scoreboard extends hexk_scoreboard #(
       .T  (hexk_example_meta_response_t),
       .KEY(int unsigned)
   );
      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function int unsigned get_key(hexk_example_meta_response_t item);
         return item.item.tag;
      endfunction : get_key

      virtual function longint unsigned get_timestamp_ps(hexk_example_meta_response_t item);
         return item.timestamp_ps;
      endfunction : get_timestamp_ps

      virtual function hexk_uid get_uid(hexk_example_meta_response_t item);
         return item.uid;
      endfunction : get_uid
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_example_predictor                            predictor;
      hexk_example_scoreboard                           scoreboard;
      // Stand for the monitors at the input and at the output of the DUT.
      uvm_analysis_port #(hexk_example_meta_request_t)  request_ap;
      uvm_analysis_port #(hexk_example_meta_response_t) response_ap;
      // The requests that the DUT model holds.
      hexk_example_request                              in_flight   [$];

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
         request_ap  = new("request_ap", this);
         response_ap = new("response_ap", this);
      endfunction : new

      function void build_phase(uvm_phase phase);
         hexk_scoreboard_cfg cfg = hexk_scoreboard_cfg::type_id::create("cfg");
         super.build_phase(phase);
         cfg.mode           = HEXK_SB_OUT_OF_ORDER;
         // This test waits for the responses itself; a testbench registers the scoreboard with an aggregator.
         cfg.hold_objection = 0;
         predictor          = hexk_example_predictor::type_id::create("predictor", this);
         scoreboard         = hexk_example_scoreboard::type_id::create("scoreboard", this);
         scoreboard.cfg     = cfg;
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         request_ap.connect(predictor.analysis_export);
         predictor.expected_ap.connect(scoreboard.expected_export);
         response_ap.connect(scoreboard.actual_export);
      endfunction : connect_phase

      // The DUT model: answers one of the requests it holds, chosen at random, after 5 to 40 ns.
      task run_dut();
         hexk_example_response response;
         int unsigned          index;
         int unsigned          delay_ns;
         forever begin
            wait (in_flight.size() != 0);
            delay_ns = $urandom_range(5, 40);
            #(delay_ns * 1ns);
            // A reset during the wait has taken the requests away.
            if (in_flight.size() == 0) begin
               continue;
            end
            index    = $urandom_range(0, in_flight.size() - 1);
            response = hexk_example_response::type_id::create("response");
            response.set(in_flight[index].tag, in_flight[index].operand + 1);
            response_ap.write(hexk_example_meta_response_t::wrap(response, "dut"));
            in_flight.delete(index);
         end
      endtask : run_dut

      task run_phase(uvm_phase phase);
         hexk_uid_pool        uids = hexk_uid_pool::get();
         hexk_example_request request;
         super.run_phase(phase);
         phase.raise_objection(this, "traffic");
         fork
            run_dut();
         join_none
         for (int unsigned i = 0; i < NUM_REQUESTS; i++) begin
            if (i == RESET_AFTER) begin
               `uvm_info("EXAMPLE", $sformatf("reset with %0d requests in the DUT", in_flight.size()), UVM_NONE)
               in_flight.delete();
               scoreboard.on_reset();
            end
            request = hexk_example_request::type_id::create("request");
            request.set(i, $urandom_range(0, 1000));
            in_flight.push_back(request);
            request_ap.write(hexk_example_meta_request_t::wrap(request, "requests", uids.new_uid("req")));
            #10ns;
         end
         // The DUT model takes a request away after it has written the response.
         wait (in_flight.size() == 0);
         phase.drop_objection(this, "all responses are in");
      endtask : run_phase

      function void report_phase(uvm_phase phase);
         hexk_sb_stats stats = scoreboard.get_stats();
         super.report_phase(phase);
         `uvm_info("EXAMPLE", $sformatf(
                   "%0d responses matched, %0d expected ones dropped at the reset, %s %0d ps",
                   stats.matched,
                   stats.dropped,
                   "mean latency",
                   stats.latency_avg_ps()
                   ), UVM_NONE)
      endfunction : report_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_scoreboard_predictor_example
