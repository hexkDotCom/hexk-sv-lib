// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_pass_test.sv
//
// Smoke test that must pass: the words go through the FIFO unchanged and the scoreboard
// matches all of them.

`ifndef HEXK_SMOKE_PASS_TEST_SV
`define HEXK_SMOKE_PASS_TEST_SV

class hexk_smoke_pass_test extends hexk_smoke_base_test;

   `uvm_component_utils(hexk_smoke_pass_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

endclass : hexk_smoke_pass_test

`endif  // HEXK_SMOKE_PASS_TEST_SV
