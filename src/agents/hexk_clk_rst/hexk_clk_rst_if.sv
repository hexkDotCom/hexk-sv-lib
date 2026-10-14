// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_if.sv
//
// Interface of the clock and reset agent: generates one clock and holds one reset pin.
// Instantiate one per clock in the testbench top, connect clk and rst to the DUT and give
// the interface to a hexk_clk_rst_agent through its cfg. The agent sets the clock and
// drives the reset by calling the tasks and functions below; testbench code may call
// get_clk_count() and wait_clks() and use the clocking block mon_cb as "the clock edge".
// In passive mode the interface generates nothing: the testbench assigns the clock and the
// reset of the DUT to ext_clk and ext_rst, and clk and rst follow them.
// All times are whole picoseconds; the interface has its own time unit, so they mean the
// same whatever the time unit of the testbench is.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    IFC-2 IFC-8
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_IF_SV
`define HEXK_CLK_RST_IF_SV

interface hexk_clk_rst_if;
   timeunit 1ns; timeprecision 1ps;

   import hexk_core_pkg::hexk_rand_stream;

   // The clock and the reset pin: connect both to the DUT.
   logic            clk;
   logic            rst;

   // Passive mode: the testbench assigns the clock and the reset of the DUT to these two.
   // A lint rule reports a signal that nothing in the design drives, as in every testbench with an active agent.
   // verilator lint_off UNDRIVEN
   logic            ext_clk;
   logic            ext_rst;
   // verilator lint_on UNDRIVEN

   // 1 in passive mode, and 1 when the reset pin is active low; set by configure().
   bit              passive;
   bit              rst_active_low = 1'b1;

   // Whether the clock is asked to run, and whether the generator is in a cycle.
   bit              run_request;
   bit              running;

   // Time from the first start to the first low time of the clock.
   longint unsigned start_delay_ps;

   // The clock that was asked for: taken over at the next rising edge.
   longint unsigned next_period_ps = 10_000;
   longint unsigned next_high_ps = 5_000;
   longint unsigned next_jitter_ps;

   // The clock of the cycle that is going on.
   longint unsigned period_ps = 10_000;
   longint unsigned high_ps = 5_000;
   longint unsigned jitter_ps;

   // Distance of the next and of the latest rising edge from their ideal times.
   longint          edge_jitter_ps;
   longint          previous_jitter_ps;

   // The low time before the next rising edge, with the jitter of both edges.
   longint          low_wait_ps;

   // Number of rising edges of clk.
   longint unsigned clk_count;

   hexk_rand_stream jitter_stream = new("hexk_clk_rst_if");

   // The reset sampled at the rising edge of the clock; @(mon_cb) is "the next clock edge" for testbench code.
   clocking mon_cb @(posedge clk);
      input rst;
   endclocking : mon_cb

   // The generator: one pass of the outer loop per start of the clock, one of the inner loop per cycle.
   // It reads its settings at fixed points of a cycle and waits for nothing but run_request and time.
   initial begin : clock_generator
      clk = 1'b0;
      forever begin
         wait (run_request);
         running = 1'b1;
         #(start_delay_ps * 1ps);
         start_delay_ps     = 0;
         previous_jitter_ps = 0;
         period_ps          = next_period_ps;
         high_ps            = next_high_ps;
         jitter_ps          = next_jitter_ps;
         forever begin
            // The low time of the cycle that is ending; the jitter moves the edge, not the ideal time of the next.
            edge_jitter_ps = 0;
            if (jitter_ps != 0) begin
               edge_jitter_ps = jitter_stream.uniform(-longint'(jitter_ps), longint'(jitter_ps));
            end
            low_wait_ps = longint'(period_ps - high_ps) + edge_jitter_ps - previous_jitter_ps;
            #(low_wait_ps * 1ps);
            if (!run_request) begin
               break;
            end
            // A new clock holds from this rising edge and counts its ideal edges from it: the jitter of the old
            // clock must not shorten the first low time of the new one, which could then be below 0.
            if (next_period_ps != period_ps || next_high_ps != high_ps || next_jitter_ps != jitter_ps) begin
               previous_jitter_ps = 0;
            end else begin
               previous_jitter_ps = edge_jitter_ps;
            end
            period_ps = next_period_ps;
            high_ps   = next_high_ps;
            jitter_ps = next_jitter_ps;
            clk       = 1'b1;
            #(high_ps * 1ps);
            clk = 1'b0;
            if (!run_request) begin
               break;
            end
         end
         running = 1'b0;
      end
   end : clock_generator

   // The count changes in the same region as the clock, like a variable of a testbench: wait_clks() waits for
   // this change, and code after it must run where code after @(posedge clk) runs. A lint rule wants a
   // nonblocking assignment in a clocked block.
   // verilator lint_off BLKSEQ
   always @(posedge clk) begin : clock_counter
      clk_count++;
   end : clock_counter
   // verilator lint_on BLKSEQ

   // Passive mode: clk and rst follow the inputs.
   always @(ext_clk) begin : passive_clock
      if (passive) begin
         clk = ext_clk;
      end
   end : passive_clock

   always @(ext_rst) begin : passive_reset
      if (passive) begin
         rst = ext_rst;
      end
   end : passive_reset

   // Sets the mode, the active level of the reset and the seed of the jitter; the agent calls it once, at time 0.
   function automatic void configure(bit is_passive, bit active_low, int unsigned seed);
      passive        = is_passive;
      rst_active_low = active_low;
      jitter_stream.seed(seed);
      if (is_passive) begin
         clk = ext_clk;
         rst = ext_rst;
      end
   endfunction : configure

   // Asks for a clock with this period, high time and jitter; it holds from the next rising edge.
   function automatic void set_clock(longint unsigned period, longint unsigned high, longint unsigned jitter);
      next_period_ps = period;
      next_high_ps   = high;
      next_jitter_ps = jitter;
   endfunction : set_clock

   // Sets the time by which the first start of the clock is delayed.
   function automatic void set_start_delay(longint unsigned delay);
      start_delay_ps = delay;
   endfunction : set_start_delay

   // Starts the clock (1) or stops it after the high time that is going on (0).
   function automatic void request_run(bit run);
      run_request = run;
   endfunction : request_run

   // 1 when the clock is asked to run.
   function automatic bit is_running();
      return run_request;
   endfunction : is_running

   // Waits until the generator has stopped; the clock is 0 then.
   task automatic wait_stopped();
      wait (!running);
   endtask : wait_stopped

   // The value of the pin for an asserted (1) or a released (0) reset.
   function automatic logic pin_value(bit active);
      return active != rst_active_low;
   endfunction : pin_value

   // Asserts (1) or releases (0) the reset at once.
   function automatic void drive_reset(bit active);
      rst = pin_value(active);
   endfunction : drive_reset

   // Asserts or releases the reset in the time step of a rising edge, after the edge: the DUT sees it at the next
   // edge. With wait_for_edge it waits for the next rising edge first; without, the caller is at an edge.
   task automatic drive_reset_at_edge(bit active, bit wait_for_edge);
      if (wait_for_edge) begin
         @(clk_count);
      end
      rst <= pin_value(active);
   endtask : drive_reset_at_edge

   // 1 when the pin has a level; active then says whether the reset is asserted.
   function automatic bit get_reset(output bit active);
      active = (rst === pin_value(1'b1));
      return !$isunknown(rst);
   endfunction : get_reset

   // Waits for a change of the reset pin.
   task automatic wait_reset_change();
      @(rst);
   endtask : wait_reset_change

   // Waits for a time in picoseconds.
   task automatic wait_ps(longint unsigned duration);
      #(duration * 1ps);
   endtask : wait_ps

   // Number of rising edges of clk since the start of the simulation.
   function automatic longint unsigned get_clk_count();
      return clk_count;
   endfunction : get_clk_count

   // Waits for n rising edges of clk; returns at once when n is 0.
   task automatic wait_clks(int unsigned n);
      repeat (n) begin
         @(clk_count);
      end
   endtask : wait_clks

endinterface : hexk_clk_rst_if

`endif  // HEXK_CLK_RST_IF_SV
