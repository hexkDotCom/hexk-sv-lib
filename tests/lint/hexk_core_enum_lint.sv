// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_core_enum_lint.sv
//
// Lint case for 'make lint' (Verilator -Wall): code of a user that keeps an enum of the core
// package in a variable and only prints its name. The enums have the width of their values,
// so this lints clean; a plain enum (32 bits) would make the unused upper bits a warning.
// Needs only src/core/hexk_core.f.

module hexk_core_enum_lint;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::*;

   hexk_ecc             ecc;
   hexk_bits_t          read_data;
   int unsigned         syndrome;
   hexk_ecc::status_e   status;
   hexk_ecc::layout_e   layout;
   hexk_lfsr::kind_e    kind;
   hexk_plusarg::form_e form;

   initial begin
      ecc    = new(8);
      status = ecc.decode(ecc.encode(hexk_bits_t'(8'h5A)), read_data, syndrome);
      layout = ecc.get_layout();
      kind   = hexk_lfsr::HEXK_LFSR_FIBONACCI;
      form   = hexk_plusarg::HEXK_PLUSARG_BARE;
      $display("%s %s %s %s 0x%0h %0d", status.name(), layout.name(), kind.name(), form.name(), read_data, syndrome);
   end

endmodule
