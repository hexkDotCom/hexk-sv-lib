# Changelog

All notable changes to hexk-sv-lib are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Before 1.0.0 a
minor version may change an API; such changes are listed under "Changed".

## [Unreleased]

## [0.9.0] - 2026-10-16

Safer defaults on the way to 1.0.0, a reference testbench that checks the library from the
outside, and fixes. The API is being settled for 1.0.0: the changes below make the safe use
the default. Several of them change the behaviour of code written for 0.8.0; they are listed
under "Changed". All modules are still `experimental`.

### Added

- `hexk_clk_rst`: `HEXK_CLK_RST_ASSERT` and `HEXK_CLK_RST_RELEASE` items, with the sequences
  `hexk_clk_rst_assert_seq` and `hexk_clk_rst_release_seq`, so that the clock can be stopped,
  started or changed while the reset is held (a warm reset).
- `hexk_clk_rst`: `check_period` in the cfg (off by default) makes the monitor check every
  interval of the clock against the period and jitter of the status, the error
  `HEXK_CLK_RST_PERIOD`; `num_checked()` and `num_checked_at()` of the monitor count the
  checked intervals.
- `hexk_report_catcher::expect_check(id, count)`: one call for a check that fails on purpose;
  it expects the messages and allows the failures in `hexk_check_stats`.
  `hexk_report_catcher::check_unchecked()` checks every global catcher that the test did not
  check, and `hexk_report_catcher::NO_LIMIT` names the maximum without a limit.
- `hexk_base_test::create_cfg()`: the hook in which a block base test creates its cfg, after
  the factory overrides of a derived test.
- `hexk_plusarg::try_get_int()`, `try_get_bit()` and `try_get_real()`: read a plusarg without
  reporting and say whether it was absent, valid or invalid (`hexk_plusarg::status_e`).
- `hexk_mem_model`: the error `HEXK_MEM_UNKNOWN`. `hexk_watchdog`: the error
  `HEXK_WATCHDOG_LIMIT`.
- `hexk_wait_util::format_ps()`: formats a time in picoseconds as `%t` does.
- `hexk_base_test`: `fail_on_warnings` (knob `+hexk_fail_on_warnings`, off by default) makes a
  warning that the test did not allow with `allow_warning()` the error `HEXK_TEST_WARNING`;
  every test has a global report catcher, `catcher`, for the messages of a negative test.
  `hexk_warning_audit`, a listener of `hexk_report_server`, collects the warnings that were not
  allowed.
- `hexk_csr_util::check_reset_values(blk, include_volatile)`: with `include_volatile` 1 the
  volatile fields are checked against their reset values too, as after a reset of a quiet block.
- `hexk_busy_group`: a chosen group of `hexk_objectable` objects with `wait_idle()`, a wait
  with a time limit until none of them is busy in the middle of a test; after the limit it is
  an error with the caller's ID that names the busy members.
- `hexk_tb_top_inc.svh` ends every simulation with a banner of the verdict of the
  `hexk_base_test`: PASSED, FAILED or ABORTED (the simulation ended before the final phase, as
  after a fatal) in block letters, with the counts of the last line; in colour and with a face
  when `+hexk_report_color=1`. `hexk_base_test::get_verdict()`, `report_banner()` and
  `banner_text()` give the verdict and the banner to a testbench top of its own.
- A reference testbench in `tests/reference`: a complete UVM testbench of a small DUT that uses
  most modules together, with tests that pass and tests that must fail in a given way, run by
  `make reference SIM=questa|vcs`. `scripts/hexk_check_run.py` checks how a simulation of a
  testbench on `hexk_base_test` ended: the verdict, the exact count of every warning, error and
  fatal, lines that the log must contain, and no error of the simulator outside UVM; its
  contract is `docs/regression.md`, and `--check-list` checks a list of runs before a regression.

### Changed

- The equality checks, `hexk_check_mask` and `hexk_check_aligned` fail when the second operand
  has more bits than a check compares (`exp has 1101 bits ...`), as the first operand does;
  before, its upper bits were cut and the check could pass. A second operand no wider than the
  first always fits, also a signed one whose top bit is X or Z.
- `hexk_clk_rst`: an assert, release or reset item at a rising edge is done when the pin has
  changed, in the same time step; before, the sequence could return just before.
- `hexk_report_catcher::expect_check()` compares the ID as text, so an ID with characters such
  as `.` or `[` matches only itself.
- `hexk_enum_util::name()` finds a member whose value has X or Z bits.
- `scripts/hexk_check_run.py` also rejects a coloured report, and a report of UVM without a file
  and line, after the summary table.
- `hexk_clk_rst` and `hexk_valid_ready`: `ap` (and `cycle_ap`) of the agent are the ports of
  its monitor, set in the build phase, no longer ports of their own created with the agent:
  connect to them in the connect phase, as before; they are null before the build phase.
- `hexk_csr_util`: every access takes the sequence it belongs to as an optional last argument
  (`seq`), which becomes its parent sequence; without it the member `parent` is used, as
  before. One object can so serve every sequence of an environment.
- `hexk_csr_util::bit_bash()` randomizes the bit-bash sequence before it starts it, so that a
  factory override with random members gets random values; a failed randomization is the fatal
  `HEXK_CSR_RAND`.
- `hexk_scoreboard` builds the text of a mismatch with its item dumps only when the error is
  printed.
- The drivers and monitors of the agents, `hexk_watchdog` and `hexk_delay_analysis_fifo` call
  `super.run_phase()` first, as the examples now do in every phase method they override.
