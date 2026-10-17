// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_unit_test.sv
//
// SVUnit tests of the clock and reset agent with its interface.
// The UVM phases do not run in a unit test simulation, so each test builds a fresh agent on
// the interface of this module, runs its build and connect phases by hand, and starts
// run_phase of the driver and the monitor in threads that teardown ends. The interface
// lives through all tests: teardown stops its clock, and every test measures times and
// clock counts from the moment its agent started. Two always blocks note when the reset
// pin was asserted and released and at how many rising edges it was asserted, as a DUT
// would see it. Sequences are started on the sequencer of the agent, as a test would.
// The tests of the passive mode need a second interface. Verilator 5.046 simulates one
// instance of an interface correctly and mixes up several, so the second instance and
// those tests are compiled for the other simulators only.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_clk_rst.

`include "svunit_defines.svh"

module hexk_clk_rst_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_clk_countable;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent_cfg;
   import hexk_clk_rst_pkg::hexk_clk_rst_item;
   import hexk_clk_rst_pkg::hexk_clk_rst_status;
   import hexk_clk_rst_pkg::hexk_clk_rst_reset_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_clock_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_stop_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_assert_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_release_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_start_seq;
   import hexk_clk_rst_pkg::HEXK_CLK_RST_RESET;
   import hexk_clk_rst_pkg::HEXK_CLK_RST_CLOCK;
   import hexk_clk_rst_pkg::HEXK_CLK_RST_STOP;
   import hexk_clk_rst_pkg::HEXK_CLK_RST_START;
   `include "uvm_macros.svh"

   // Jitter of the test with jitter, and the number of rising edges it looks at.
   localparam longint JITTER_PS = 400;
   localparam int unsigned JITTER_EDGES = 16;

   string          name = "hexk_clk_rst_ut";
   svunit_testcase svunit_ut;

   hexk_clk_rst_if clk_if ();
