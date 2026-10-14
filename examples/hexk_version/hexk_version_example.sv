// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_version_example.sv
//
// Minimal use of hexk_version.svh and hexk_sim_compat.svh.
// Prints the library version and the simulator name once at time 0, and shows how code
// adapts to the library version at elaboration time. Needs only src/core/hexk_core.f.

`include "hexk_version.svh"
`include "hexk_sim_compat.svh"

module hexk_version_example;
   timeunit 1ns / 1ps;

   initial begin
      $info("hexk-sv-lib %s on %s", `HEXK_VERSION_STR, `HEXK_SIM_NAME);
   end

   if (`HEXK_VERSION_MAJOR == 0) begin : gen_pre_release
      initial begin
         $info("pre-1.0 release: a minor version may change an API");
      end
   end

endmodule : hexk_version_example
