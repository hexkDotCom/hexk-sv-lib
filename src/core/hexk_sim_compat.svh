// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_sim_compat.svh
//
// Simulator differences behind three macros, so that no other file tests simulator defines.
// HEXK_SIM_NAME is the simulator name as a string literal, for banners. HEXK_STACKTRACE is
// a statement that prints the call stack where the simulator can do it and does nothing
// elsewhere; write it as `HEXK_STACKTRACE; inside procedural code. HEXK_SIM_NO_PIN_MODEL is
// defined where the simulator cannot model a pin: a net with several drivers, drive
// strengths and force; hexk_pins_if compiles without them there.
// Compile-time switches: +define+HEXK_NO_STACKTRACE makes the stack trace a no-op,
// +define+HEXK_STACKTRACE=<system task> selects another task.
// Assumes the simulators' own predefined macros VCS, QUESTA, XCELIUM and VERILATOR.
//
//! @module    hexk_sim_compat
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_SIM_COMPAT_SVH
`define HEXK_SIM_COMPAT_SVH

// Simulator name as a string literal: "vcs", "questa", "xcelium", "verilator" or "unknown".
`ifdef VCS
`define HEXK_SIM_NAME "vcs"
`elsif QUESTA
`define HEXK_SIM_NAME "questa"
`elsif XCELIUM
`define HEXK_SIM_NAME "xcelium"
`elsif VERILATOR
`define HEXK_SIM_NAME "verilator"
`else
`define HEXK_SIM_NAME "unknown"
`endif

// Defined where the simulator cannot model a net with several drivers, drive strengths and force.
`ifdef VERILATOR
`define HEXK_SIM_NO_PIN_MODEL
`endif

// Statement that prints the call stack; a statement without effect where unsupported or disabled.
`ifdef HEXK_NO_STACKTRACE
`ifdef HEXK_STACKTRACE
`undef HEXK_STACKTRACE
`endif
`define HEXK_STACKTRACE $write("")
`endif

`ifndef HEXK_STACKTRACE
`ifdef VCS
// Seen to print the call stack on VCS X-2025.06.
`define HEXK_STACKTRACE $stack
`elsif QUESTA
`define HEXK_STACKTRACE $stacktrace
`elsif XCELIUM
`define HEXK_STACKTRACE $stacktrace
`else
`define HEXK_STACKTRACE $write("")
`endif
`endif

`endif  // HEXK_SIM_COMPAT_SVH
