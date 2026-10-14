// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_macros.svh
//
// Umbrella header for every macro file of the UVM layer of hexk-sv-lib.
// Include it once per compilation unit, before the first use of a library macro. It pulls
// in uvm_macros.svh through hexk_uvm_compat.svh, so user code needs no separate include.
// Macro files are added to it as their modules are implemented.
//
//! @module    hexk_macros
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_MACROS_SVH
`define HEXK_MACROS_SVH

`include "hexk_uvm_compat.svh"
`include "hexk_report_macros.svh"
`include "hexk_check_macros.svh"
`include "hexk_wait_macros.svh"
`include "hexk_rand_once_macros.svh"
`include "hexk_util_macros.svh"
`include "hexk_hdl_macros.svh"
`include "hexk_coverage_macros.svh"

`endif  // HEXK_MACROS_SVH
