// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_scoreboard_example.sv
//
// Minimal use of hexk_scoreboard: a DUT answers requests out of order, so the scoreboard
// matches by the tag of the response. The class derived from the scoreboard says what the
// key of an item is and how an item is printed; everything else is the cfg. The test writes
// four expected responses, then the actual ones in another order with some delay; the
// scoreboard keeps the run phase alive until the last response has arrived, or reports one
// that is overdue. check_phase prints the summary, and the test checks that four pairs
// matched. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_scoreboard_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::HEXK_SB_OUT_OF_ORDER;
   `include "uvm_macros.svh"

   class hexk_example_response extends uvm_sequence_item;
      local int unsigned tag;
      local int unsigned data;

      `uvm_object_utils(hexk_example_response)

      function new(string name = "hexk_example_response");
         super.new(name);
      endfunction : new

      function void set(int unsigned response_tag, int unsigned response_data);
         tag  = response_tag;
         data = response_data;
      endfunction : set

      function int unsigned get_tag();
         return tag;
      endfunction : get_tag

      function string convert2string();
         return $sformatf("tag=%0d data=0x%0h", tag, data);
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
         same &= comparer.compare_field_int("data", 64'(data), 64'(other.data), $bits(data));
         return same;
      endfunction : do_compare
   endclass : hexk_example_response

   // Scoreboard for responses: the key is the tag. An item is printed on one line by the default item_text(), which
   // calls convert2string() of the item.
   class hexk_example_scoreboard extends hexk_scoreboard #(
       .T  (hexk_example_response),
       .KEY(int unsigned)
   );
      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function int unsigned get_key(hexk_example_response item);
         return item.get_tag();
      endfunction : get_key
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator                  objections;
      hexk_scoreboard_cfg                        scoreboard_cfg;
      hexk_example_scoreboard                    scoreboard;
      uvm_analysis_port #(hexk_example_response) predictor_port;
      uvm_analysis_port #(hexk_example_response) monitor_port;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections                  = hexk_objection_aggregator::type_id::create("objections", this);
         objections.poll_interval_ps = `hexk_ps(10ns);
         scoreboard_cfg              = hexk_scoreboard_cfg::type_id::create("scoreboard_cfg");
         scoreboard_cfg.mode         = HEXK_SB_OUT_OF_ORDER;
         // A response that never comes is an error after 1 us, instead of a run phase that never ends.
         scoreboard_cfg.max_wait_ps  = `hexk_ps(1us);
         scoreboard                  = hexk_example_scoreboard::type_id::create("scoreboard", this);
         scoreboard.cfg              = scoreboard_cfg;
         scoreboard.aggregator       = objections;
         predictor_port              = new("predictor_port", this);
         monitor_port                = new("monitor_port", this);
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         predictor_port.connect(scoreboard.expected_export);
         monitor_port.connect(scoreboard.actual_export);
      endfunction : connect_phase

      // A response with the given tag; the data follows from the tag.
      function hexk_example_response response(int unsigned tag);
         hexk_example_response item = hexk_example_response::type_id::create("item");
         item.set(tag, 32'hC0DE_0000 + tag);
         return item;
      endfunction : response

      task run_phase(uvm_phase phase);
         int unsigned answer_order[4] = '{2, 0, 3, 1};
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         for (int unsigned tag = 0; tag < 4; tag++) begin
            predictor_port.write(response(tag));
         end
         phase.drop_objection(this, "stimulus");
         // The DUT answers later and in its own order; the scoreboard holds the phase until then.
         foreach (answer_order[i]) begin
            #20ns;
            monitor_port.write(response(answer_order[i]));
         end
      endtask : run_phase

      // An empty scoreboard reports nothing either: the test checks that its four responses were compared.
      function void check_phase(uvm_phase phase);
         hexk_sb_stats stats = scoreboard.get_stats();
         super.check_phase(phase);
         `hexk_check_eq(stats.matched, 4, "EXAMPLE_MATCHED")
      endfunction : check_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_scoreboard_example
