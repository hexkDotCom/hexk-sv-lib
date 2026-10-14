// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_base_test.sv
//
// Base test of the smoke testbench: builds the environment on top of hexk_base_test, resets
// the DUT in the reset phase and sends num_items random words through the FIFO in the main
// phase. In the check phase it checks that the scoreboard matched as many words.
// A test changes the cfg in modify_cfg() and what happens before the traffic in prepare().
// The knob num_items (+num_items=<n>) sets the number of words.

`ifndef HEXK_SMOKE_BASE_TEST_SV
`define HEXK_SMOKE_BASE_TEST_SV

class hexk_smoke_base_test extends hexk_base_test;

   // The longest a test may take (500 us), and the longest it may go without a word leaving the FIFO (20 us),
   // in picoseconds.
   localparam longint unsigned GLOBAL_TIMEOUT_PS = 500_000_000;
   localparam longint unsigned INACTIVITY_LIMIT_PS = 20_000_000;

   // Clock cycles of the reset.
   localparam int unsigned RESET_CYCLES = 5;

   hexk_smoke_env_cfg env_cfg;
   hexk_smoke_env     env;

   `uvm_component_utils(hexk_smoke_base_test)

   // Creates the test and the cfg of its environment.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      env_cfg = hexk_smoke_env_cfg::type_id::create("env_cfg");
   endfunction : new

   // Hook of hexk_base_test: the knob for the number of words.
   virtual function void define_knobs();
      knobs.add_int("num_items", 20, "words to send through the FIFO", 1, 10000);
   endfunction : define_knobs

   // Hook: what a test does to the DUT before the traffic starts; nothing by default.
   virtual task prepare();
   endtask : prepare

   // UVM callback: fetches the interfaces, randomizes the cfg and builds the environment.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `hexk_vif_get_or_fatal(hexk_clk_rst_if, "clk_rst_vif", env_cfg.clk_rst_cfg.vif)
      `hexk_vif_get_or_fatal(hexk_valid_ready_if#(hexk_smoke_env_cfg::WIDTH), "in_vif", env_cfg.in_cfg.vif)
      `hexk_vif_get_or_fatal(hexk_valid_ready_if#(hexk_smoke_env_cfg::WIDTH), "out_vif", env_cfg.out_cfg.vif)
      `hexk_vif_get_or_fatal(hexk_pins_if#(hexk_smoke_env_cfg::NUM_CTRL_PINS), "ctrl_vif", env_cfg.ctrl_vif)
      `hexk_randomize_or_fatal(env_cfg, "HEXK_SMOKE_RAND")
      env_cfg.num_items          = 32'(knobs.get_int("num_items"));
      watchdog.global_timeout_ps = GLOBAL_TIMEOUT_PS;
      env                        = hexk_smoke_env::type_id::create("env", this);
      env.cfg                    = env_cfg;
      env.aggregator             = objections;
      env.watchdog               = watchdog;
   endfunction : build_phase

   // UVM callback: puts the control pins to 0 through pulls and resets the DUT.
   task reset_phase(uvm_phase phase);
      hexk_clk_rst_reset_seq reset_seq = hexk_clk_rst_reset_seq::type_id::create("reset_seq");
      super.reset_phase(phase);
      phase.raise_objection(this, "reset");
      env_cfg.ctrl_vif.pull_down();
      `hexk_randomize_with_or_fatal(reset_seq, "HEXK_SMOKE_RAND", hold_cycles == RESET_CYCLES;)
      reset_seq.start(env.clk_rst_agent.sqr);
      phase.drop_objection(this, "reset done");
   endtask : reset_phase

   // UVM callback: lets the test prepare the DUT, then sends the words. The watchdog counts from here.
   task main_phase(uvm_phase phase);
      hexk_valid_ready_random_seq #(hexk_smoke_env_cfg::WIDTH) traffic_seq;
      int unsigned                                             num_words = env_cfg.num_items;
      super.main_phase(phase);
      phase.raise_objection(this, "traffic");
      traffic_seq = hexk_valid_ready_random_seq#(hexk_smoke_env_cfg::WIDTH)::type_id::create("traffic_seq");
      prepare();
      watchdog.set_inactivity_limit(INACTIVITY_LIMIT_PS);
      `hexk_randomize_with_or_fatal(traffic_seq, "HEXK_SMOKE_RAND", num_items == num_words;)
      traffic_seq.start(env.in_agent.sqr);
      phase.drop_objection(this, "traffic sent");
   endtask : main_phase

   // UVM callback: every word that was sent must have been matched by the scoreboard.
   function void check_phase(uvm_phase phase);
      hexk_sb_stats stats = env.sb.get_stats();
      super.check_phase(phase);
      `hexk_check_eq(stats.matched, env_cfg.num_items, "HEXK_SMOKE_MATCHED", "words matched by the scoreboard")
   endfunction : check_phase

endclass : hexk_smoke_base_test

`endif  // HEXK_SMOKE_BASE_TEST_SV
