// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_bench.sv
//
// Benchmarks of the paths of the library that run for every transaction or message. One
// simulation runs one case, chosen with +hexk_bench=<case>, +hexk_bench_count=<n> times; 'make
// bench' runs every case once with a count of 0 and once with its count, and the difference of
// the two wall-clock times divided by the count is the cost of one operation. Cases:
//   sb_in_order          an expected and an actual item through a scoreboard in order
//   sb_ooo_1, _16, _256  the same out of order, with 1, 16 or 256 items waiting under one key;
//                        the partner is always the newest, so the search compares with all of them
//   sb_ooo_256_partner   sb_ooo_256 with an is_partner() that compares one field instead of compare()
//   delay_uniform        one draw of a delay generator, uniform 0 to 10
//   delay_weighted       one draw of a delay generator with 8 weights
//   report               the text and the marker and stack trace decisions of one message of the
//                        report server, without the output of UVM; time advances by 1 ps before each
//                        message, so that the time column is new for every message
//   report_triggers      the same with 4 marker triggers and 4 stack trace triggers that do not match
//   report_uvm           the same with the layout of UVM (style HEXK_FMT_UVM), as a reference
//   time_step            only the step of 1 ps, to subtract from the three cases above
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_bench;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_delay;
   import hexk_uvm_pkg::hexk_delay_cfg;
   import hexk_uvm_pkg::hexk_report_cfg;
   import hexk_uvm_pkg::hexk_report_server;
   import hexk_uvm_pkg::HEXK_SB_IN_ORDER;
   import hexk_uvm_pkg::HEXK_SB_OUT_OF_ORDER;
   import hexk_uvm_pkg::HEXK_DELAY_UNIFORM;
   import hexk_uvm_pkg::HEXK_DELAY_WEIGHTED;
   import hexk_uvm_pkg::HEXK_FMT_UVM;
   `include "uvm_macros.svh"

   // An item with one compared field, as a scoreboard sees it.
   class hexk_bench_item extends uvm_sequence_item;
      int unsigned data;

      `uvm_object_utils(hexk_bench_item)

      function new(string name = "hexk_bench_item");
         super.new(name);
         data = 0;
      endfunction : new

      function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_bench_item other;
         return $cast(other, rhs) && other.data == data;
      endfunction : do_compare
   endclass : hexk_bench_item

   typedef hexk_scoreboard#(hexk_bench_item) hexk_bench_sb_t;

   // A scoreboard whose partner is the item with the same data, found without compare().
   class hexk_bench_partner_sb extends hexk_scoreboard #(hexk_bench_item);
      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function bit is_partner(hexk_bench_item exp, hexk_bench_item act);
         return exp.data == act.data;
      endfunction : is_partner
   endclass : hexk_bench_partner_sb

   // count pairs through a scoreboard; with waiting > 0 out of order, with that many items waiting under one key
   // when the actual item comes: waiting - 1 items that never get a partner, and the expected item of the pair.
   // With by_field the scoreboard finds the partner by one field.
   function automatic void run_scoreboard(int unsigned count, int unsigned waiting, bit by_field = 0);
      hexk_scoreboard_cfg   cfg = hexk_scoreboard_cfg::type_id::create("cfg");
      hexk_bench_partner_sb partner_sb;
      hexk_bench_sb_t       sb;
      hexk_bench_item       fresh = hexk_bench_item::type_id::create("fresh");
      hexk_bench_item       stale;
      if (by_field) begin
         partner_sb = new("bench_sb", null);
         sb         = partner_sb;
      end else begin
         sb = new("bench_sb", null);
      end
      cfg.mode           = (waiting == 0) ? HEXK_SB_IN_ORDER : HEXK_SB_OUT_OF_ORDER;
      cfg.hold_objection = 0;
      sb.cfg             = cfg;
      sb.build_phase(null);
      for (int unsigned i = 1; i < waiting; i++) begin
         stale      = hexk_bench_item::type_id::create("stale");
         stale.data = i;
         sb.write_expected_idx(0, stale);
      end
      for (int unsigned i = 0; i < count; i++) begin
         sb.write_expected_idx(0, fresh);
         sb.write_actual_idx(0, fresh);
      end
   endfunction : run_scoreboard

   // count draws of a delay generator.
   function automatic void run_delay(int unsigned count, bit weighted);
      hexk_delay_cfg cfg = hexk_delay_cfg::type_id::create("cfg");
      hexk_delay     delay;
      int unsigned   sum;
      if (weighted) begin
         cfg.mode = HEXK_DELAY_WEIGHTED;
         for (int unsigned value = 0; value < 8; value++) begin
            cfg.weights[value] = value + 1;
         end
      end else begin
         cfg.mode = HEXK_DELAY_UNIFORM;
         cfg.lo   = 0;
         cfg.hi   = 10;
      end
      delay = new(cfg, "bench_delay", 1);
      for (int unsigned i = 0; i < count; i++) begin
         sum += delay.next();
      end
      $display("HEXK_BENCH sum of the delays %0d", sum);
   endfunction : run_delay

   // count messages through the work of the report server, without the output of UVM, one per time step.
   task automatic run_report(int unsigned count, bit with_triggers, bit uvm_style = 0);
      hexk_report_cfg    cfg = hexk_report_cfg::type_id::create("cfg");
      hexk_report_server server;
      uvm_report_message message = uvm_report_message::new_report_message();
      uvm_root           top = uvm_root::get();
      int unsigned       length;
      int unsigned       marked;
      if (with_triggers) begin
         cfg.marker_triggers     = '{"alpha", "beta", "gamma", "delta"};
         cfg.stacktrace_triggers = '{"epsilon", "zeta", "eta", "theta"};
      end
      if (uvm_style) begin
         cfg.style = HEXK_FMT_UVM;
      end
      server = hexk_report_server::install(cfg);
      message.set_report_message(UVM_INFO, "HEXK_BENCH_MSG", "a message of the bench with a few words", UVM_LOW,
                                 "hexk_bench.sv", 100, "");
      message.set_report_object(top);
      message.set_report_handler(top.get_report_handler());
      message.set_report_server(server);
      for (int unsigned i = 0; i < count; i++) begin
         string text;
         #1ps;
         text = server.compose_report_message(message);
         length += text.len();
         marked += 32'(server.gets_marker(message)) + 32'(server.gets_stacktrace(message));
      end
      $display("HEXK_BENCH characters %0d, marked %0d", length, marked);
   endtask : run_report

   // count steps of 1 ps and nothing else.
   task automatic run_time_steps(int unsigned count);
      repeat (count) begin
         #1ps;
      end
   endtask : run_time_steps

   initial begin
      string       name;
      int unsigned count;
      name  = "";
      count = 0;
      void'($value$plusargs("hexk_bench=%s", name));
      void'($value$plusargs("hexk_bench_count=%d", count));
      case (name)
         "sb_in_order":        run_scoreboard(count, 0);
         "sb_ooo_1":           run_scoreboard(count, 1);
         "sb_ooo_16":          run_scoreboard(count, 16);
         "sb_ooo_256":         run_scoreboard(count, 256);
         "sb_ooo_256_partner": run_scoreboard(count, 256, 1);
         "delay_uniform":      run_delay(count, 0);
         "delay_weighted":     run_delay(count, 1);
         "report":             run_report(count, 0);
         "report_triggers":    run_report(count, 1);
         "report_uvm":         run_report(count, 0, 1);
         "time_step":          run_time_steps(count);
         default:              $display("HEXK_BENCH unknown case '%s'", name);
      endcase
      $display("HEXK_BENCH_DONE %s %0d", name, count);
      $finish;
   end

endmodule : hexk_bench
