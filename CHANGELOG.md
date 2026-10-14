# Changelog

All notable changes to hexk-sv-lib are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0.0 a
minor version may change an API; such changes are listed under "Changed".

## [Unreleased]

## [0.7.0] - 2026-10-14

First public release. All modules are `experimental`: their APIs may still change before
1.0.0, and every such change will be listed here.

### Added

- **Core layer** (`hexk_core_pkg`, no UVM, runs on Verilator): string helpers (`hexk_str`),
  enum utilities (`hexk_enum_util`), bit and integer helpers (`hexk_math`), CRC (`hexk_crc`),
  LFSR (`hexk_lfsr`), extended Hamming code (`hexk_ecc`), seed-stable random streams
  (`hexk_rand_stream`), plusargs with defaults (`hexk_plusarg`), version defines
  (`hexk_version`), simulator shims (`hexk_sim_compat`).
- **UVM layer** (`hexk_uvm_pkg`, UVM 1.2 and IEEE 1800.2-2017/2020):
  - reporting and checks: check macros and check statistics, static report macros, report
    server and report catcher, waits with a time limit, regex match and filter;
  - end of test and liveness: objection aggregator, end-of-test registry, watchdog;
  - configuration and stimulus: knobs, delays, guard against a second randomization,
    optional base test and testbench-top include, utility macros;
  - data and checking: unique IDs, value wrapper, meta item, delayed analysis FIFO,
    scoreboard (in order, out of order, streams), sparse memory model, HDL access by path,
    coverage helpers.
- **Agents:** clock and reset (`hexk_clk_rst`), valid/ready (`hexk_valid_ready`), pins
  interface (`hexk_pins`).
- A contract document per module in `docs/api/`, a minimal example per module in
  `examples/`, and `llms.txt` as an index for AI assistants.
- `scripts/hexk_rebrand.py`, which writes a copy of the library with another prefix.

Tested with free tools (lint, elaboration with slang against UVM 1.2 and 2020, unit tests on
Verilator 5.046) and on Questa 2024.1 and VCS X-2025.06, each with UVM 1.2 and UVM 2020.3.1
(unit tests, every example, the smoke testbench). See "Where it has been tested" in the
README for the numbers and the limits on Verilator. Nothing has been run on Xcelium.

[Unreleased]: https://github.com/hexkDotCom/hexk-sv-lib/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/hexkDotCom/hexk-sv-lib/releases/tag/v0.7.0
