// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_wait_macros_example.sv
//
// Minimal use of the wait macros: wait for a signal with a time limit, run statements with
// a time limit, and use hexk_wait_util where the outcome is wanted as a value.
// Here ready rises after 30 ns, so the first wait returns then without a message; the
// handshake task is slower than its limit and is ended with a UVM error.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_wait_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_wait_util;

   bit ready;
   bit timed_out;

   // Stands for a handshake that takes too long.
   task automatic slow_handshake();
      #500ns;
   endtask : slow_handshake

   initial begin
      #30ns;
      ready = 1;
   end

   initial begin
      `hexk_wait_timeout(ready, 100ns, "EXAMPLE_READY")
      $info("ready seen at %0t", $realtime);

      `hexk_spinwait(slow_handshake();, 200ns, "EXAMPLE_HANDSHAKE")

      ready = 0;
      hexk_wait_util::wait_or_timeout(ready, 50ns, timed_out);
      $info("second wait timed out: %0b", timed_out);
   end

endmodule : hexk_wait_macros_example
