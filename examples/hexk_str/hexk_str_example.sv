// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_str_example.sv
//
// Minimal use of hexk_str: take a hierarchical name apart, sort names in natural order,
// and shape strings for a fixed-width log column. Needs only src/core/hexk_core.f.

module hexk_str_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_str;

   localparam string PATH = "uvm_test_top.env.agent_3.drv";

   string fields[$];
   string names [$];

   initial begin
      hexk_str::split(PATH, fields, ".");
      $info("%0d elements, leaf '%s', inside '%s'", fields.size(), fields[$], hexk_str::scope_slice(PATH, 1, -2));

      hexk_str::split("agent_10 agent_2 agent_1", names);
      hexk_str::natural_sort(names);
      $info("natural order: %s", hexk_str::join_str(names, ", "));

      $info("[%s] [%s]", hexk_str::pad("id", 8, 1), hexk_str::truncate(PATH, 12, 1));
      $info("grouped as '%s'", hexk_str::denumber("agent_12.item_7"));
   end

endmodule : hexk_str_example
