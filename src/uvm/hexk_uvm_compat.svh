// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uvm_compat.svh
//
// UVM version detection for the UVM layer of hexk-sv-lib.
// Defines exactly one of HEXK_UVM_VERSION_1_2 (Accellera UVM 1.2) and
// HEXK_UVM_VERSION_IEEE (IEEE 1800.2-2017 or 1800.2-2020 reference implementation), from
// the version macros that uvm_macros.svh provides. Library code branches on these two
// defines only, never on the UVM macros themselves, so a new UVM release is handled here.
// UVM 1.1d and older are not supported: neither define is set.
// HEXK_UVM_SUMMARY_FILE is the default argument of uvm_report_server::report_summarize in
// the version at hand, for a class that overrides that function.
// HEXK_UVM_REGEX_NO_DPI is defined when UVM is compiled without its regular expression code
// and matches globs instead.
//
//! @module    hexk_uvm_compat
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_UVM_COMPAT_SVH
`define HEXK_UVM_COMPAT_SVH

`include "uvm_macros.svh"

// Defined when compiling against Accellera UVM 1.2.
`ifdef UVM_VERSION_1_2
`define HEXK_UVM_VERSION_1_2
`endif

// Defined when compiling against an IEEE 1800.2 reference implementation (2017 or 2020).
`ifndef UVM_VERSION_1_2
`ifdef UVM_VERSION
`define HEXK_UVM_VERSION_IEEE
`endif
`endif

// Default of the argument of uvm_report_server::report_summarize: UVM 1.2 declares 0, the
// IEEE implementations UVM_STDOUT. An override repeats it, so that a call without an argument
// means the same through a handle of either class (VCS warns about a different default).
`ifdef HEXK_UVM_VERSION_IEEE
`define HEXK_UVM_SUMMARY_FILE UVM_STDOUT
`else
`define HEXK_UVM_SUMMARY_FILE 0
`endif

// Defined when UVM matches globs instead of regular expressions: with UVM_REGEX_NO_DPI, and with
// UVM_NO_DPI, which stands for it inside UVM. UVM passes neither on to a file that is compiled on its
// own, so the define that was given to the compilation is looked at here.
`ifdef UVM_NO_DPI
`define HEXK_UVM_REGEX_NO_DPI
`elsif UVM_REGEX_NO_DPI
`define HEXK_UVM_REGEX_NO_DPI
`endif

`endif  // HEXK_UVM_COMPAT_SVH
