// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_enum_util_example.sv
//
// Minimal use of hexk_enum_util: turn text into an enum value without a case statement,
// print the legal names, and get short names by stripping the common prefix.
// Needs only src/core/hexk_core.f.

module hexk_enum_util_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_enum_util;

   // Operating modes of an imaginary DUT.
   typedef enum {
      HEXK_EXAMPLE_MODE_IDLE,
      HEXK_EXAMPLE_MODE_FAST,
      HEXK_EXAMPLE_MODE_SLOW
   } hexk_example_mode_e;

   // One typedef per enum keeps the calls short.
   typedef hexk_enum_util#(hexk_example_mode_e) hexk_example_mode_util;

   hexk_example_mode_e mode;
   hexk_example_mode_e values[string];

   initial begin
      if (!hexk_example_mode_util::try_from_name("hexk_example_mode_fast", mode, 1)) begin
         $error("not a mode; legal names: %s", hexk_example_mode_util::to_list_str());
      end
      $info("mode %s, one of %0d", hexk_example_mode_util::name(mode), hexk_example_mode_util::num());

      hexk_example_mode_util::to_map(values, 1);
      $info("without '%s': FAST=%0d SLOW=%0d", hexk_example_mode_util::common_prefix(), values["FAST"], values["SLOW"]);
   end

endmodule : hexk_enum_util_example