`ifndef VERILATOR
   hexk_clk_rst_if passive_if ();
   logic dut_clk = 1'b0;
   logic dut_rst_n = 1'b1;
   assign passive_if.ext_clk = dut_clk;
   assign passive_if.ext_rst = dut_rst_n;
`endif

   hexk_report_catcher                        catcher;
   hexk_clk_rst_agent_cfg                     cfg;
   hexk_clk_rst_agent                         agent;
   uvm_tlm_analysis_fifo #(hexk_clk_rst_item) seen;
   process                                    driver_process;
   process                                    monitor_process;
   int unsigned                               created;
   string                                     result;

   // The moment the agent of the test started, and the clock count then.
   realtime                                   start_time;
   longint unsigned                           start_count;

   // What a DUT sees of the reset: when the pin was last asserted and released, in picoseconds since the
   // start, and at how many rising edges it was asserted.
   bit                                        pin_active_low = 1'b1;
   longint                                    asserted_ps = -1;
   longint                                    released_ps = -1;
   int unsigned                               active_edges;

   always @(clk_if.rst) begin
      if (clk_if.rst === !pin_active_low) begin
         asserted_ps = since_start();
      end else if (clk_if.rst === pin_active_low) begin
         released_ps = since_start();
      end
   end

   always @(posedge clk_if.clk) begin
      if (clk_if.rst === !pin_active_low) begin
         active_edges++;
      end
   end

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   // Every test gets a fresh cfg on the interface of this module; the test starts the agent after it set the cfg.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_CLK_RST_ILLEGAL$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_CLK_RST_STOPPED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_CLK_RST_CFG$", UVM_FATAL, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_CLK_RST_PERIOD$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_CLK_RST_UNKNOWN$", UVM_ERROR, "", 0, -1, UVM_INFO);
      cfg            = hexk_clk_rst_agent_cfg::type_id::create("cfg");
      cfg.vif        = clk_if;
      agent          = null;
      pin_active_low = 1'b1;
      result         = "";
   endtask : setup

   // Ends the threads of the agent and leaves the interface with a stopped clock and a pin at 1, so that the
   // reset of the start of the next test is a change of the pin.
   task automatic teardown();
      svunit_ut.teardown();
      if (driver_process != null) begin
         driver_process.kill();
         driver_process = null;
      end
      if (monitor_process != null) begin
         monitor_process.kill();
         monitor_process = null;
      end
      // Killing the monitor does not end its thread that checks the clock on Verilator 5.046; this ends it.
      if (agent != null && agent.cfg != null) begin
         agent.cfg.check_period = 0;
      end
      clk_if.request_run(1'b0);
      clk_if.wait_stopped();
      clk_if.rst = 1'b1;
      catcher.clear();
   endtask : teardown

   // Picoseconds since the agent of the test started.
   function automatic longint since_start();
      return longint'(($realtime - start_time) / 1ps);
   endfunction : since_start

   // Rising edges of the clock since the agent of the test started.
   function automatic string edges_since_start();
      return $sformatf("%0d", clk_if.get_clk_count() - start_count);
   endfunction : edges_since_start

   // Sets the clock of the cfg.
   function automatic void set_clock(longint unsigned period_ps, int unsigned duty_percent = 50,
                                     longint unsigned jitter_ps = 0, longint unsigned phase_ps = 0);
      cfg.period_ps    = period_ps;
      cfg.duty_percent = duty_percent;
      cfg.jitter_ps    = jitter_ps;
      cfg.phase_ps     = phase_ps;
   endfunction : set_clock

   // Sets one of the flags of the cfg.
   function automatic void set_flag(string which, bit value);
      case (which)
         "rst_active_low": begin
            cfg.rst_active_low = value;
            pin_active_low     = value;
         end
         "start_clock":  cfg.start_clock = value;
         "check_period": cfg.check_period = value;
         default:        cfg.reset_at_start = value;
      endcase
   endfunction : set_flag

   // Builds an agent with the cfg of the test and runs its phases up to the start of simulation.
   function automatic void build_agent(hexk_clk_rst_agent_cfg agent_cfg);
      created++;
      agent     = hexk_clk_rst_agent::type_id::create($sformatf("ut_clk_rst_agent_%0d", created), null);
      agent.cfg = agent_cfg;
      agent.build_phase(null);
      if (agent.mon == null) begin
         return;
      end
      agent.mon.connect_phase(null);
      if (agent.drv != null) begin
         agent.drv.connect_phase(null);
      end
      agent.connect_phase(null);
      if (agent.drv != null) begin
         agent.drv.seq_item_port.resolve_bindings();
      end
      seen = new($sformatf("ut_clk_rst_seen_%0d", created), null);
      agent.ap.connect(seen.analysis_export);
      // The port of the agent is that of the monitor: resolved after the test connected to it.
      agent.mon.ap.resolve_bindings();
      agent.start_of_simulation_phase(null);
   endfunction : build_agent

   // Starts an active agent with the cfg of the test: the moment from which the test measures.
   task automatic start_agent();
      asserted_ps  = -1;
      released_ps  = -1;
      active_edges = 0;
      start_time   = $realtime;
      start_count  = clk_if.get_clk_count();
      build_agent(cfg);
      fork
         begin
            monitor_process = process::self();
            agent.mon.run_phase(null);
         end
         begin
            driver_process = process::self();
            agent.drv.run_phase(null);
         end
      join_none
      wait (monitor_process != null && driver_process != null);
   endtask : start_agent

   // Waits until the given number of picoseconds has passed since the start.
   task automatic advance_to(longint target_ps);
      longint now_ps = since_start();
      if (target_ps > now_ps) begin
         clk_if.wait_ps(target_ps - now_ps);
      end
   endtask : advance_to

   // The times of the next count rising edges of the clock, in picoseconds since the start.
   task automatic measure_edges(int unsigned count);
      result = "";
      repeat (count) begin
         @(posedge clk_if.clk);
         result = {result, $sformatf("%0d ", since_start())};
      end
   endtask : measure_edges

   // The next high and the next low time of the clock in picoseconds, as "<high> <low>".
   task automatic measure_high_low();
      longint rose_ps;
      longint fell_ps;
      @(posedge clk_if.clk);
      rose_ps = since_start();
      @(negedge clk_if.clk);
      fell_ps = since_start();
      @(posedge clk_if.clk);
      result = $sformatf("%0d %0d", fell_ps - rose_ps, since_start() - fell_ps);
   endtask : measure_high_low

   // The shortest and the longest high time and the shortest and the longest low time of the next count cycles, in
   // picoseconds: "<shortest high> <longest high> <shortest low> <longest low>". It is called at a rising edge,
   // the first one of the cycles it measures.
   task automatic measure_extreme_high_low(int unsigned count);
      longint rose_ps;
      longint fell_ps;
      longint shortest_high = -1;
      longint shortest_low = -1;
      longint longest_high = -1;
      longint longest_low = -1;
      repeat (count) begin
         rose_ps = since_start();
         @(negedge clk_if.clk);
         fell_ps = since_start();
         if (shortest_high < 0 || fell_ps - rose_ps < shortest_high) begin
            shortest_high = fell_ps - rose_ps;
         end
         longest_high = (fell_ps - rose_ps > longest_high) ? fell_ps - rose_ps : longest_high;
         @(posedge clk_if.clk);
         if (shortest_low < 0 || since_start() - fell_ps < shortest_low) begin
            shortest_low = since_start() - fell_ps;
         end
         longest_low = (since_start() - fell_ps > longest_low) ? since_start() - fell_ps : longest_low;
      end
      result = $sformatf("%0d %0d %0d %0d", shortest_high, longest_high, shortest_low, longest_low);
   endtask : measure_extreme_high_low

   // Looks at JITTER_EDGES rising edges of a clock of 10 ns with jitter: "<all near their ideal time> <one moved>".
   task automatic measure_jitter();
      longint ideal_ps = 5000;
      longint offset_ps;
      bit     all_near = 1;
      bit     one_moved = 0;
      repeat (JITTER_EDGES) begin
         @(posedge clk_if.clk);
         offset_ps = since_start() - ideal_ps;
         if (offset_ps < -JITTER_PS || offset_ps > JITTER_PS) begin
            all_near = 0;
         end
         if (offset_ps != 0) begin
            one_moved = 1;
         end
         ideal_ps += 10_000;
      end
      result = $sformatf("%0b %0b", all_near, one_moved);
   endtask : measure_jitter

   // Runs a reset sequence: "<asserted at> <released at> <rising edges with the reset asserted> <done at>".
   // The members are assigned after a plain randomize(): one tool cannot override a soft constraint in the call.
   task automatic run_reset(int unsigned cycles, longint unsigned extra_ps = 0, bit at_edge = 0,
                            bit release_at_edge = 1);
      hexk_clk_rst_reset_seq seq = hexk_clk_rst_reset_seq::type_id::create("seq");
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.hold_cycles  = cycles;
      seq.hold_ps      = extra_ps;
      seq.sync_assert  = at_edge;
      seq.sync_release = release_at_edge;
      seq.start(agent.sqr);
      // The always block that notes the release runs in the time step of the release.
      clk_if.wait_ps(1);
      result = $sformatf("%0d %0d %0d %0d", asserted_ps, released_ps, active_edges, since_start() - 1);
   endtask : run_reset

   // Runs a reset sequence with what a plain randomize() gives, or as created when randomize_first is 0.
   // SEQ-3 waived: with randomize_first 0 the test checks the defaults of a sequence started without randomize().
   task automatic run_default_reset(bit randomize_first = 1);
      hexk_clk_rst_reset_seq seq = hexk_clk_rst_reset_seq::type_id::create("seq");
      if (randomize_first && seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.start(agent.sqr);
      clk_if.wait_ps(1);
      result = $sformatf("%0d %0d %0d %0d", asserted_ps, released_ps, active_edges, since_start() - 1);
   endtask : run_default_reset

   // The members of the sequences as created, without randomize():
   // "<reset: hold_cycles hold_ps sync_assert sync_release> | <clock: period duty jitter> | <stop: stop_ps>".
   function automatic string created_sequence_members();
      hexk_clk_rst_reset_seq reset_seq = hexk_clk_rst_reset_seq::type_id::create("reset_seq");
      hexk_clk_rst_clock_seq clock_seq = hexk_clk_rst_clock_seq::type_id::create("clock_seq");
      hexk_clk_rst_stop_seq  stop_seq = hexk_clk_rst_stop_seq::type_id::create("stop_seq");
      return $sformatf(
          "%0d %0d %0d %0d | %0d %0d %0d | %0d",
          reset_seq.hold_cycles,
          reset_seq.hold_ps,
          reset_seq.sync_assert,
          reset_seq.sync_release,
          clock_seq.period_ps,
          clock_seq.duty_percent,
          clock_seq.jitter_ps,
          stop_seq.stop_ps
      );
   endfunction : created_sequence_members

   // Runs a frequency sequence and returns when it is done: "<done at> <period of the status> <period of the cfg>".
   task automatic run_freq(longint unsigned period, int unsigned duty = 50, longint unsigned jitter = 0);
      hexk_clk_rst_clock_seq seq = hexk_clk_rst_clock_seq::type_id::create("seq");
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.period_ps    = period;
      seq.duty_percent = duty;
      seq.jitter_ps    = jitter;
      seq.start(agent.sqr);
      result = $sformatf("%0d %0d %0d", since_start(), agent.status.period_ps, cfg.period_ps);
   endtask : run_freq

   // Starts a clock sequence with a new period in the background; result is the period in the status 1 ns later.
   task automatic status_while_the_clock_changes(longint unsigned period);
      fork
         run_freq(period);
      join_none
      #1ns;
      result = $sformatf("%0d", agent.status.period_ps);
   endtask : status_while_the_clock_changes

   // The period in the status.
   function automatic string status_period();
      return $sformatf("%0d", agent.status.period_ps);
   endfunction : status_period

   // Runs a stop sequence: "<done at> <clock> <rising edges since the start>".
   task automatic run_stop(longint unsigned restart_after_ps = 0);
      hexk_clk_rst_stop_seq seq = hexk_clk_rst_stop_seq::type_id::create("seq");
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.stop_ps = restart_after_ps;
      seq.start(agent.sqr);
      result = $sformatf("%0d %0b %s", since_start(), clk_if.clk, edges_since_start());
   endtask : run_stop

   // Runs an assert sequence, the reset at the next rising edge or at once.
   task automatic run_assert(bit at_edge);
      hexk_clk_rst_assert_seq seq = hexk_clk_rst_assert_seq::type_id::create("seq");
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.sync_assert = at_edge;
      seq.start(agent.sqr);
   endtask : run_assert

   // Runs an assert (1) or a release (0) sequence at the next rising edge: the pin as soon as start() returned.
   task automatic pin_when_done(bit assert_it);
      hexk_clk_rst_release_seq seq = hexk_clk_rst_release_seq::type_id::create("seq");
      if (assert_it) begin
         run_assert(1);
      end else begin
         if (seq.randomize() != 1) begin
            result = "randomization failed";
            return;
         end
         seq.sync_release = 1;
         seq.start(agent.sqr);
      end
      result = $sformatf("%b", clk_if.rst);
   endtask : pin_when_done

   // Runs a release sequence, at the next rising edge or at once:
   // "<asserted at> <released at> <rising edges with the reset asserted> <done at>".
   task automatic run_release(bit at_edge);
      hexk_clk_rst_release_seq seq = hexk_clk_rst_release_seq::type_id::create("seq");
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.sync_release = at_edge;
      seq.start(agent.sqr);
      // The always block that notes the release runs in the time step of the release.
      clk_if.wait_ps(1);
      result = $sformatf("%0d %0d %0d %0d", asserted_ps, released_ps, active_edges, since_start() - 1);
   endtask : run_release

   // Runs a start sequence: "<done at> <rising edges since the start>".
   task automatic run_start();
      hexk_clk_rst_start_seq seq = hexk_clk_rst_start_seq::type_id::create("seq");
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.start(agent.sqr);
      result = $sformatf("%0d %s", since_start(), edges_since_start());
   endtask : run_start

   // Errors and fatals of the agent in this test, as "<illegal> <stopped> <cfg>".
   function automatic string problems();
      return $sformatf(
          "%0d %0d %0d",
          catcher.get_count(
              "^HEXK_CLK_RST_ILLEGAL$"
          ),
          catcher.get_count(
              "^HEXK_CLK_RST_STOPPED$"
          ),
          catcher.get_count(
              "^HEXK_CLK_RST_CFG$", UVM_FATAL
          )
      );
   endfunction : problems

   // The items the monitor wrote so far, each as "A" or "R" for asserted or released and the clock count since
   // the start; "-" when there is none.
   function automatic string seen_items();
      hexk_clk_rst_item item;
      string            text;
      while (seen.try_get(
          item
      )) begin
         text = {text, $sformatf("%s%0d ", item.reset_active ? "A" : "R", item.clk_count - start_count)};
      end
      return (text.len() == 0) ? "-" : text;
   endfunction : seen_items

   // The check of the clock by the monitor: "<intervals checked> <errors of the check>".
   function automatic string period_checks();
      return $sformatf("%0d %0d", agent.mon.num_checked(), catcher.get_count("^HEXK_CLK_RST_PERIOD$"));
   endfunction : period_checks

   // Whether the two events of the status of the agent were triggered, what the item of the release says, and
   // whether the status says that the reset is asserted:
   // "<asserted> <released> <reset_active of the item of the release> <in_reset>".
   function automatic string events();
      hexk_clk_rst_status status = agent.status;
      hexk_clk_rst_item   item;
      string              data = "none";
      if ($cast(item, status.reset_released.get_trigger_data()) && item != null) begin
         data = $sformatf("%0b", item.reset_active);
      end
      return $sformatf(
          "%0b %0b %s %0b", status.reset_asserted.is_on(), status.reset_released.is_on(), data, status.in_reset
      );
   endfunction : events

   // The status and the port of an agent that was only constructed, and the port once it is built:
   // "<status> | <port after construction> | <full name of ap> <it is the port of the monitor>", with the name of
   // the agent written as "agent".
   function automatic string parts_of_an_agent();
      hexk_clk_rst_agent constructed;
      created++;
      constructed = hexk_clk_rst_agent::type_id::create($sformatf("ut_clk_rst_agent_%0d", created), null);
      if (constructed.status == null) begin
         return "no status";
      end
      build_agent(cfg);
      if (agent.ap == null) begin
         return "no port";
      end
      return $sformatf(
          "%s | %s | %s %0b",
          constructed.status.convert2string(),
          (constructed.ap == null) ? "none" : "some",
          hexk_str::replace(
              agent.ap.get_full_name(), agent.get_name(), "agent"
          ),
          agent.ap == agent.mon.ap
      );
   endfunction : parts_of_an_agent

   // Builds an agent without a cfg, or with a cfg without an interface: "<fatals> <monitor created>".
   function automatic string build_without(string what);
      hexk_clk_rst_agent_cfg broken = (what == "cfg") ? null : hexk_clk_rst_agent_cfg::type_id::create("broken");
      build_agent(broken);
      return $sformatf("%0d %0d", catcher.get_count("^HEXK_CLK_RST_CFG$", UVM_FATAL), agent.mon != null);
   endfunction : build_without

   // Builds an agent whose cfg is in uvm_config_db, and with assign_too a cfg assigned as well: "<fatals> <the
   // agent has the cfg of uvm_config_db> <the agent has the assigned cfg>".
   function automatic string build_from_config_db(bit assign_too);
      hexk_clk_rst_agent_cfg from_db = hexk_clk_rst_agent_cfg::type_id::create("from_db");
      from_db.vif = clk_if;
      // The agent that build_agent() creates next.
      uvm_config_db#(hexk_clk_rst_agent_cfg)::set(null, $sformatf("ut_clk_rst_agent_%0d", created + 1), "cfg", from_db);
      build_agent(assign_too ? cfg : null);
      return $sformatf(
          "%0d %0d %0d", catcher.get_count("^HEXK_CLK_RST_CFG$", UVM_FATAL), agent.cfg == from_db, agent.cfg == cfg
      );
   endfunction : build_from_config_db

   // Waits for clock cycles through the agent as a hexk_clk_countable: "<cycles counted> <time it took>".
   task automatic count_through_the_agent(int unsigned cycles);
      hexk_clk_countable counter = agent;
      longint unsigned   first_count = counter.get_clk_count();
      longint            began_ps = since_start();
      counter.wait_clks(cycles);
      result = $sformatf("%0d %0d", counter.get_clk_count() - first_count, since_start() - began_ps);
   endtask : count_through_the_agent

   // Values of a cfg: what set_freq_mhz makes of a frequency, and why a clock is not legal.
   function automatic string freq_of(real freq_mhz);
      cfg.set_freq_mhz(freq_mhz);
      return $sformatf("%0d %0.3f", cfg.period_ps, cfg.get_freq_mhz());
   endfunction : freq_of

   function automatic string reason_of(longint unsigned period_ps, int unsigned duty_percent,
                                       longint unsigned jitter_ps);
      set_clock(period_ps, duty_percent, jitter_ps);
      return cfg.illegal_reason();
   endfunction : reason_of

`ifndef VERILATOR
   // Whether a clock is legal for the constraints of the cfg and for illegal_reason(): "<constraints> <reason>".
   // The constraint of the call overrides the soft defaults of the cfg, which Verilator 5.046 does not do.
   function automatic string legality(longint unsigned period, int unsigned duty, longint unsigned jitter);
      hexk_clk_rst_agent_cfg probe = hexk_clk_rst_agent_cfg::type_id::create("probe");
      string                 reason = hexk_clk_rst_agent_cfg::clock_illegal_reason(period, duty, jitter);
      int                    solved;
      solved = probe.randomize() with {
         period_ps == local:: period;
         duty_percent == local:: duty;
         jitter_ps == local:: jitter;
      };
      return {(solved == 1) ? "legal" : "illegal", " ", (reason.len() == 0) ? "legal" : "illegal"};
   endfunction : legality

   // The first of a set of clocks around the rounding of the high time for which the constraints of the cfg and
   // illegal_reason() disagree, as "<period> <duty> <jitter>: <constraints> <reason>"; "" when they always agree.
   function automatic string first_legality_difference();
      longint unsigned periods [$] = '{2, 3, 4, 7, 10, 50, 101};
      int unsigned     duties  [$] = '{1, 49, 50, 99};
      longint unsigned jitters [$] = '{0, 1, 2};
      string           verdict;
      foreach (periods[i]) begin
         foreach (duties[k]) begin
            foreach (jitters[m]) begin
               verdict = legality(periods[i], duties[k], jitters[m]);
               if (verdict != "legal legal" && verdict != "illegal illegal") begin
                  return $sformatf("%0d %0d %0d: %s", periods[i], duties[k], jitters[m], verdict);
               end
            end
         end
      end
      return "";
   endfunction : first_legality_difference
`endif

   // The clock of a cfg after a plain randomize(), and whether a clone shares the interface.
   function automatic string randomized_cfg();
      hexk_clk_rst_agent_cfg copy;
      if (cfg.randomize() != 1) begin
         return "randomization failed";
      end
      if (!$cast(copy, cfg.clone())) begin
         return "clone failed";
      end
      return $sformatf(
          "%0d %0d %0d %0d %0b", cfg.period_ps, cfg.duty_percent, cfg.jitter_ps, cfg.phase_ps, copy.vif == cfg.vif
      );
   endfunction : randomized_cfg

   // An item of each kind as text, and whether a copy compares equal before and after a change.
   function automatic string item_texts();
      hexk_clk_rst_item item = hexk_clk_rst_item::type_id::create("item");
      hexk_clk_rst_item copy;
      string            texts                                             [$];
      bit               equal_before;
      item.op           = HEXK_CLK_RST_RESET;
      item.hold_cycles  = 5;
      item.sync_release = 1;
      texts.push_back(item.convert2string());
      item.op           = HEXK_CLK_RST_CLOCK;
      item.period_ps    = 2500;
      item.duty_percent = 40;
      texts.push_back(item.convert2string());
      item.op      = HEXK_CLK_RST_STOP;
      item.hold_ps = 700;
      texts.push_back(item.convert2string());
      item.op = HEXK_CLK_RST_START;
      texts.push_back(item.convert2string());
      item.op = HEXK_CLK_RST_CLOCK;
      void'($cast(copy, item.clone()));
      equal_before   = item.compare(copy);
      copy.period_ps = 2501;
      texts.push_back($sformatf("%0b %0b", equal_before, item.compare(copy)));
      return hexk_core_pkg::hexk_str::join_str(texts, " | ");
   endfunction : item_texts

   // What a comparer like that of hexk_scoreboard noted when expected.compare(actual) found a difference; the lines
   // are joined with " | ".
   function automatic string miscompares(uvm_object expected, uvm_object actual);
      uvm_comparer comparer = new();
      comparer.show_max  = 0;
      comparer.verbosity = UVM_DEBUG;
      void'(expected.compare(actual, comparer));
      return hexk_core_pkg::hexk_str::replace(hexk_core_pkg::hexk_str::strip(comparer.miscompares), "\n", " | ");
   endfunction : miscompares

   // The type name of an object and its fields as the line printer shows them, from the opening brace on; the
   // instance number before it differs from run to run.
   function automatic string printed_fields(uvm_object object);
      uvm_line_printer printer = new();
      string           text = object.sprint(printer);
      int              brace = hexk_core_pkg::hexk_str::find(text, "{");
      return {object.get_type_name(), " ", hexk_core_pkg::hexk_str::strip(text.substr(brace, text.len() - 1))};
   endfunction : printed_fields

   // A reset item as the printer shows it, then the texts of a new item into which a packed copy of it was
   // unpacked, as a reset and as a clock: the members that a reset does not use are packed as well.
   function automatic string printed_and_unpacked();
      hexk_clk_rst_item item = hexk_clk_rst_item::type_id::create("item");
      hexk_clk_rst_item unpacked = hexk_clk_rst_item::type_id::create("unpacked");
      bit               bits                                                      [];
      string            texts                                                     [$ ];
      item.op           = HEXK_CLK_RST_RESET;
      item.hold_cycles  = 5;
      item.hold_ps      = 70;
      item.sync_assert  = 1;
      item.sync_release = 1;
      item.reset_active = 1;
      item.clk_count    = 64'd123456789012;
      item.period_ps    = 2500;
      item.duty_percent = 40;
      item.jitter_ps    = 9;
      texts.push_back(printed_fields(item));
      void'(item.pack(bits));
      void'(unpacked.unpack(bits));
      texts.push_back(unpacked.convert2string());
      unpacked.op = HEXK_CLK_RST_CLOCK;
      texts.push_back(unpacked.convert2string());
      return hexk_core_pkg::hexk_str::join_str(texts, " | ");
   endfunction : printed_and_unpacked

   // The differences of two clock items with another period and duty cycle, then of the same items when the
   // operation of the actual item differs.
   function automatic string item_differences();
      hexk_clk_rst_item expected = hexk_clk_rst_item::type_id::create("expected");
      hexk_clk_rst_item actual = hexk_clk_rst_item::type_id::create("actual");
      string            texts                                                     [$];
      expected.op           = HEXK_CLK_RST_CLOCK;
      expected.period_ps    = 2500;
      expected.duty_percent = 40;
      actual.op             = HEXK_CLK_RST_CLOCK;
      actual.period_ps      = 2501;
      actual.duty_percent   = 50;
      texts.push_back(miscompares(expected, actual));
      actual.op = HEXK_CLK_RST_STOP;
      texts.push_back(miscompares(expected, actual));
      return hexk_core_pkg::hexk_str::join_str(texts, " / ");
   endfunction : item_differences

`ifndef VERILATOR
   // Runs a reset sequence whose default of 5 cycles a constraint of the call overrides, as a test does.
   task automatic run_constrained_reset(int unsigned cycles);
      hexk_clk_rst_reset_seq seq = hexk_clk_rst_reset_seq::type_id::create("seq");
      if (seq.randomize() with {hold_cycles == local:: cycles;} != 1) begin
         result = "randomization failed";
         return;
      end
      seq.start(agent.sqr);
      clk_if.wait_ps(1);
      result = $sformatf("%0d %0d %0d %0d", asserted_ps, released_ps, active_edges, since_start() - 1);
   endtask : run_constrained_reset

   hexk_clk_rst_agent_cfg passive_cfg;

   // Starts a passive agent on the second interface, whose clock and reset the testbench drives.
   task automatic start_passive_agent();
      passive_cfg           = hexk_clk_rst_agent_cfg::type_id::create("passive_cfg");
      passive_cfg.vif       = passive_if;
      passive_cfg.is_active = UVM_PASSIVE;
      start_time            = $realtime;
      start_count           = passive_if.get_clk_count();
      build_agent(passive_cfg);
      fork
         begin
            monitor_process = process::self();
            agent.mon.run_phase(null);
         end
      join_none
      wait (monitor_process != null);
   endtask : start_passive_agent

   // Drives the clock and the reset of a DUT that the passive agent watches: four clock cycles of 14 ns,
   // with the reset asserted during the second and the third.
   task automatic run_dut_clock();
      repeat (4) begin
         #7ns;
         dut_clk = 1'b1;
         #2ns;
         dut_rst_n = (passive_if.get_clk_count() - start_count == 2 || passive_if.get_clk_count() - start_count == 3) ?
             1'b0 : 1'b1;
         #5ns;
         dut_clk = 1'b0;
      end
      result = $sformatf("%0d %0d %0d", passive_if.get_clk_count() - start_count, agent.drv == null, agent.sqr == null);
   endtask : run_dut_clock

   // Takes the reset of the DUT from released to X, asserted, X and released again: "<errors> <items>" with the
   // number of HEXK_CLK_RST_UNKNOWN errors and the reset items the passive agent published.
   task automatic run_reset_without_level();
      int unsigned items_before = seen.used();
      #10ns;
      dut_rst_n = 1'bx;
      #10ns;
      dut_rst_n = 1'b0;
      #10ns;
      dut_rst_n = 1'bz;
      #10ns;
      dut_rst_n = 1'b1;
      #10ns;
      result = $sformatf("%0d %0d", catcher.get_count("^HEXK_CLK_RST_UNKNOWN$"), seen.used() - items_before);
   endtask : run_reset_without_level
`endif

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(the_clock_starts_with_a_low_time_and_has_the_period_of_the_cfg)
      start_agent();
      measure_edges(3);
      `FAIL_UNLESS_STR_EQUAL(result, "5000 15000 25000 ")
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0")
   `SVTEST_END

   `SVTEST(the_duty_cycle_sets_the_high_time)
      set_clock(10_000, 30);
      start_agent();
      measure_high_low();
      `FAIL_UNLESS_STR_EQUAL(result, "3000 7000")
   `SVTEST_END

   `SVTEST(the_phase_delays_the_first_start)
      set_clock(8000, 50, 0, 3000);
      start_agent();
      measure_edges(2);
      `FAIL_UNLESS_STR_EQUAL(result, "7000 15000 ")
   `SVTEST_END

   `SVTEST(without_start_clock_the_clock_waits_for_a_start_sequence)
      set_flag("start_clock", 0);
      start_agent();
      advance_to(30_000);
      `FAIL_UNLESS_STR_EQUAL(edges_since_start(), "0")
      run_start();
      `FAIL_UNLESS_STR_EQUAL(result, "35000 1")
   `SVTEST_END

   `SVTEST(the_status_tells_a_new_clock_from_the_rising_edge_from_which_it_holds)
      start_agent();
      advance_to(6_000);
      status_while_the_clock_changes(20_000);
      `FAIL_UNLESS_STR_EQUAL(result, "10000")
      advance_to(40_000);
      `FAIL_UNLESS_STR_EQUAL(status_period(), "20000")
   `SVTEST_END

   `SVTEST(a_start_of_a_running_clock_does_nothing)
      start_agent();
      advance_to(17_000);
      run_start();
      `FAIL_UNLESS_STR_EQUAL(result, "17000 2")
   `SVTEST_END

   `SVTEST(a_stop_lets_the_high_time_end_and_leaves_the_clock_at_0)
      start_agent();
      advance_to(17_000);
      run_stop();
      `FAIL_UNLESS_STR_EQUAL(result, "20000 0 2")
      advance_to(60_000);
      `FAIL_UNLESS_STR_EQUAL(edges_since_start(), "2")
   `SVTEST_END

   `SVTEST(a_stop_in_the_low_time_stops_before_the_next_rising_edge)
      start_agent();
      advance_to(22_000);
      run_stop();
      `FAIL_UNLESS_STR_EQUAL(result, "25000 0 2")
   `SVTEST_END

   `SVTEST(a_start_after_a_stop_begins_with_a_low_time)
      start_agent();
      advance_to(17_000);
      run_stop();
      advance_to(30_000);
      run_start();
      `FAIL_UNLESS_STR_EQUAL(result, "35000 3")
      measure_edges(1);
      `FAIL_UNLESS_STR_EQUAL(result, "45000 ")
   `SVTEST_END

   `SVTEST(a_warm_reset_holds_the_reset_while_the_clock_is_stopped_and_started)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_assert(0);
      run_stop();
      advance_to(30_000);
      run_start();
      run_release(1);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 45000 2 45000")
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0")
   `SVTEST_END

   `SVTEST(an_assert_at_an_edge_of_a_stopped_clock_is_an_error_and_asserts_at_once)
      set_flag("reset_at_start", 0);
      set_flag("start_clock", 0);
      start_agent();
      advance_to(7_000);
      run_assert(1);
      advance_to(8_000);
      run_release(0);
      `FAIL_UNLESS_STR_EQUAL(result, "7000 8000 0 8000")
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 1 0")
   `SVTEST_END

   `SVTEST(a_reset_at_an_edge_has_changed_the_pin_when_its_sequence_returns)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      pin_when_done(1);
      `FAIL_UNLESS_STR_EQUAL(result, "0")
      pin_when_done(0);
      `FAIL_UNLESS_STR_EQUAL(result, "1")
   `SVTEST_END

   `SVTEST(a_stop_with_a_time_starts_the_clock_again)
      start_agent();
      advance_to(17_000);
      run_stop(8000);
      `FAIL_UNLESS_STR_EQUAL(result, "33000 1 3")
   `SVTEST_END

   `SVTEST(a_stop_of_a_stopped_clock_does_nothing_and_with_a_time_starts_it_after_that_time)
      start_agent();
      advance_to(17_000);
      run_stop();
      advance_to(30_000);
      run_stop();
      `FAIL_UNLESS_STR_EQUAL(result, "30000 0 2")
      run_stop(8000);
      `FAIL_UNLESS_STR_EQUAL(result, "43000 1 3")
   `SVTEST_END

   `SVTEST(a_new_period_holds_from_the_next_rising_edge)
      start_agent();
      advance_to(17_000);
      run_freq(4000);
      `FAIL_UNLESS_STR_EQUAL(result, "25000 4000 10000")
      measure_edges(2);
      `FAIL_UNLESS_STR_EQUAL(result, "29000 33000 ")
   `SVTEST_END

   `SVTEST(a_new_duty_cycle_comes_with_the_new_period)
      start_agent();
      advance_to(17_000);
      run_freq(20_000, 25);
      measure_high_low();
      `FAIL_UNLESS_STR_EQUAL(result, "5000 15000")
   `SVTEST_END

   `SVTEST(a_new_clock_for_a_stopped_clock_holds_from_its_start)
      set_flag("start_clock", 0);
      start_agent();
      run_freq(6000);
      `FAIL_UNLESS_STR_EQUAL(result, "0 6000 10000")
      run_start();
      `FAIL_UNLESS_STR_EQUAL(result, "3000 1")
   `SVTEST_END

   `SVTEST(an_illegal_clock_in_the_cfg_is_an_error_and_gives_the_default_clock)
      set_clock(10_000, 0);
      start_agent();
      measure_edges(2);
      `FAIL_UNLESS_STR_EQUAL(result, "5000 15000 ")
      `FAIL_UNLESS_STR_EQUAL(problems(), "1 0 0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d %0d", agent.status.duty_percent, cfg.duty_percent), "50 0")
   `SVTEST_END

   `SVTEST(an_illegal_clock_in_an_item_is_an_error_and_changes_nothing)
      start_agent();
      advance_to(17_000);
      run_freq(1);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 10000 10000")
      `FAIL_UNLESS_STR_EQUAL(problems(), "1 0 0")
      measure_edges(2);
      `FAIL_UNLESS_STR_EQUAL(result, "25000 35000 ")
   `SVTEST_END

   `SVTEST(a_fast_clock_after_a_jittered_slow_one_counts_from_its_first_edge)
      set_clock(10_000, 50, 1000);
      start_agent();
      advance_to(57_000);
      run_freq(10, 50, 0);
      measure_extreme_high_low(8);
      `FAIL_UNLESS_STR_EQUAL(result, "5 5 5 5")
   `SVTEST_END

   `SVTEST(jitter_moves_the_edges_and_does_not_add_up)
      set_clock(10_000, 50, JITTER_PS);
      start_agent();
      measure_jitter();
      `FAIL_UNLESS_STR_EQUAL(result, "1 1")
   `SVTEST_END

   `SVTEST(the_reset_is_asserted_from_the_start)
      start_agent();
      advance_to(17_000);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %0d %0d", clk_if.rst, asserted_ps, active_edges), "0 0 2")
   `SVTEST_END

   `SVTEST(without_reset_at_start_the_reset_is_released_from_the_start)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %0d", clk_if.rst, active_edges), "1 0")
   `SVTEST_END

   `SVTEST(a_reset_that_is_active_high_drives_the_pin_the_other_way)
      set_flag("rst_active_low", 0);
      start_agent();
      advance_to(17_000);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b", clk_if.rst), "1")
      run_reset(1);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b", clk_if.rst), "0")
   `SVTEST_END

   `SVTEST(the_default_reset_is_seen_at_exactly_five_rising_edges)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_default_reset();
      `FAIL_UNLESS_STR_EQUAL(result, "17000 65000 5 65000")
   `SVTEST_END

   `SVTEST(a_reset_sequence_started_without_randomize_uses_the_defaults)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_default_reset(0);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 65000 5 65000")
   `SVTEST_END

   `SVTEST(the_members_of_a_created_sequence_have_their_defaults)
      `FAIL_UNLESS_STR_EQUAL(created_sequence_members(), "5 0 0 1 | 10000 50 0 | 0")
   `SVTEST_END

   `SVTEST(a_reset_can_be_asserted_at_a_rising_edge)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_reset(2, 0, 1, 1);
      `FAIL_UNLESS_STR_EQUAL(result, "25000 45000 2 45000")
   `SVTEST_END

   `SVTEST(a_reset_at_an_edge_without_a_hold_leaves_the_reset_released)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_reset(0, 0, 1, 0);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %0d %0d", clk_if.rst, active_edges, since_start() - 1), "1 0 25000")
   `SVTEST_END

   `SVTEST(a_reset_at_an_edge_without_a_hold_leaves_an_active_high_reset_released)
      set_flag("reset_at_start", 0);
      set_flag("rst_active_low", 0);
      start_agent();
      advance_to(17_000);
      run_reset(0, 0, 1, 0);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %0d", clk_if.rst, since_start() - 1), "0 25000")
   `SVTEST_END

   `SVTEST(a_reset_can_be_held_for_a_time_and_released_between_edges)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_reset(0, 7000, 0, 0);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 24000 0 24000")
   `SVTEST_END

   `SVTEST(edges_and_a_time_add_up_and_a_release_at_an_edge_waits_for_the_next_one)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_reset(1, 2000, 0, 1);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 35000 2 35000")
   `SVTEST_END

   `SVTEST(edges_and_a_time_add_up_for_a_release_between_edges)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_reset(1, 2000, 0, 0);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 27000 1 27000")
   `SVTEST_END

   `SVTEST(a_reset_releases_the_reset_of_the_start)
      start_agent();
      advance_to(17_000);
      run_reset(1);
      `FAIL_UNLESS_STR_EQUAL(result, "0 25000 3 25000")
   `SVTEST_END

   `SVTEST(a_reset_that_needs_edges_of_a_stopped_clock_is_an_error_and_does_not_wait)
      set_flag("reset_at_start", 0);
      set_flag("start_clock", 0);
      start_agent();
      advance_to(17_000);
      run_reset(3, 2000, 1, 1);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 19000 0 19000")
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 1 0")
   `SVTEST_END

   `SVTEST(a_reset_by_time_works_with_a_stopped_clock)
      set_flag("reset_at_start", 0);
      set_flag("start_clock", 0);
      start_agent();
      run_reset(0, 4000, 0, 0);
      `FAIL_UNLESS_STR_EQUAL(result, "0 4000 0 4000")
      `FAIL_UNLESS_STR_EQUAL(problems(), "0 0 0")
   `SVTEST_END

   `SVTEST(the_monitor_reports_the_reset_of_the_start_and_its_release)
      start_agent();
      advance_to(17_000);
      `FAIL_UNLESS_STR_EQUAL(seen_items(), "A0 ")
      `FAIL_UNLESS_STR_EQUAL(events(), "1 0 none 1")
      run_reset(1);
      `FAIL_UNLESS_STR_EQUAL(seen_items(), "R3 ")
      `FAIL_UNLESS_STR_EQUAL(events(), "1 1 0 0")
   `SVTEST_END

   `SVTEST(the_monitor_reports_every_reset_once)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      `FAIL_UNLESS_STR_EQUAL(seen_items(), "-")
      run_reset(1);
      run_reset(0, 3000, 0, 0);
      `FAIL_UNLESS_STR_EQUAL(seen_items(), "A2 R3 A3 R3 ")
   `SVTEST_END

   `SVTEST(with_check_period_the_monitor_checks_every_interval_of_the_clock)
      set_flag("reset_at_start", 0);
      set_flag("check_period", 1);
      start_agent();
      // Rising edges at 5, 15, ..., 95 ns: nine intervals.
      advance_to(100_000);
      `FAIL_UNLESS_STR_EQUAL(period_checks(), "9 0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d %0d", agent.mon.num_checked_at(10_000), agent.mon.num_checked_at(20_000)),
                             "9 0")
   `SVTEST_END

   `SVTEST(the_check_of_the_period_allows_twice_the_jitter)
      set_flag("reset_at_start", 0);
      set_clock(10_000, 50, JITTER_PS);
      set_flag("check_period", 1);
      start_agent();
      // Twenty rising edges, each within the jitter of 5, 15, ..., 195 ns.
      advance_to(200_000);
      `FAIL_UNLESS_STR_EQUAL(period_checks(), "19 0")
   `SVTEST_END

   `SVTEST(the_check_of_the_period_skips_a_reset_a_new_clock_and_a_stop)
      set_flag("check_period", 1);
      start_agent();
      advance_to(17_000);
      `FAIL_UNLESS_STR_EQUAL(period_checks(), "0 0")
      run_reset(1);
      advance_to(60_000);
      run_freq(20_000);
      advance_to(150_000);
      run_stop();
      advance_to(180_000);
      run_start();
      advance_to(300_000);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d %0b %0b", catcher.get_count("^HEXK_CLK_RST_PERIOD$"),
                                       agent.mon.num_checked_at(10_000) > 0, agent.mon.num_checked_at(20_000) > 2),
                             "0 1 1")
   `SVTEST_END

   `SVTEST(a_clock_that_is_not_the_one_of_the_status_is_an_error)
      set_flag("reset_at_start", 0);
      set_flag("check_period", 1);
      start_agent();
      advance_to(50_000);
      // A clock changed behind the back of the agent: rising edges at 55, 67 and 79 ns.
      clk_if.set_clock(12_000, 6_000, 0);
      advance_to(80_000);
      `FAIL_UNLESS_STR_EQUAL(period_checks(), "7 2")
   `SVTEST_END

   `SVTEST(without_check_period_the_monitor_does_not_check_the_clock)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(50_000);
      clk_if.set_clock(12_000, 6_000, 0);
      advance_to(80_000);
      `FAIL_UNLESS_STR_EQUAL(period_checks(), "0 0")
   `SVTEST_END

   `SVTEST(the_agent_counts_and_waits_for_clock_cycles)
      start_agent();
      advance_to(17_000);
      count_through_the_agent(4);
      `FAIL_UNLESS_STR_EQUAL(result, "4 38000")
      count_through_the_agent(0);
      `FAIL_UNLESS_STR_EQUAL(result, "0 0")
   `SVTEST_END

   `SVTEST(the_status_belongs_to_the_agent_from_its_construction_and_the_port_is_that_of_the_monitor)
      `FAIL_UNLESS_STR_EQUAL(parts_of_an_agent(),
         "in_reset=0 period_ps=10000 duty_percent=50 jitter_ps=0 | none | agent.mon.ap 1")
   `SVTEST_END

   `SVTEST(an_agent_without_a_cfg_or_an_interface_is_a_fatal)
      `FAIL_UNLESS_STR_EQUAL(build_without("cfg"), "1 0")
      `FAIL_UNLESS_STR_EQUAL(build_without("vif"), "2 0")
   `SVTEST_END

   `SVTEST(an_agent_takes_an_assigned_cfg_first_and_else_that_of_the_config_db)
      `FAIL_UNLESS_STR_EQUAL(build_from_config_db(0), "0 1 0")
      `FAIL_UNLESS_STR_EQUAL(build_from_config_db(1), "0 0 1")
   `SVTEST_END

   `SVTEST(set_freq_mhz_rounds_to_whole_picoseconds)
      `FAIL_UNLESS_STR_EQUAL(freq_of(100.0), "10000 100.000")
      `FAIL_UNLESS_STR_EQUAL(freq_of(3000.0), "333 3003.003")
      `FAIL_UNLESS_STR_EQUAL(freq_of(0.032768), "30517578 0.033")
   `SVTEST_END

   `SVTEST(illegal_reason_says_what_is_wrong_with_a_clock)
      `FAIL_UNLESS_STR_EQUAL(reason_of(10_000, 50, 0), "")
      `FAIL_UNLESS_STR_EQUAL(reason_of(1, 50, 0), "period_ps (1) is not in 2 to 281474976710655")
      `FAIL_UNLESS_STR_EQUAL(reason_of(10_000, 100, 0), "duty_percent (100) is not in 1 to 99")
      `FAIL_UNLESS_STR_EQUAL(reason_of(10, 5, 0), "period_ps (10) with duty_percent (5) leaves no high or no low time")
      `FAIL_UNLESS_STR_EQUAL(reason_of(10_000, 30, 750), "")
      `FAIL_UNLESS_STR_EQUAL(reason_of(10_000, 30, 751),
         "jitter_ps (751) is above a quarter of the shorter of the high and the low time (3000)")
   `SVTEST_END

`ifndef VERILATOR
   `SVTEST(the_constraints_of_the_cfg_allow_the_clocks_that_illegal_reason_allows)
      // A period of 2 ps with 99 % high rounds to 1 ps high and 1 ps low, which the driver accepts.
      `FAIL_UNLESS_STR_EQUAL(legality(2, 99, 0), "legal legal")
      `FAIL_UNLESS_STR_EQUAL(legality(10, 5, 0), "illegal illegal")
      `FAIL_UNLESS_STR_EQUAL(legality(10_000, 30, 750), "legal legal")
      `FAIL_UNLESS_STR_EQUAL(legality(10_000, 30, 751), "illegal illegal")
      // 101 ps with 49 % high: 49 ps high, 52 ps low; a quarter of the shorter one is 12 ps.
      `FAIL_UNLESS_STR_EQUAL(legality(101, 49, 12), "legal legal")
      `FAIL_UNLESS_STR_EQUAL(legality(101, 49, 13), "illegal illegal")
      // 101 ps with 51 % high: 51 ps high, 50 ps low; a quarter of the low time is 12 ps.
      `FAIL_UNLESS_STR_EQUAL(legality(101, 51, 12), "legal legal")
      `FAIL_UNLESS_STR_EQUAL(legality(101, 51, 13), "illegal illegal")
      `FAIL_UNLESS_STR_EQUAL(first_legality_difference(), "")
   `SVTEST_END
`endif

   // Constrained randomization on Verilator needs an external SMT solver (z3) on the PATH.
   `SVTEST(a_plain_randomize_keeps_the_default_clock_and_a_clone_shares_the_interface)
      `FAIL_UNLESS_STR_EQUAL(randomized_cfg(), "10000 50 0 0 1")
   `SVTEST_END

   `SVTEST(convert2string_of_the_cfg_lists_the_settings)
      `FAIL_UNLESS_STR_EQUAL(cfg.convert2string(),
         {"UVM_ACTIVE period_ps=10000 duty_percent=50 jitter_ps=0 phase_ps=0 active_low=1 start_clock=1 ",
          "reset_at_start=1 check_period=0"})
   `SVTEST_END

   `SVTEST(an_item_prints_what_its_operation_uses_and_compares_it)
      `FAIL_UNLESS_STR_EQUAL(item_texts(),
         {"HEXK_CLK_RST_RESET hold_cycles=5 hold_ps=0 sync_assert=0 sync_release=1 reset_active=0 clk_count=0 | ",
          "HEXK_CLK_RST_CLOCK period_ps=2500 duty_percent=40 jitter_ps=0 | HEXK_CLK_RST_STOP hold_ps=700 | ",
          "HEXK_CLK_RST_START | 1 0"})
   `SVTEST_END

   `SVTEST(an_item_prints_what_its_operation_uses_and_unpacks_every_member_it_packed)
      `FAIL_UNLESS_STR_EQUAL(printed_and_unpacked(),
         {"hexk_clk_rst_item { op: HEXK_CLK_RST_RESET  hold_cycles: 'd5  hold_ps: 'd70  sync_assert: 'b1  ",
          "sync_release: 'b1  reset_active: 'b1  clk_count: 'd123456789012  } | HEXK_CLK_RST_RESET hold_cycles=5 ",
          "hold_ps=70 sync_assert=1 sync_release=1 reset_active=1 clk_count=123456789012 | HEXK_CLK_RST_CLOCK ",
          "period_ps=2500 duty_percent=40 jitter_ps=9"})
   `SVTEST_END

   `SVTEST(a_difference_of_two_items_names_the_fields_their_operation_uses)
      `FAIL_UNLESS_STR_EQUAL(item_differences(),
         {"expected.period_ps: lhs = 'h9c4 : rhs = 'h9c5 | expected.duty_percent: lhs = 'h28 : rhs = 'h32 / ",
          "expected.op: lhs = 'h1 : rhs = 'h2"})
   `SVTEST_END

   // A soft constraint cannot be overridden by a constraint of the call on Verilator 5.046.
`ifndef VERILATOR
   `SVTEST(a_constraint_of_the_test_overrides_a_default_of_a_sequence)
      set_flag("reset_at_start", 0);
      start_agent();
      advance_to(17_000);
      run_constrained_reset(2);
      `FAIL_UNLESS_STR_EQUAL(result, "17000 35000 2 35000")
   `SVTEST_END

   `SVTEST(a_passive_agent_counts_the_clock_and_reports_the_reset_of_the_dut)
      start_passive_agent();
      run_dut_clock();
      `FAIL_UNLESS_STR_EQUAL(result, "4 1 1")
      `FAIL_UNLESS_STR_EQUAL(seen_items(), "A2 R4 ")
   `SVTEST_END

   `SVTEST(a_reset_pin_without_a_level_after_a_level_is_an_error)
      start_passive_agent();
      run_reset_without_level();
      `FAIL_UNLESS_STR_EQUAL(result, "2 2")
   `SVTEST_END
`endif

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_clk_rst_unit_test
