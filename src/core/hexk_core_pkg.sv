// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_core_pkg.sv
//
// Pure-SystemVerilog utility package of hexk-sv-lib, with no UVM dependency.
// Compile it with src/core/hexk_core.f and import the classes you use by name. Everything
// in it also runs on Verilator. Problems are reported through return values and $error,
// because the package cannot know whether UVM is present.
//
//! @module    hexk_core_pkg
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_CORE_PKG_SV
`define HEXK_CORE_PKG_SV

`include "hexk_version.svh"
`include "hexk_sim_compat.svh"

// Width in bits of the vectors of the width-generic helpers (hexk_math, hexk_crc, hexk_ecc).
`ifndef HEXK_MAX_WIDTH
`define HEXK_MAX_WIDTH 1024
`endif

package hexk_core_pkg;

   // Vector of HEXK_MAX_WIDTH bits, the argument type of the width-generic helpers; cast with hexk_bits_t'(x).
   typedef logic [`HEXK_MAX_WIDTH-1:0] hexk_bits_t;

   `include "hexk_str.sv"
   `include "hexk_math.sv"
   `include "hexk_enum_util.sv"
   `include "hexk_crc.sv"
   `include "hexk_lfsr.sv"
   `include "hexk_ecc.sv"
   `include "hexk_rand_stream.sv"
   `include "hexk_plusarg.sv"
endpackage : hexk_core_pkg

`endif  // HEXK_CORE_PKG_SV
