// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_plusarg_example.sv
//
// Minimal use of hexk_plusarg: read an integer, a string, a flag and a list from the
// command line, each with a default. Run it with, for example,
// +fifo_depth=0x40 +mode=fast +waves +tests=smoke,reset. Needs only src/core/hexk_core.f.

module hexk_plusarg_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_plusarg;

   localparam longint DEFAULT_DEPTH = 16;

   longint depth;
   string  mode;
   bit     waves;
   string  tests [$];

   initial begin
      depth = hexk_plusarg::get_int("fifo_depth", DEFAULT_DEPTH);
      mode  = hexk_plusarg::get_str("mode", "normal");
      waves = hexk_plusarg::get_bit("waves", 0);
      hexk_plusarg::get_list("tests", tests);
      $info("depth %0d, mode %s, waves %0b, %0d tests selected", depth, mode, waves, tests.size());
   end

endmodule : hexk_plusarg_example