- Examples: the coverage example samples its data coverage in a `uvm_subscriber` fed by a
  `uvm_monitor`; the delayed-FIFO example creates the FIFO through the factory; the scoreboard
  predictor example no longer waits a fixed 1 ns at the end of the test.
- `hexk_report_server`: the contract states that the counts of `get_count()`, the summary table
  and the first error start with `install()`, while the counts of UVM are carried over.
- The equality checks (`hexk_check_eq`, `_ne`, `_case_eq`), `hexk_check_mask` and
  `hexk_check_aligned` fail when the second operand does not fit the width of the first as an
  unsigned or a signed number, with a message that says so, instead of cutting it:
  `` `hexk_check_eq(byte_value, 256, ...) `` no longer passes for 0. -1, `'1` and `8'hFF`
  against a byte still fit.
- `hexk_check_obj_eq(act, exp)` calls `exp.compare(act)`, as the scoreboard does, so that the
  expected object decides, for instance with the tolerance of a `hexk_value_wrapper`.
- `hexk_report_catcher::expect_msg()` without a maximum expects exactly the minimum, one by
  default: an error storm no longer passes. Give `NO_LIMIT` for no maximum. `hexk_base_test`
  checks the expectations of the global catchers in its report phase.
- `hexk_scoreboard`: the latency of a pair whose actual item came first runs from the timestamp
  of the expected item to the arrival of the actual item, instead of being 0.
- `hexk_scoreboard` takes its cfg from `uvm_config_db` (`"cfg"`) when none is assigned, as the
  agents do.
- `hexk_mem_model`: `addr_t` and `strobe_t` are four-state; an address or byte enable with an
  X or Z bit is the error `HEXK_MEM_UNKNOWN` and the access is not carried out, instead of an
  access at address 0.
- `hexk_clk_rst_op_e` has three bits.
- The agents create their items under the hierarchical name of the sequencer
  (`<sequencer path>.req`) or monitor (`<monitor path>.item`), so that a factory instance
  override can change the items of one agent.
- `hexk_csr_util::poll_interval_ps` is 100 ns by default instead of 0.
- The protocol errors of `hexk_valid_ready_if` start with the name of the assertion in its
  interface instance.
- `hexk_watchdog`: a limit that ends after `hexk_wait_util::LAST_PS` is the error
  `HEXK_WATCHDOG_LIMIT`, and is off, instead of never firing without a word. An assignment of
  `inactivity_limit_ps` during the run counts from then, like `set_inactivity_limit()`.
- `hexk_knobs`: a plusarg of an integer or bit knob that cannot be read is the error
  `HEXK_KNOBS_VALUE`, and a set function can still change the knob; it was a `$error` outside
  UVM reporting, and the knob kept the default as its command-line value.
- `hexk_regex` without the regex DPI code of UVM: an expression without an operator means
  what it means with it (`"^ID$"` is "equals", `"ID"` is "contains").
- The members of the sequences start at their defaults, so a sequence started without
  `randomize()` sends one item, holds the reset for 5 edges, and so on.
- `+hexk_timeout`, `+hexk_report_time_unit` and `+hexk_report_style` given without a value or
  with an empty one are an error or a warning like any other wrong value.

### Fixed

- `+hexk_report_color` with a value that is not a bit value is the warning `HEXK_REPORT_CFG`
  and keeps the colour setting, as for the other report plusargs; it was an error without an ID.
- `hexk_objection_aggregator::report_busy()` indents the further lines of a reason given to
  `raise()` by four spaces, as it did already for the reason of a busy object.
- On Questa, a `hexk_scoreboard` specialized in a package for an item class of that package read
  the time in the time unit of that package instead of picoseconds: with a unit of 1 ns its time
  limit `max_wait_ps` lasted 1000 times longer and its latencies were 1000 times shorter.
  `hexk_scoreboard`, `hexk_meta_item` and `hexk_delay_analysis_fifo` read and format the time
  through `hexk_wait_util` now.
- On Verilator, a bit check (`hexk_check_eq` and the others that compare bits) whose first
  operand calls a method of the class did not compile.
- `hexk_tb_top_inc.svh` passes `+UVM_TESTNAME` to `run_test()`, so that the test is found where
  UVM does not read the command line itself, as on Verilator.
- The `TEST FAILED` line of `hexk_base_test` said that checks "failed without an error" also when
  they had reported their errors; it says so only when there is no error and no fatal.
- `+hexk_rand_once_trap` was taken as given, and matched an object without a name, when the
  plusarg was absent.
- The contracts match the code: the weighted mode of `hexk_delay_cfg` needs its weights given
  after a randomization; `HEXK_NO_CHECK_STATS` removes the counting of the macros only;
  `idle_data_x` of a valid/ready cfg is read at every transfer; the texts of `hexk_uid` can
  repeat after `HEXK_UID_LENGTH`; the `@emits` of `hexk_report_server` lists
  `HEXK_REPORT_CFG`; the indexed analysis imp has parameter defaults and `get_type_name()`;
  the delayed FIFO keeps one queue; a typedef of a struct was cut short in the generated API
  section; a type declared inside a class is internal unless its contract names it.

Tested as 0.8.0 was, and with the reference testbench on Questa 2024.1 and VCS X-2025.06,
each with UVM 1.2 and UVM 2020.3.1. See "Where it has been tested" in the README for the
numbers. Nothing has been run on Xcelium.

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

[Unreleased]: https://github.com/hexkDotCom/hexk-sv-lib/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/hexkDotCom/hexk-sv-lib/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/hexkDotCom/hexk-sv-lib/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/hexkDotCom/hexk-sv-lib/releases/tag/v0.7.0
