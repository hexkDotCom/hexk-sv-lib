// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_error_test.sv
//
// Smoke test that must fail with data errors: the test makes the DUT invert bit 0 of every
// word at its output, so the scoreboard reports a mismatch for each and the test ends with
// TEST FAILED. It shows that the checking of the testbench finds an error.

`ifndef HEXK_SMOKE_ERROR_TEST_SV
`define HEXK_SMOKE_ERROR_TEST_SV

class hexk_smoke_error_test extends hexk_smoke_base_test;

   `uvm_component_utils(hexk_smoke_error_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Hook of the base test: switches the corruption of the DUT on.
   virtual task prepare();
      env_cfg.ctrl_vif.drive_pin(hexk_smoke_env_cfg::CORRUPT_PIN, 1'b1);
   endtask : prepare

endclass : hexk_smoke_error_test

`endif  // HEXK_SMOKE_ERROR_TEST_SV
