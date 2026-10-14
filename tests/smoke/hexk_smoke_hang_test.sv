// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke_hang_test.sv
//
// Smoke test that must hang: the test makes the DUT stop taking words, so the first word
// waits for ever and nothing leaves the FIFO. The watchdog ends the test with a fatal that
// names who is still busy. It shows that a hang ends early and with a diagnosis.

`ifndef HEXK_SMOKE_HANG_TEST_SV
`define HEXK_SMOKE_HANG_TEST_SV

class hexk_smoke_hang_test extends hexk_smoke_base_test;

   `uvm_component_utils(hexk_smoke_hang_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Hook of the base test: stalls the input of the DUT.
   virtual task prepare();
      env_cfg.ctrl_vif.drive_pin(hexk_smoke_env_cfg::STALL_PIN, 1'b1);
   endtask : prepare

endclass : hexk_smoke_hang_test

`endif  // HEXK_SMOKE_HANG_TEST_SV
