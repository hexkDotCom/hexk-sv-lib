# docs/api

One contract document per module, `<module>.md`: what a human or an AI assistant needs to use
the module correctly without reading its source. The nine sections are fixed: summary, when
to use, API, behaviour and invariants, configuration, messages emitted, minimal example,
anti-patterns, status.

The blocks between `HEXK_GEN:BEGIN` and `HEXK_GEN:END` markers are generated from the
`//!` tags and declarations in the source by `make docs`; do not edit them. Everything else
is written by hand. `make pre_sim` fails when a generated block is out of date.

## Modules

### Core layer (no UVM)

- [hexk_core_pkg](hexk_core_pkg.md): pure-SystemVerilog utility package
- [hexk_version](hexk_version.md): library version as preprocessor defines
- [hexk_sim_compat](hexk_sim_compat.md): simulator name and stack-trace macros
- [hexk_str](hexk_str.md): string utilities: split, join, strip, find, replace, pad,
  truncate, paths, scopes, digit runs, natural sort, hex dump
- [hexk_enum_util](hexk_enum_util.md): enum name lookup both ways, membership test,
  member list, common prefix, name-to-value map
- [hexk_crc](hexk_crc.md): CRC of 1 to 64 bits from catalogue parameters, with
  presets for CRC-8, CRC-16, CRC-32, CRC-32C and CRC-64
- [hexk_lfsr](hexk_lfsr.md): Galois or Fibonacci LFSR with a maximal-length tap table
- [hexk_ecc](hexk_ecc.md): extended Hamming code (SECDED) for 4 to 128 data bits:
  encode, decode with syndrome and corrected data, error injection; two bit orders
- [hexk_rand_stream](hexk_rand_stream.md): random numbers from a stream that owns
  its seed, for modules, interfaces and BFMs; uniform, normal, exponential, Poisson, weighted
- [hexk_plusarg](hexk_plusarg.md): plusargs with a default and exact name matching:
  presence, integer, string, bit, real, list
- [hexk_math](hexk_math.md): clamp, powers of two, alignment, range overlap,
  popcount, parity, bit and byte reversal, sign extension, masks

### UVM layer

- [hexk_uvm_pkg](hexk_uvm_pkg.md): UVM utility package
- [hexk_macros](hexk_macros.md): umbrella header for all library macros
- [hexk_uvm_compat](hexk_uvm_compat.md): UVM version detection
- [hexk_check_macros](hexk_check_macros.md): check macros with uniform messages and
  static IDs, randomize and cast wrappers, counts of executed checks
- [hexk_wait_macros](hexk_wait_macros.md): waits and statement blocks with a time
  limit that reports instead of hanging
- [hexk_report_macros](hexk_report_macros.md): report macros for static methods,
  modules and interfaces
- [hexk_regex](hexk_regex.md): regular expression match and include/exclude filter
- [hexk_uid](hexk_uid.md): hierarchical unique IDs for transactions, numbered per
  label under their parent
- [hexk_value_wrapper](hexk_value_wrapper.md): a packed value as a uvm_object, with
  an optional tolerance in compare()
- [hexk_meta_item](hexk_meta_item.md): an item with timestamp, unique ID and source
- [hexk_delay_analysis_fifo](hexk_delay_analysis_fifo.md): analysis FIFO whose
  items become visible after a time or a number of clock events, in order
- [hexk_scoreboard](hexk_scoreboard.md): generic scoreboard: in order, out of order
  by key or in order per key, streams, leftovers, latency, statistics, objection handling
- [hexk_mem_model](hexk_mem_model.md): sparse memory with byte enables, endianness,
  policies for reads of unwritten bytes, address range, $readmemh files
- [hexk_hdl_macros](hexk_hdl_macros.md): read, deposit, force and release of a signal
  by its HDL path, with the return code checked and reported
- [hexk_coverage](hexk_coverage.md): coverage of a valid/ready handshake (states and
  pairs of cycles), and a macro that creates a covergroup only when the knob coverage is on
- [hexk_report_server](hexk_report_server.md): report server with configurable line
  layout, stack traces and markers on triggers, listeners, summary table
- [hexk_report_catcher](hexk_report_catcher.md): expected errors, warnings and
  fatals for negative tests
- [hexk_objection_aggregator](hexk_objection_aggregator.md): one objection per
  phase while registered objects are busy, and a report of who is busy and why
- [hexk_eot_registry](hexk_eot_registry.md): end-of-test checks for objects that
  are not components, run in check_phase
- [hexk_watchdog](hexk_watchdog.md): global timeout and inactivity limit with
  heartbeats; one fatal that names the busy objects and the last heartbeats
- [hexk_knobs](hexk_knobs.md): test-wide knobs with default, help text and
  plusarg, final after lock(); table of all knobs, misspelled plusarg check
- [hexk_delay](hexk_delay.md): random delays as counts from a randomizable cfg:
  none, constant, uniform, normal, exponential, bursty, weighted; own random stream
- [hexk_rand_once](hexk_rand_once.md): guard that reports a second randomization
  of an object that must be randomized once, with a stack trace
- [hexk_util_macros](hexk_util_macros.md): singleton, indexed analysis imp, checked
  virtual interface hand-over through uvm_config_db, no-overlap constraint for ranges
- [hexk_base_test](hexk_base_test.md): optional common base test and testbench-top
  include: report server, knobs, aggregator, registry, watchdog, TEST PASSED/FAILED line
- [hexk_clk_rst](hexk_clk_rst.md): clock and reset agent: interface that generates a
  clock and a reset, sequences for reset, frequency, stop and start, reset events, clock count
- [hexk_valid_ready](hexk_valid_ready.md): valid/ready agent, initiator or responder,
  with delays from hexk_delay, protocol assertions, a monitor per transfer and coverage
- [hexk_pins](hexk_pins.md): interface for pins without a protocol (GPIO, straps,
  interrupts): drive, pull up or down, force, sample and wait per pin, without an agent
