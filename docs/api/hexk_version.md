# hexk_version

## 1. Summary

Version of hexk-sv-lib as preprocessor defines.

## 2. When to use / when not to use

Use it to print the library version in a banner or log, and to make code that must work with
several library versions adapt at compile or elaboration time.

To find out whether a release has a module, test its define `HEXK_HAS_<MODULE>`, such as
`` `ifdef HEXK_HAS_CSR_UTIL ``, rather than a version number. Do not parse
`HEXK_VERSION_STR` at run time; the three numeric defines exist so that nobody has to.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_version.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_version.svh`:

```systemverilog
// Major version number (SemVer): incompatible API changes.
`define HEXK_VERSION_MAJOR
// Minor version number (SemVer): added functionality; may break APIs before 1.0.0.
`define HEXK_VERSION_MINOR
// Patch version number (SemVer): fixes only.
`define HEXK_VERSION_PATCH
// Full version as a string literal, for banners and log files.
`define HEXK_VERSION_STR
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
```
<!-- HEXK_GEN:END api -->

The three numbers are plain decimal literals, usable in `if`, `case` and generate conditions.
`HEXK_VERSION_STR` is a string literal including its quotes.

## 4. Behaviour and invariants

- The file is generated from `VERSION` by `make version`. `make pre_sim` fails when the two
  disagree, so the defines always describe the checkout they come from.
- It only defines macros and is include-guarded: it can be included at any scope, any number
  of times.
- `hexk_core_pkg.sv` includes it, but macros do not cross compilation units. Include it in
  every file that uses the defines.

## 5. Configuration

None.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_version/hexk_version_example.sv`, elaborated in Gate 1:

```systemverilog
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
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Editing `hexk_version.svh` by hand.** The next `make version` overwrites it and
  `make pre_sim` rejects the mismatch. Edit `VERSION` and run `make version`.
- **Comparing version strings at run time** (`if (`HEXK_VERSION_STR == "0.1.0")`). It breaks on
  the next patch release. Compare `HEXK_VERSION_MAJOR` and `HEXK_VERSION_MINOR` instead.
- **Relying on another file's include.** In tools that compile each file as its own
  compilation unit the defines are not visible. Include the header where it is used.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
