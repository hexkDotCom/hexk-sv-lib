# Integration

This page holds command lines that have been run, and says so for each. The Questa lines
were run on Questa 2024.1 on Windows, the VCS lines on VCS X-2025.06 on Linux (WSL). **The
Xcelium line has not been run**; it shows the intended shape. The library has not been
tested on Xcelium.

## Filelists

`HEXK_SV_LIB_HOME` points at the repository root; every filelist uses it.

| Filelist | Content |
|---|---|
| `src/core/hexk_core.f` | `hexk_core_pkg`: pure SystemVerilog, no UVM |
| `src/uvm/hexk_uvm.f` | `hexk_uvm_pkg`; includes the core filelist |
| `src/hexk_all.f` | everything |

Each filelist adds one include directory, its own. UVM is not in any filelist: it comes from
your tool and must be compiled first.

```bash
export HEXK_SV_LIB_HOME=/path/to/hexk-sv-lib

# VCS with the UVM 1.2 that ships with it (the unit tests of the library were run this way)
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 -f $HEXK_SV_LIB_HOME/src/hexk_all.f -f my_tb.f
# VCS with its IEEE 1800.2-2020 UVM (the same)
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-ieee-2020-2.0 -f $HEXK_SV_LIB_HOME/src/hexk_all.f -f my_tb.f
# VCS with a UVM compiled from source (what 'make test SIM=vcs' does)
vcs -full64 -sverilog -timescale=1ns/1ps +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
   -f $HEXK_SV_LIB_HOME/src/hexk_all.f -f my_tb.f $UVM_HOME/src/dpi/uvm_dpi.cc -CFLAGS -DVCS
# The HDL access macros need access to signals by path: add -debug_access+r+w+f
# Xcelium (not run yet)
xrun -uvm -f $HEXK_SV_LIB_HOME/src/hexk_all.f -f my_tb.f
```

Questa, run on 2024.1. Without further options Questa 2024.1 compiles against its built-in
UVM 1.1d, which the library does not support, so select UVM 1.2 or compile a UVM yourself:

```bash
# Questa with the UVM 1.2 library that ships with it
vlib work
vmap mtiUvm '$MODEL_TECH/../uvm-1.2'
vlog -sv -timescale 1ns/1ps +incdir+$QUESTA_HOME/verilog_src/uvm-1.2/src \
   -f $HEXK_SV_LIB_HOME/src/hexk_all.f -f my_tb.f
vsim -c my_top -do "run -all; quit -f"

# Questa with UVM compiled from source ($UVM_HOME: Accellera UVM 1.2 or uvm-core 2020.3.1);
# needs a C compiler on the PATH for the DPI code of UVM
vlib work
vlog -sv -timescale 1ns/1ps +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
   $UVM_HOME/src/dpi/uvm_dpi.cc -ccflags "-DQUESTA" \
   -f $HEXK_SV_LIB_HOME/src/hexk_all.f -f my_tb.f
vsim -c my_top -do "run -all; quit -f"
```

On Windows two more things were needed. With the shipped UVM 1.2 and no C compiler
installed, `vsim` needs `-nodpiexports`. With UVM from source and MinGW-w64 GCC, the DPI
code of UVM needs a POSIX `regex.h`, which MinGW-w64 does not have; the unit tests use
`tests/unit/mingw_compat/regex.h` (`-ccflags "-DQUESTA -I<that directory>"` and
`vsim -ldflags -lstdc++`).

The equivalent of what Gate 1 runs today, with free tools:

```bash
# Verilator lint of the core and a core-only example
verilator --lint-only -Wall --timescale 1ns/1ps -f $HEXK_SV_LIB_HOME/src/core/hexk_core.f \
   $HEXK_SV_LIB_HOME/examples/hexk_version/hexk_version_example.sv --top-module hexk_version_example

# slang elaboration of everything against UVM sources in $UVM_HOME. hexk_slang.py runs slang
# through the pyslang package (pip install pyslang); a standalone slang binary takes the
# same options.
python3 $HEXK_SV_LIB_HOME/scripts/hexk_slang.py --std=1800-2017 --timescale=1ns/1ps +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
   -f $HEXK_SV_LIB_HOME/src/hexk_all.f
```

