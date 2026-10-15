# Changelog

All notable changes to hexk-sv-lib are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0.0 a
minor version may change an API; such changes are listed under "Changed".

## [Unreleased]

## [0.8.0] - 2026-10-15

Register accesses for any register model (`hexk_csr_util`), a time limit for items that wait
in the scoreboard, and fixes. Several fixes concern 0.7.0 code: on VCS, the delayed analysis
FIFO and the wait macros used inside a class with a type parameter waited 1000 times too long
when the item class came from a scope with another time unit. The API changes are listed
under "Changed". All modules are still `experimental`.

### Added

- `hexk_csr_util`: register accesses for any `uvm_reg_block`. Write and read with the status
  checked, read and check a register or a field (counted in `hexk_check_stats`), spin-waits
  with a poll interval and a time limit, a check of the reset value of every readable field
  of a block with one message per wrong register, the bit-bash sequence of UVM, and
  exclusions by a glob on the name of a register, field or block, through the resources that
  the register sequences of UVM honour too. It knows the accesses in flight and can keep a
  phase alive through `hexk_objection_aggregator`.
- `hexk_scoreboard_cfg.max_wait_ps`: the longest time an item may wait for its partner. An
  item that waits longer is the error `HEXK_SB_TIMEOUT` at that moment and is dropped, so a
  missing item no longer keeps the test alive until a watchdog ends it. Off by default.
  `hexk_sb_stats` counts such items in `timed_out`.
- `hexk_wait_util::wait_ps()`: waits a number of picoseconds; `ends_after_last()` says whether
  a wait ends after the last time a simulator can schedule, which it then never does.

### Changed

- Every enum of the library has the width of its values (`enum bit`, `enum bit [1:0]` or
  `enum bit [2:0]`) instead of 32 bits, such as `hexk_ecc::status_e`, `hexk_delay_mode_e`,
  `hexk_sb_mode_e` and `hexk_clk_rst_op_e`. A variable of such a type that is only printed by
  name no longer makes Verilator `-Wall` report unused bits. The operation of a
  `hexk_clk_rst_item` takes 2 bits in `pack()`, no longer 32.
- The summary line of `hexk_sb_stats` (`convert2string()`) has the count of timed-out items,
  and that of `hexk_scoreboard_cfg` the value of `max_wait_ps`.
- The time arguments of `hexk_clk_rst` end in `_ps` like every time of the library, which
  matters for calls with named arguments: `hexk_clk_rst_if::set_clock(new_period_ps,
  new_high_ps, new_jitter_ps)`, `set_start_delay(delay_ps)`, `wait_ps(duration_ps)`,
  `hexk_clk_rst_agent_cfg::high_time_ps(clock_period_ps, duty)` and
  `clock_illegal_reason(clock_period_ps, duty, clock_jitter_ps)`, and
  `hexk_clk_rst_status::set_clock(new_period_ps, duty, new_jitter_ps)`.
- API made consistent: `hexk_report_server::get_count(id, severity)` takes the ID first, like
  `hexk_report_catcher::get_count`; `hexk_scoreboard::get_stats(i)` returns a copy for a
  stream as for all streams; the counters of `hexk_check_stats` are local (read them with
  `num_passed()` and `num_failed()`); the index of a `hexk_analysis_imp_indexed_<SUFFIX>` is
  local, read with `get_index()`; `hexk_enum_util` and `hexk_enum_knob` are virtual classes,
  like the other classes of static functions; the parameterized components (scoreboard,
  delay FIFO, valid/ready agent, driver and monitor) give their name in `get_type_name()`;
  `hexk_report_cfg::unit_exponent()` is the one table of the time units.
- `hexk_clk_rst_if::is_running()` is `run_requested()`: it says whether the clock is asked to
  run, while the generator may still finish a high time after a stop.
- The examples use the macros of the library for randomization (`hexk_randomize_or_fatal`) and
  for the virtual interfaces (`hexk_vif_set`, `hexk_vif_get_or_fatal`), and compare their
  items through the comparer. The scoreboard and valid/ready examples give the scoreboard a
  `max_wait_ps` and check in `check_phase` that every item was matched; the pins example
  stops at a wait that timed out instead of going on as if the pins had changed.
- The API section of a contract lists what users call; the building blocks of the macros,
  marked "Internal" in the source, are left out.
