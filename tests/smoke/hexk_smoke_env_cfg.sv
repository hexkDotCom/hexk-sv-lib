// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_env_cfg.sv
//
// Configuration of the smoke environment: the cfgs of its three agents and of its
// scoreboard, the handle of the control pins, and how many words a test sends.
// It contains the cfgs of its children and creates them (guide rule CFG-3), so one
// randomize() covers all of them. The base test assigns the interfaces and hands the cfg
// to the environment.

`ifndef HEXK_SMOKE_ENV_CFG_SV
`define HEXK_SMOKE_ENV_CFG_SV

class hexk_smoke_env_cfg extends uvm_object;

   // Width of the words that go through the FIFO, and the number of control pins.
   localparam int unsigned WIDTH = 8;
   localparam int unsigned NUM_CTRL_PINS = 2;

   // The control pins of the DUT by number.
   localparam int unsigned CORRUPT_PIN = 0;
   localparam int unsigned STALL_PIN = 1;

   // The cfgs of the agents: clock and reset, the input channel and the output channel of the FIFO.
   rand hexk_clk_rst_agent_cfg              clk_rst_cfg;
   rand hexk_valid_ready_agent_cfg #(WIDTH) in_cfg;
   rand hexk_valid_ready_agent_cfg #(WIDTH) out_cfg;

   // The cfg of the scoreboard.
   hexk_scoreboard_cfg                      sb_cfg;

   // The control pins of the DUT.
   virtual hexk_pins_if #(NUM_CTRL_PINS)    ctrl_vif;

   // Number of words a test sends through the FIFO.
   rand int unsigned                        num_items;

   `uvm_object_utils(hexk_smoke_env_cfg)

   // What every legal cfg keeps.
   constraint legal_values_cstr {num_items inside {[1 : 10000]};}

   // A plain randomize() gives 20 words; the knob num_items replaces it.
   constraint default_values_cstr {soft num_items == 20;}

   // Creates the cfg with the cfgs of its children; the agent at the output is a responder.
   function new(string name = "hexk_smoke_env_cfg");
      super.new(name);
      clk_rst_cfg  = hexk_clk_rst_agent_cfg::type_id::create("clk_rst_cfg");
      in_cfg       = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("in_cfg");
      out_cfg      = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("out_cfg");
      sb_cfg       = hexk_scoreboard_cfg::type_id::create("sb_cfg");
      out_cfg.role = HEXK_VALID_READY_RESPONDER;
      num_items    = 20;
   endfunction : new

endclass : hexk_smoke_env_cfg

`endif  // HEXK_SMOKE_ENV_CFG_SV