## Another prefix

`scripts/hexk_rebrand.py` writes a copy of the repository with another prefix, for a naming
policy or for two versions of the library in one simulation:

```bash
python3 scripts/hexk_rebrand.py --prefix acme --out ../acme-sv-lib   # acme_, ACME_, acme-
python3 scripts/hexk_rebrand.py --version-suffix 2 --out ../lib-v2   # the prefix with a 2 before the underscore
```

- Everything with the prefix changes: classes, packages, interfaces, macros, defines, include
  guards, message IDs, plusargs, `HEXK_SV_LIB_HOME`, file and directory names, filelists,
  core files, documents.
- Kept as they are: `LICENSE`, `NOTICE`, the copyright lines, links, the name of the GitHub
  organisation, and the FuseSoC names (`hexkdotcom:hexk:core` and the others).
- **Known limit: FuseSoC.** Because the FuseSoC names stay, the cores of a copy have the
  names of the original. FuseSoC knows a core by its name only: with the original and a
  copy, or with two copies, in one workspace it prints
  `Replacing hexkdotcom:hexk:core:<version> in <one path> with the version found in <the other>`
  for each core and then resolves the name to the one it found last (seen with FuseSoC
  2.4.7), so the other one cannot be selected. Keep one of them per FuseSoC workspace, or
  use the filelists, which have no such conflict because their file names and
  `HEXK_SV_LIB_HOME` are rebranded.
- `NOTICE` and every file with a copyright line get the line
  `Modified from hexk-sv-lib v<version>: the prefix hexk_ was changed to acme_.`
  (Apache-2.0, section 4(b)).
- Without `--out` the copy goes to `build/rebrand/<prefix>`. A directory that is not empty
  is refused; `--force` replaces a copy that the script wrote before and touches nothing
  else. A prefix that belongs to another library (`uvm`, `ovm`, `vmm`, `svunit`, `svt`,
  `std`, `sv`) is refused.
- After writing, the script searches the copy for the old prefix and fails if one is left
  outside the keep-list.
- The same input gives the same output, so a new release is rebranded by running the
  script again.

The copy is for use, not for development. Its filelists, its `make elab`, `make test`,
`make examples` and `make smoke` work as in the original. `make pre_sim` is the gate for
changes to the library and is not meant for a copy; it does not pass there, because the
format check fails where the alignment depends on the length of a name, and the version,
style and document checks do not know the added line in the file headers. To change the
library, change the original and rebrand again.

What is run on a copy with the prefix `zzz_`: in every Gate 1 run (`make rebrand_check`),
slang elaborates it against UVM 1.2 and 2020 and its unit tests pass on Verilator 5.046.
Once, by hand (2026-10-13): its unit tests pass on Questa 2024.1 with UVM 1.2 and 2020 and
on VCS X-2025.06 with UVM 2020; its examples run and its smoke tests end as expected on
Questa and VCS with UVM 2020.

## Times

Every time that crosses the API of the library is a whole number of picoseconds in a
`longint unsigned` whose name ends in `_ps`: the timeouts of `hexk_wait_util`, the limits of
the watchdog, the poll interval of the objection aggregator, the latency of the delay FIFO,
`max_latency_ps`, `max_wait_ps` and the timestamps of the scoreboard, the poll interval and
the time limit of `hexk_csr_util`, the timestamp of `hexk_meta_item`, the
unit of `hexk_delay::wait_time`, and all times of the agents. A number of picoseconds means
the same in every scope, whatever its time unit, so the library can be compiled into a
testbench with any mix of time units.

