// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_base_test.sv
//
// Base test of the reference testbench, on hexk_base_test. A test here configures and decides;
// the work is done by the virtual sequences and the environment. The base test creates its cfg in
// the hook create_cfg(), so that a factory override of a derived test reaches it; defines the knobs
// of the testbench; configures the scoreboards; resets the DUT; and in the main phase starts the
// virtual sequence that create_traffic() returns, by default ref_packets random packets
// (hexk_ref_random_vseq), then has the environment compare ERR with the predictor. At the end
// every packet and every word that the sequences sent must have been matched. A warning that the
// test did not allow is an error (fail_on_warnings of hexk_base_test, set in the constructor; a
// test allows one with allow_warning()). A test of its own overrides create_traffic(), sets itself
// up in configure_test() (the randomized cfg, the expectations of the catcher, exclusions), and
// states how it must end (expected_matches(), expected_commits(), check_phase()).
//
// Knobs: ref_packets (number of packets), ref_mode (plain, scramble or mixed), ref_irq (wait for the
// interrupt or poll).

`ifndef HEXK_REF_BASE_TEST_SV
`define HEXK_REF_BASE_TEST_SV

class hexk_ref_base_test extends hexk_base_test;

   // The longest a test may take (2 ms), and the longest it may go without a packet (100 us).
   localparam longint unsigned GLOBAL_TIMEOUT_PS = 2_000_000_000;
   localparam longint unsigned INACTIVITY_LIMIT_PS = 100_000_000;

   // The cfg of the environment, created in create_cfg() and randomized in build_phase, and the environment.
   hexk_ref_env_cfg env_cfg;
   hexk_ref_env     env;

   // The mode of the packets and whether the sequences wait for the interrupt, from the knobs.
   hexk_ref_mode_e  mode;
   bit              use_irq;

   `uvm_component_utils(hexk_ref_base_test)

   // Creates the test, which fails on a warning that it did not allow; the cfg comes in create_cfg().
   function new(string name, uvm_component parent);
      super.new(name, parent);
      fail_on_warnings = 1;
   endfunction : new

   // Hook of hexk_base_test: the knobs of the testbench.
   virtual function void define_knobs();
      knobs.add_int("ref_packets", 10, "packets a test sends", 1, 200);
      hexk_enum_knob#(hexk_ref_mode_e)::add("ref_mode", HEXK_REF_MIXED, "packets plain, scrambled or mixed");
      knobs.add_bit("ref_irq", 1, "wait for the interrupt; 0 polls IRQ.DONE");
   endfunction : define_knobs

   // Hook of hexk_base_test: the cfg, through the factory, after the overrides of a derived test.
   virtual function void create_cfg();
      env_cfg = hexk_ref_env_cfg::type_id::create("env_cfg", this);
   endfunction : create_cfg

   // UVM callback: the interfaces, the cfg with the knobs, the environment.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `hexk_vif_get_or_fatal(hexk_clk_rst_if, "clk_rst_vif", env_cfg.clk_rst_cfg.vif)
      `hexk_vif_get_or_fatal(hexk_valid_ready_if#(32), "in_vif", env_cfg.in_cfg.vif)
      `hexk_vif_get_or_fatal(hexk_ref_bus_if, "bus_vif", env_cfg.bus_cfg.vif)
      `hexk_vif_get_or_fatal(hexk_pins_if#(hexk_ref_env_cfg::NUM_STRAPS), "strap_vif", env_cfg.strap_vif)
      `hexk_randomize_or_fatal(env_cfg, "REF_RAND")
      env_cfg.num_packets = 32'(knobs.get_int("ref_packets"));
      mode                = hexk_enum_knob#(hexk_ref_mode_e)::get("ref_mode");
      use_irq             = knobs.get_bit("ref_irq");
      configure_scoreboards();
      configure_test();
      watchdog.global_timeout_ps = GLOBAL_TIMEOUT_PS;
      env                        = hexk_ref_env::type_id::create("env", this);
      env.cfg                    = env_cfg;
      env.aggregator             = objections;
      env.watchdog               = watchdog;
   endfunction : build_phase

   // Hook: what a test sets up before the environment is built: members of the cfg after its randomization and the
   // knobs (a randomization would overwrite them before), the expectations of the catcher, exclusions of registers.
   virtual function void configure_test();
   endfunction : configure_test

   // The scoreboards. Results: keyed by packet number, waiting at most 50 us. Commits: in order; the actual
   // and the expected commit of an edge arrive at that edge in an order the simulator chooses, so an actual one
   // may come first and wait (allow_unexpected), but at most 1 ns, less than any clock period here: a commit
   // that waits longer came at another edge.
   virtual function void configure_scoreboards();
      env_cfg.result_sb_cfg.mode             = HEXK_SB_IN_ORDER_PER_KEY;
      env_cfg.result_sb_cfg.max_wait_ps      = 50_000_000;
      env_cfg.result_sb_cfg.flush_on_reset   = 1;
      env_cfg.commit_sb_cfg.mode             = HEXK_SB_IN_ORDER;
      env_cfg.commit_sb_cfg.allow_unexpected = 1;
      env_cfg.commit_sb_cfg.max_wait_ps      = 1_000;
      env_cfg.commit_sb_cfg.flush_on_reset   = 1;
   endfunction : configure_scoreboards

   // UVM callback: puts the straps to 0 through pulls and resets the DUT.
   task reset_phase(uvm_phase phase);
      hexk_clk_rst_reset_seq reset_seq = hexk_clk_rst_reset_seq::type_id::create("reset_seq");
      super.reset_phase(phase);
      phase.raise_objection(this, "reset");
      env_cfg.strap_vif.pull_down();
      `hexk_randomize_or_fatal(reset_seq, "REF_RAND")
      reset_seq.start(env.clk_rst_agent.sqr);
      phase.drop_objection(this, "reset done");
   endtask : reset_phase

   // UVM callback: starts the traffic of the test, then checks ERR; the watchdog counts from here.
   task main_phase(uvm_phase phase);
      hexk_ref_vseq_base traffic;
      super.main_phase(phase);
      phase.raise_objection(this, "traffic");
      watchdog.set_inactivity_limit(INACTIVITY_LIMIT_PS);
      traffic = create_traffic();
      prepare(traffic);
      `hexk_randomize_or_fatal(traffic, "REF_RAND")
      traffic.start(null);
      env.check_error_counters();
      phase.drop_objection(this, "traffic done");
   endtask : main_phase

   // Hook: the virtual sequence that is the traffic of the test; by default ref_packets random packets.
   virtual function hexk_ref_vseq_base create_traffic();
      hexk_ref_random_vseq traffic_seq = hexk_ref_random_vseq::type_id::create("traffic_seq");
      traffic_seq.num_packets = env_cfg.num_packets;
      return traffic_seq;
   endfunction : create_traffic

   // Gives a virtual sequence what it needs from this test: the environment, the way to wait for DONE, the mode.
   function void prepare(hexk_ref_vseq_base seq);
      seq.env     = env;
      seq.use_irq = use_irq;
      seq.mode    = mode;
   endfunction : prepare

   // Hook: the number of packet results that must match; every packet sent, unless a test makes them fail.
   virtual function int unsigned expected_matches();
      return env.packets_sent;
   endfunction : expected_matches

   // Hook: the number of commits that must match; every word sent, unless a test drops words on purpose.
   virtual function int unsigned expected_commits();
      return env.words_sent;
   endfunction : expected_commits

   // UVM callback: every packet and every word that was sent must have been matched.
   function void check_phase(uvm_phase phase);
      hexk_sb_stats results = env.result_sb.get_stats();
      hexk_sb_stats commits = env.commit_sb.get_stats();
      super.check_phase(phase);
      `hexk_check_eq(results.matched, expected_matches(), "REF_MATCHED", "packet results matched")
      `hexk_check_eq(commits.matched, expected_commits(), "REF_COMMITTED", "commits matched")
   endfunction : check_phase

endclass : hexk_ref_base_test

`endif  // HEXK_REF_BASE_TEST_SV
