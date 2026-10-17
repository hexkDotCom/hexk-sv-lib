// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_version.svh
//
// Version of hexk-sv-lib as preprocessor defines.
// GENERATED from the VERSION file by `make version`; do not edit by hand (FIL-10).
// Include it where code has to adapt to the library version at compile time. The file
// only defines macros, so it can be included at any scope and any number of times.
// The HEXK_HAS_<MODULE> defines say which modules this release contains; test them with
// `ifdef in code that must also compile against an older release.
//
//! @module    hexk_version
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_VERSION_SVH
`define HEXK_VERSION_SVH

// Major version number (SemVer): incompatible API changes.
`define HEXK_VERSION_MAJOR 0

// Minor version number (SemVer): added functionality; may break APIs before 1.0.0.
`define HEXK_VERSION_MINOR 10

// Patch version number (SemVer): fixes only.
`define HEXK_VERSION_PATCH 0

// Full version as a string literal, for banners and log files.
`define HEXK_VERSION_STR "0.10.0"

// Defined when hexk_base_test is part of this release.
`define HEXK_HAS_BASE_TEST

// Defined when hexk_check_macros is part of this release.
`define HEXK_HAS_CHECK_MACROS

// Defined when hexk_clk_rst is part of this release.
`define HEXK_HAS_CLK_RST

// Defined when hexk_coverage is part of this release.
`define HEXK_HAS_COVERAGE

// Defined when hexk_crc is part of this release.
`define HEXK_HAS_CRC

// Defined when hexk_csr_util is part of this release.
`define HEXK_HAS_CSR_UTIL

// Defined when hexk_delay is part of this release.
`define HEXK_HAS_DELAY

// Defined when hexk_delay_analysis_fifo is part of this release.
`define HEXK_HAS_DELAY_ANALYSIS_FIFO

// Defined when hexk_ecc is part of this release.
`define HEXK_HAS_ECC

// Defined when hexk_enum_util is part of this release.
`define HEXK_HAS_ENUM_UTIL

// Defined when hexk_eot_registry is part of this release.
`define HEXK_HAS_EOT_REGISTRY

// Defined when hexk_hdl_macros is part of this release.
`define HEXK_HAS_HDL_MACROS

// Defined when hexk_knobs is part of this release.
`define HEXK_HAS_KNOBS

// Defined when hexk_lfsr is part of this release.
`define HEXK_HAS_LFSR

// Defined when hexk_math is part of this release.
`define HEXK_HAS_MATH

// Defined when hexk_mem_model is part of this release.
`define HEXK_HAS_MEM_MODEL

// Defined when hexk_meta_item is part of this release.
`define HEXK_HAS_META_ITEM

// Defined when hexk_objection_aggregator is part of this release.
`define HEXK_HAS_OBJECTION_AGGREGATOR

// Defined when hexk_pins is part of this release.
`define HEXK_HAS_PINS

// Defined when hexk_plusarg is part of this release.
`define HEXK_HAS_PLUSARG

// Defined when hexk_rand_once is part of this release.
`define HEXK_HAS_RAND_ONCE

// Defined when hexk_rand_stream is part of this release.
`define HEXK_HAS_RAND_STREAM

// Defined when hexk_regex is part of this release.
`define HEXK_HAS_REGEX

// Defined when hexk_report_catcher is part of this release.
`define HEXK_HAS_REPORT_CATCHER

// Defined when hexk_report_macros is part of this release.
`define HEXK_HAS_REPORT_MACROS

// Defined when hexk_report_server is part of this release.
`define HEXK_HAS_REPORT_SERVER

// Defined when hexk_scoreboard is part of this release.
`define HEXK_HAS_SCOREBOARD

// Defined when hexk_str is part of this release.
`define HEXK_HAS_STR

// Defined when hexk_uid is part of this release.
`define HEXK_HAS_UID

// Defined when hexk_util_macros is part of this release.
`define HEXK_HAS_UTIL_MACROS

// Defined when hexk_valid_ready is part of this release.
`define HEXK_HAS_VALID_READY

// Defined when hexk_value_wrapper is part of this release.
`define HEXK_HAS_VALUE_WRAPPER

// Defined when hexk_wait_macros is part of this release.
`define HEXK_HAS_WAIT_MACROS

// Defined when hexk_watchdog is part of this release.
`define HEXK_HAS_WATCHDOG

`endif  // HEXK_VERSION_SVH
