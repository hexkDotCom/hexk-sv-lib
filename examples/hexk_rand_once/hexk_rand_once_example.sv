// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_once_example.sv
//
// Minimal use of the randomize-once guard: an environment cfg that the base test randomizes
// once. A helper further down randomizes it again by mistake, after the address map was
// already built from its values; the guard reports that with an error and a stack trace.
// Then the cfg is re-randomized on purpose, which allow_rerandomize() permits once.
// Run it with +hexk_rand_once_trap=env_cfg to see who randomizes the cfg first.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_rand_once_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;

   class hexk_example_env_cfg extends uvm_object;
      rand int unsigned num_channels;

      constraint num_channels_cstr {num_channels inside {[1 : 8]};}

      `hexk_rand_once_guard_decl

      function new(string name = "hexk_example_env_cfg");
         super.new(name);
      endfunction : new
   endclass : hexk_example_env_cfg

   hexk_example_env_cfg cfg;

   // Stands for a helper that should only read the cfg.
   function automatic void careless_helper();
      `hexk_randomize_or_fatal(cfg, "EXAMPLE")
   endfunction : careless_helper

   initial begin
      cfg = new("env_cfg");
      `hexk_randomize_or_fatal(cfg, "EXAMPLE")
      `uvm_info("EXAMPLE", $sformatf("building %0d channels", cfg.num_channels), UVM_NONE)

      // Reported by the guard: the channels were built from the first value.
      careless_helper();

      // Intended: the test asks for it first.
      cfg.rand_once.allow_rerandomize();
      `hexk_randomize_or_fatal(cfg, "EXAMPLE")
   end

endmodule : hexk_rand_once_example