- Write a time as `` `hexk_ps(10us) ``: the macro converts a time of the calling scope to
  picoseconds, in that scope. A plain number works too: `10_000_000` is 10 us.
- `hexk_wait_util::now_ps()` is the simulation time in picoseconds, for comparing with a
  timestamp of the library.
- An override of `hexk_scoreboard::get_timestamp_ps()` returns picoseconds, such as
  `timestamp_ps` of a meta item or `hexk_wait_util::now_ps()`, not `$time` of its own scope.
- The wait macros (`` `hexk_wait_timeout `` and the others) take a time of the calling scope,
  `10us`, and convert it with `` `hexk_ps `` in that scope; they wait whole picoseconds.
- **No time limit is reached after about 2.56 hours of simulation.** Every time limit and
  long wait of the library goes through `hexk_wait_util` (only the half periods of the clock
  of `hexk_clk_rst`, short delays on the hottest path of a simulation, are delays of their
  own), and a wait that would end after
  `hexk_wait_util::LAST_PS` ((2^63 - 1) / 1000 ps, 9 223 372 036 854 775 ps, about 2 h 34 min of
  simulated time) never ends: a timeout, a watchdog limit, a FIFO latency, a scoreboard
  `max_wait_ps` or a spin-wait limit that long is the same as none. The reason is that one
  simulator counts the time as a signed 64-bit number of steps of the simulation resolution
  and cannot schedule an event later than that; with a resolution of 1 fs, the finest there
  is, the last such time is `LAST_PS`. The library stops there on every simulator and with
  every resolution, so that a test behaves the same everywhere.
  `hexk_wait_util::ends_after_last(duration_ps, from_ps)` tells whether a wait would never end.
- `hexk_uvm_pkg` declares `timeunit 1ps; timeprecision 1ps;`, so the precision of the
  simulation is 1 ps or finer. The interfaces of the agents declare `1ns/1ps` themselves.
  `hexk_core_pkg` has no times and declares no time scale.

When any module of your design declares `timeunit` or `` `timescale ``, the tool needs a
default for the files that declare none, for example `--timescale 1ns/1ps` (Verilator,
slang) or the `-timescale` option of your simulator.

## Using the pieces from your own base test

`hexk_base_test` is optional: it is one way to set the services up, not a condition for
using them. Each of its policies can also be switched off in the constructor of a block
base test that extends it: `install_report_server = 0` keeps a report server of the
project, `stop_objection_propagation = 0` keeps the propagation of UVM, `require_checks = 0`
lets a test pass without counted checks. A project with a base test of its own does the
steps it wants itself:

```systemverilog
class my_base_test extends uvm_test;   // the base test of the project
   hexk_objection_aggregator objections;
   hexk_watchdog             watchdog;

   function void build_phase(uvm_phase phase);
      hexk_knobs knobs = hexk_knobs::get();
      super.build_phase(phase);
      // 1. Report server, if the project wants the layout and the counts of the library.
      if (hexk_report_server::get_installed() == null) begin
         hexk_report_cfg report_cfg = hexk_report_cfg::type_id::create("report_cfg");
         report_cfg.apply_plusargs();
         void'(hexk_report_server::install(report_cfg));
      end
      // 2. Knobs. Without them the delay generators ignore perf_mode and every covergroup of
      //    `hexk_cg_new is created.
      knobs.add_bit("perf_mode", 0, "every delay of the delay generators is 0");
      knobs.add_bit("coverage", 1, "the covergroups of the library are created");
      knobs.lock();
      // 3. Objection aggregator and watchdog; the env registers its busy objects with objections.
      objections          = hexk_objection_aggregator::type_id::create("objections", this);
      watchdog            = hexk_watchdog::type_id::create("watchdog", this);
      watchdog.aggregator = objections;
      // 4. End-of-test registry: created here, so that its parent is the test.
      void'(hexk_eot_registry::get());
   endfunction : build_phase

   // 5. Verdict: the check macros and the scoreboards count in hexk_check_stats; other checkers
   //    of the project can count there too with hexk_check_stats::record_pass() and record_fail().
   function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("MY_CHECKS", {"\n", hexk_check_stats::summary()}, UVM_LOW)
   endfunction : report_phase