- `hexk_valid_ready_data_seq` randomizes an item only when the factory gives a class derived
  from `hexk_valid_ready_item`. A plain item has no random field left after the sequence
  assigns `data` and `delay_cycles`, and the randomization cost several times as much as the
  rest of the item.

### Fixed

- `hexk_delay_analysis_fifo` on VCS: with an item class declared in a scope whose time unit
  is not 1 ps, such as a module or package with a time unit of 1 ns, the latency took 1000
  times too long.
- `hexk_delay_analysis_fifo`: a latency that took the due time past the largest simulation
  time wrapped around, and the item became visible at once. Every delay of the library now
  goes through `hexk_wait_util`, where a time after about 2.56 hours of simulation
  (`hexk_wait_util::LAST_PS`) never comes, the same on every simulator and resolution.
- `hexk_wait_timeout`, `hexk_wait_timeout_fatal` and `hexk_spinwait` used in a class with a
  type parameter could time out after the wrong time on VCS, like the FIFO above. Their timer
  now waits `TIMEOUT` rounded to whole picoseconds through `hexk_wait_util`.
- `hexk_wait_timeout` and `hexk_wait_timeout_fatal` reported a timeout when the condition was
  set by a nonblocking assignment in the time step of the timeout, which their contract says
  must not happen. At the timeout they now wait for the nonblocking assignments first.
- The example of `hexk_wait_util` passed `50ns` to `wait_or_timeout()`, whose timeout is in
  picoseconds, and so waited 50 ps; it passes `` `hexk_ps(50ns) ``.
- `hexk_report_server::set_cfg()` used a `time_precision` too fine for the time unit before it
  corrected it, for the warning about it; it corrects it first.
- `hexk_report_server` printed one time for two messages less than 1 ps apart, and its cache
  of file:line columns counted files instead of entries against its limit.
- `hexk_delay_analysis_fifo` with `latency_cycles` took a clock event less than 1 ps after a
  write for one in the same time step.
- `hexk_enum_knob::add()` accepted an enumeration with two members of the same text on the
  command line (`MODE_A`, `MODE_a`) and could return the wrong one; it is the error
  `HEXK_KNOBS_ENUM` now.
- `hexk_clk_rst`: the status gave a new clock of a running clock before the rising edge from
  which it holds.
- `hexk_scoreboard`: an actual item that came before its expected item got a latency from the
  timestamp of the expected item instead of 0.
- `hexk_math::swap_bytes()` with a byte count whose number of bits does not fit 32 bits
  returned 0 without an error.
- The example of `hexk_rand_stream` drew two values in the arguments of one call, whose order
  differs between simulators.
- The example of `hexk_watchdog` suggested `+hexk_timeout=1us` to see the global timeout,
  which the inactivity limit beats; it suggests `+hexk_timeout=250ns`.
- The descriptions in the sources of `hexk_report_server` and `hexk_report_catcher` say what
  the default cfg adds (stack traces, the summary table) and that `demote()` rules count
  their messages for `get_count()`.
- The contracts state three limits: an expression as operand of an order check is evaluated in
  the width of the comparison; `compare()`, `pack()` and printing of a valid/ready item cover
  `UVM_MAX_STREAMBITS` bits; the numbers of `hexk_uid` are 32-bit.
- The generated API section of the `hexk_delay` contract left out the last two delay modes.
- The contract of `hexk_version` said that the `HEXK_HAS_<MODULE>` defines are not generated;
  they are, one per module.
- The contracts of the check macros and the HDL access macros say that their local variable
  names (`hexk_check_act`, `hexk_hdl_value`, ...) must not be used for the operands.

Tested as 0.7.0 was: free tools (lint, elaboration with slang against UVM 1.2 and 2020, unit
tests on Verilator 5.046) and Questa 2024.1 and VCS X-2025.06, each with UVM 1.2 and UVM
2020.3.1 (unit tests, every example, the smoke testbench). See "Where it has been tested" in
the README for the numbers. Nothing has been run on Xcelium.

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

[Unreleased]: https://github.com/hexkDotCom/hexk-sv-lib/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/hexkDotCom/hexk-sv-lib/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/hexkDotCom/hexk-sv-lib/releases/tag/v0.7.0
