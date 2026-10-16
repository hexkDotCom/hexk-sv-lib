// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_env_cfg.sv
//
// Configuration of the reference environment: the cfgs of the agents and scoreboards, the bus,
// and what the test sends. It is randomized once, in the build phase of the test; a second
// randomization would change values that the environment has already used, which the
// hexk_rand_once guard reports. Members that a test wants different are assigned after the
// randomization, not given as inline constraints, which Verilator does not apply over soft ones.

`ifndef HEXK_REF_ENV_CFG_SV
`define HEXK_REF_ENV_CFG_SV

class hexk_ref_env_cfg extends uvm_object;

   // Width of the words of the input channel.
   localparam int unsigned WIDTH = 32;

   // The cfgs of the agents: clock and reset, and the input channel.
   rand hexk_clk_rst_agent_cfg              clk_rst_cfg;
   rand hexk_valid_ready_agent_cfg #(WIDTH) in_cfg;

   // The cfgs of the two scoreboards: packet results, and the commits of the pipeline.
   hexk_scoreboard_cfg                      result_sb_cfg;
   hexk_scoreboard_cfg                      commit_sb_cfg;

   // The cfg of the bus agent, with the register bus.
   hexk_ref_bus_agent_cfg                   bus_cfg;

   // The strap pins of the testbench (hexk_pins_if): pin STALL_PIN holds the input's ready at 0.
   localparam int unsigned NUM_STRAPS = 1;
   localparam int unsigned STALL_PIN = 0;
   virtual hexk_pins_if #(NUM_STRAPS) strap_vif;

   // Number of packets a test sends; the base test sets it from the knob ref_packets.
   int unsigned                       num_packets;

   // The longest a packet may take to complete after its last word (2 us): the time limit of the wait for
   // DONE, of every spin-wait of env.csr, and of the waits until the environment is drained or quiet.
   longint unsigned                   done_timeout_ps = 2_000_000;

   // Lengths of the packets: 1 to 16 words.
   rand int unsigned                  min_len;
   rand int unsigned                  max_len;

   // The guard against a second randomization: the member rand_once and its pre_ and post_randomize().
   `hexk_rand_once_guard_decl

   `uvm_object_utils(hexk_ref_env_cfg)

   // What every legal cfg keeps.
   constraint legal_values_cstr {
      min_len inside {[1 : 16]};
      max_len inside {[1 : 16]};
      min_len <= max_len;
   }

   // A plain randomize() gives packets of 1 to 16 words.
   constraint default_values_cstr {
      soft min_len == 1;
      soft max_len == 16;
   }

   // Creates the cfg and the cfgs of its children.
   function new(string name = "hexk_ref_env_cfg");
      super.new(name);
      clk_rst_cfg              = hexk_clk_rst_agent_cfg::type_id::create("clk_rst_cfg");
      // The monitor of the agent checks every interval of the clock against the clock it drives.
      clk_rst_cfg.check_period = 1;
      in_cfg                   = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("in_cfg");
      result_sb_cfg            = hexk_scoreboard_cfg::type_id::create("result_sb_cfg");
      commit_sb_cfg            = hexk_scoreboard_cfg::type_id::create("commit_sb_cfg");
      bus_cfg                  = hexk_ref_bus_agent_cfg::type_id::create("bus_cfg");
      min_len                  = 1;
      max_len                  = 16;
   endfunction : new

endclass : hexk_ref_env_cfg

`endif  // HEXK_REF_ENV_CFG_SV