endclass : my_base_test
```

Nothing else in the library depends on the base test: the scoreboard, the delay generators,
the agents, the memory model and the check macros work in any test.

## Reset and end of test

The library gives each part a way to drop what a reset makes invalid; the env decides when
and in which order. The order that the library is written for:

```systemverilog
// In the env: the clock and reset agent tells when the reset comes.
task run_phase(uvm_phase phase);
   forever begin
      clk_rst_agent.status.reset_asserted.wait_trigger();
      pipeline_fifo.flush();   // items on their way through the model of the pipeline are gone
      sb.on_reset();           // waiting items are dropped and counted as dropped
      mem.clear();             // only a memory whose content the reset loses
   end
endtask : run_phase
```

- The delay FIFO comes first, so that no item that was written before the reset reaches the
  predictor after the scoreboard was emptied.
- The valid/ready agents need no call: the driver ends the item it is sending and the next
  one follows the release; the monitor drops the transfer that was waiting.
- An object registered with the objection aggregator that holds a `raise()` across the
  reset drops it itself; a busy object is asked again at the next poll.
- `examples/hexk_scoreboard/hexk_scoreboard_predictor_example.sv` shows a reset in the middle
  of the traffic with a predictor and a scoreboard.

End of the test:

- The aggregator objects on `run_phase` and on the current phase of the run-time schedule
  (`reset_phase`, `main_phase`, ...). A raised or busy member holds all of them; there is no
  membership per phase. The base test stops the propagation of these objections.
- Who registers: the env registers its agents and delay FIFOs with `register()`; a scoreboard
  registers itself when its `aggregator` is assigned and `cfg.hold_objection` is set. The
  base test creates the aggregator.
- A phase ends when no member is raised or busy; the aggregator looks every
  `poll_interval_ps`. The watchdog ends a test that never gets there.
- Then `check_phase`: every component reports what it still holds (the scoreboard its
  leftovers), and the end-of-test registry calls `eot_check()` of its objects. Then
  `report_phase` (summaries) and `final_phase`, in which the base test prints the verdict.

## Items after they are published

- An item that is written to an analysis port is not changed afterwards, neither by its
  producer nor by a subscriber. Subscribers keep the handle; nothing is copied on the way.
- A producer that reuses one object for several transactions writes a clone each time. The
  monitors of the library create a new item for every write.
- The scoreboard, the delay FIFO and `hexk_meta_item` keep the handles they are given and do
  not copy; `hexk_scoreboard_cfg::clone_expected` makes the scoreboard keep clones of the
  expected items that wait. `hexk_meta_item::copy()` and `clone()` copy the wrapper and share the wrapped
  item and its ID; for an independent item, clone the item itself.
- A driver may write a response into the request item it got from the sequencer; that item
  is not published.

## When a cfg is read

| Cfg | Read | A change later |
|---|---|---|
| `hexk_report_cfg` | copied by `hexk_report_server::set_cfg()` (and `install()`) | needs another `set_cfg()` |
| `hexk_delay_cfg` | at every draw | applies to the next delay |
| `hexk_scoreboard_cfg` | `mode`, `num_streams` and `max_wait_ps` in the build phase; `hold_objection` at the end of elaboration, which registers the scoreboard with its aggregator, and when it is busy; the rest when used | applies from then on, except `mode`, `num_streams` and `max_wait_ps`; setting `hold_objection` after elaboration does not register the scoreboard |
| `hexk_clk_rst_agent_cfg` | in the build phase, at the start of the simulation and at the start of the run phase; `check_period` at every rising edge | has no effect, except clearing `check_period`, which ends the check for the rest of the run; clock sequences change the clock |
| `hexk_valid_ready_agent_cfg` | in the build phase and at the start of the simulation; `idle_data_x` at every transfer of the driver, the members of its `delay_cfg` at every draw | has no effect, except in `idle_data_x` and in the members of the `delay_cfg` object the driver took in its connect phase |

What changes during the run is not in a cfg: the reset and the clock of a clock and reset
agent are in its `status`. A copy of an agent cfg shares the interface.

## What works where

A feature marked "full" behaves the same on every simulator for which it is so marked. The
unit tests, examples and smoke tests run on Questa and VCS with UVM 1.2 and
2020; Gate 1 runs the unit tests on Verilator.

| Feature | VCS X-2025.06 | Questa 2024.1 | Verilator 5.046 |
|---|---|---|---|
| `hexk_core_pkg` | full | full | full, two-state (see X and Z) |
| UVM layer and agents with UVM 1.2 | full | full | not available: Verilator cannot compile UVM 1.2 |
| UVM layer and agents with UVM 2020 | full | full | full with `+define+UVM_HDL_NO_DPI +define+UVM_CMDLINE_NO_DPI`; constrained randomization needs the z3 solver |
| Several instances of one agent interface | full | full | not available: tasks called through a virtual interface wake on events of another instance |
| Pin model of `hexk_pins_if` (several drivers, pulls, force) | full | full | reduced: a stub (`HEXK_SIM_NO_PIN_MODEL`) that drives nothing and reports `HEXK_PINS_UNSUPPORTED` once per interface, at the first operation it cannot do |
| Functional coverage (covergroups) | full | full | not available: covergroups are ignored; `hexk_handshake_coverage::sample()` only counts |
| X and Z | full | full | not available: variables are two-state, X and Z do not occur |
| HDL access macros | full with `-debug_access+r+w+f` | full with read and write access for the module (`-voptargs=-access=rw+<module>`) | reduced: they compile and cannot reach a signal |
| Regular expressions of `hexk_regex` | POSIX with the DPI code of UVM; globs with `UVM_NO_DPI`, or with `UVM_REGEX_NO_DPI` on UVM 1.2 (UVM 2020.3.1 does not compile with `UVM_REGEX_NO_DPI` alone) | the same | the same; the regex DPI code of UVM builds |
| `soft` constraints | full | full | reduced: a constraint of `randomize() with` does not override a `soft` one, and a `soft` constraint on a member with `rand_mode(0)` is taken as hard |
| Stack traces (`HEXK_STACKTRACE`) | `$stack` | `$stacktrace` | none |
| Values of a seeded `hexk_rand_stream` | the same as on the other two | the same as on the other two | the same as on the other two |

Compile-time defines that switch a feature: `HEXK_SIM_NO_PIN_MODEL` (set by
`hexk_sim_compat.svh` on Verilator), `HEXK_UVM_REGEX_NO_DPI` (set by `hexk_uvm_compat.svh`
when UVM is compiled with `UVM_NO_DPI` or `UVM_REGEX_NO_DPI`), and the switches in the table
below. A test that needs a feature checks the define at compile time.

## FuseSoC

| Core | Content |
|---|---|
| `hexkdotcom:hexk:core` | `hexk_core_pkg` |
| `hexkdotcom:hexk:uvm` | `hexk_uvm_pkg`, depends on the core |
| `hexkdotcom:hexk:clk_rst` | clock and reset agent, depends on the UVM core |
| `hexkdotcom:hexk:valid_ready` | valid/ready agent, depends on the UVM core |
| `hexkdotcom:hexk:pins` | pins interface, depends on the UVM core |
| `hexkdotcom:hexk:sv_lib` | everything |

Add the repository as a library (`fusesoc library add hexk-sv-lib /path/to/hexk-sv-lib`) and
depend on one of the cores. UVM comes from the tool options of your own core.

A copy of the library under another prefix keeps these names; see the known limit under
"Another prefix".

## Compile-time switches

| Switch | Effect | Module |
|---|---|---|
| `+define+HEXK_NO_STACKTRACE` | `HEXK_STACKTRACE` has no effect | `hexk_sim_compat` |
| `+define+HEXK_STACKTRACE=<task>` | use this system task for stack traces | `hexk_sim_compat` |
| `+define+HEXK_MAX_WIDTH=<n>` | width of the vectors of the width-generic helpers, default 1024 | `hexk_core_pkg` |
| `+define+HEXK_NO_CHECK_STATS` | the check macros do not count executed checks | `hexk_check_macros` |
