// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_env_cfg.sv
//
// Configuration of the reference environment: the cfgs of the agents and scoreboards, the bus,
// which agents the environment builds, and what the test sends. It is randomized once, in the
// build phase of the test; a second randomization would change values that the environment has
// already used, which the hexk_rand_once guard reports. Members that a test wants different are
// assigned after the randomization, not given as inline constraints, which Verilator does not
// apply over soft ones.

`ifndef HEXK_REF_ENV_CFG_SV
`define HEXK_REF_ENV_CFG_SV

class hexk_ref_env_cfg extends uvm_object;

   // Width of the words of the input channel.
   localparam int unsigned WIDTH = 32;

   // The cfgs of the agents: clock and reset, and the input channel.
   rand hexk_clk_rst_agent_cfg              clk_rst_cfg;
   rand hexk_valid_ready_agent_cfg #(WIDTH) in_cfg;

   // The cfgs of the two scoreboards: packet results, and the commits of the pipeline.
   rand hexk_scoreboard_cfg                 result_sb_cfg;
   rand hexk_scoreboard_cfg                 commit_sb_cfg;

   // The cfg of the bus agent, with the register bus.
   rand hexk_ref_bus_agent_cfg              bus_cfg;

   // Which agents the environment builds, and whose interfaces the test fetches (guide CFG-8). A parent that has an
   // agent of its own on that interface sets the flag to 0 and connects that agent to the exports of the environment.
   // The clock and reset agent is always built: the environment takes the resets from it.
   bit                                      has_in_agent   = 1;
   bit                                      has_bus_agent  = 1;

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

   // The guard against a second randomization: the member rand_once and its pre_ and post_randomize(). A copy has a
   // guard of its own.
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
   endfunction : new

   // UVM hook of copy() and clone(): copies every member; the copy has cfgs of its own for the children and shares
   // the interface of the straps.
   function void do_copy(uvm_object rhs);
      hexk_ref_env_cfg other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("REF_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                               rhs.get_name(), rhs.get_type_name()))
         return;
      end
      clk_rst_cfg   = null;
      in_cfg        = null;
      result_sb_cfg = null;
      commit_sb_cfg = null;
      bus_cfg       = null;
      if (other.clk_rst_cfg != null) begin
         `hexk_cast_or_fatal(clk_rst_cfg, other.clk_rst_cfg.clone(), "REF_COPY_TYPE")
      end
      if (other.in_cfg != null) begin
         `hexk_cast_or_fatal(in_cfg, other.in_cfg.clone(), "REF_COPY_TYPE")
      end
      if (other.result_sb_cfg != null) begin
         `hexk_cast_or_fatal(result_sb_cfg, other.result_sb_cfg.clone(), "REF_COPY_TYPE")
      end
      if (other.commit_sb_cfg != null) begin
         `hexk_cast_or_fatal(commit_sb_cfg, other.commit_sb_cfg.clone(), "REF_COPY_TYPE")
      end
      if (other.bus_cfg != null) begin
         `hexk_cast_or_fatal(bus_cfg, other.bus_cfg.clone(), "REF_COPY_TYPE")
      end
      has_in_agent    = other.has_in_agent;
      has_bus_agent   = other.has_bus_agent;
      strap_vif       = other.strap_vif;
      num_packets     = other.num_packets;
      done_timeout_ps = other.done_timeout_ps;
      min_len         = other.min_len;
      max_len         = other.max_len;
   endfunction : do_copy

   // UVM hook of compare(): compares every member, the cfgs of the children by their members; the interfaces of the
   // straps must be the same.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_ref_env_cfg other;
      bit              same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      same = 1;
      same &= comparer.compare_object("clk_rst_cfg", clk_rst_cfg, other.clk_rst_cfg);
      same &= comparer.compare_object("in_cfg", in_cfg, other.in_cfg);
      same &= comparer.compare_object("result_sb_cfg", result_sb_cfg, other.result_sb_cfg);
      same &= comparer.compare_object("commit_sb_cfg", commit_sb_cfg, other.commit_sb_cfg);
      same &= comparer.compare_object("bus_cfg", bus_cfg, other.bus_cfg);
      same &= comparer.compare_field_int("has_in_agent", 64'(has_in_agent), 64'(other.has_in_agent), 1);
      same &= comparer.compare_field_int("has_bus_agent", 64'(has_bus_agent), 64'(other.has_bus_agent), 1);
      if (strap_vif != other.strap_vif) begin
         comparer.print_msg("strap_vif: the two refer to different interfaces");
         same = 0;
      end
      same &= comparer.compare_field_int("num_packets", 64'(num_packets), 64'(other.num_packets), 32);
      same &= comparer.compare_field_int("done_timeout_ps", done_timeout_ps, other.done_timeout_ps, 64);
      same &= comparer.compare_field_int("min_len", 64'(min_len), 64'(other.min_len), 32);
      same &= comparer.compare_field_int("max_len", 64'(max_len), 64'(other.max_len), 32);
      return same;
   endfunction : do_compare

   // UVM hook of print() and sprint(): every member, the cfgs of the children with theirs; the interface as set or
   // null.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_object("clk_rst_cfg", clk_rst_cfg);
      printer.print_object("in_cfg", in_cfg);
      printer.print_object("result_sb_cfg", result_sb_cfg);
      printer.print_object("commit_sb_cfg", commit_sb_cfg);
      printer.print_object("bus_cfg", bus_cfg);
      printer.print_field_int("has_in_agent", 64'(has_in_agent), 1, UVM_BIN);
      printer.print_field_int("has_bus_agent", 64'(has_bus_agent), 1, UVM_BIN);
      printer.print_string("strap_vif", (strap_vif == null) ? "null" : "set");
      printer.print_field_int("num_packets", 64'(num_packets), 32, UVM_DEC);
      printer.print_field_int("done_timeout_ps", done_timeout_ps, 64, UVM_DEC);
      printer.print_field_int("min_len", 64'(min_len), 32, UVM_DEC);
      printer.print_field_int("max_len", 64'(max_len), 32, UVM_DEC);
   endfunction : do_print

endclass : hexk_ref_env_cfg

`endif  // HEXK_REF_ENV_CFG_SV
