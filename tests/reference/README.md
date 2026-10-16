# tests/reference

Reference testbench: a complete UVM testbench of a small but real DUT, built the way a project
builds one, with the library doing the work it is meant for. It checks the library from the
outside: the DUT is plain RTL that uses nothing of the library, and its expected behaviour comes
from the library's models (CRC, LFSR, ECC, memory model), cross-checked against fixed vectors
that a Python script computed without the library. It is also an example of how the modules fit
together in one environment, to read and to copy from.

## The DUT

`hexk_ref_dut` is a packet store. Words arrive on a valid/ready channel and are grouped into
packets; for each packet it computes a CRC-32, optionally scrambles the words with an LFSR, and
stores them in a RAM of 64 words as SECDED code words, three clock edges after it took them. A
register bus with byte strobes controls it and reads the results; an interrupt says that a
packet is done. Debug registers inject ECC errors, corrupt reads or make the DUT hang. The
header of `rtl/hexk_ref_dut.sv` is its specification: the behaviour, the timing and the register
map with the reset values.

## Where to start reading

1. `rtl/hexk_ref_dut.sv`, the header only: what the DUT does.
2. `tb/hexk_ref_tb.sv`: the DUT, the interfaces, and `hexk_tb_top_inc.svh`, which installs the
   report server, publishes the interfaces and calls `run_test()`.
3. `tests/hexk_ref_base_test.sv`: the knobs, the cfg, the scoreboards' settings, the reset, the
   main phase that starts the test's virtual sequence, and what every test checks at the end.
4. `env/hexk_ref_env.sv`: the agents, the register model, the predictor and the scoreboards, and
   how they are connected.
5. `sequences/hexk_ref_packet_vseq.sv` and `sequences/hexk_ref_vseq_base.sv`: one packet from
   programming the DUT to collecting its result; `sequences/hexk_ref_scenario_vseq.sv`: the steps
   that the scenarios of the tests share.
6. `env/hexk_ref_predictor.sv`: the reference model, and how it keeps in step with the DUT (see
   below).
7. The tests in `tests/`, each a short file that configures, picks its scenario (a virtual
   sequence in `sequences/`) and says how the run must end; the negative ones
   (`hexk_ref_hang_test`, `hexk_ref_stall_test`, `hexk_ref_corrupt_test`) show what a failure
   looks like. The scenario itself, with its own checks of the registers, is in the sequence.

## Layout

| Directory | Content |
|---|---|
| `rtl/` | the DUT |
| `agents/bus/` | the agent of the register bus and of the commit port: interface, cfg, item, driver, monitor, sequence, register adapter |
| `env/` | register model, predictor, models of the DUT, cfg and environment |
| `sequences/` | the virtual sequences: one packet from programming to collecting its result, a burst of packets without gaps, the shared steps of a scenario, and the scenario of every test (random traffic, vectors, registers, RAM, resets, ECC, faults, ...) |
| `tests/` | the base test and the tests; a test configures the environment, picks its scenario with `create_traffic()` and says how the run must end |
| `tb/` | the top module and the throttle of the input's ready |
| `vectors/` | the fixed vectors (`hexk_ref_vectors.svh`) and the script that computes them (`hexk_ref_vectors.py`) |
| `hexk_ref.f` | filelist; compile it after UVM and `src/hexk_all.f`; the top module is `hexk_ref_tb` |
| `hexk_ref_pkg.sv` | the package, which includes every class in the order they depend on each other |
| `hexk_ref_regression.txt` | the runs of `make reference` and how each must end |

## Where each library module is used

| Module | Where | What to look at |
|---|---|---|
| [`hexk_base_test`](../../docs/api/hexk_base_test.md) | `tests/hexk_ref_base_test.sv`, `tb/hexk_ref_tb.sv` | the hooks `define_knobs()` and `create_cfg()`, `fail_on_warnings`, the catcher of a negative test, the `TEST PASSED`/`TEST FAILED` line and the banner, the top include |
| [`hexk_knobs`](../../docs/api/hexk_knobs.md), [`hexk_enum_knob`](../../docs/api/hexk_knobs.md) | `tests/hexk_ref_base_test.sv` | `define_knobs()`: `ref_packets`, `ref_mode` (an enum), `ref_irq` |
| [`hexk_clk_rst`](../../docs/api/hexk_clk_rst.md) | `tests/hexk_ref_base_test.sv`, `sequences/hexk_ref_warm_reset_vseq.sv`, `env/hexk_ref_env.sv` | the reset in `reset_phase`; a warm reset with the clock stopped and changed; the reset events on which the env flushes the predictor and the scoreboards; the check of the clock period by its monitor (`check_period`) |
| [`hexk_valid_ready`](../../docs/api/hexk_valid_ready.md) | `env/hexk_ref_env.sv`, `sequences/hexk_ref_vseq_base.sv` | the input agent, its data sequence, its word and edge ports (`ap`, `cycle_ap`) |
| [`hexk_pins`](../../docs/api/hexk_pins.md) | `tb/hexk_ref_tb.sv`, `sequences/hexk_ref_fault_vseq.sv` | a strap pin that holds the input's ready low |
| [`hexk_scoreboard`](../../docs/api/hexk_scoreboard.md) | `env/hexk_ref_result_sb.sv`, `tests/hexk_ref_base_test.sv` | results keyed by packet number (`HEXK_SB_IN_ORDER_PER_KEY`, `get_key()`, `get_timestamp_ps()`, `max_wait_ps`); commits in order |
| [`hexk_meta_item`](../../docs/api/hexk_meta_item.md), [`hexk_uid`](../../docs/api/hexk_uid.md) | `env/hexk_ref_result.sv`, `env/hexk_ref_predictor.sv` | results with a timestamp, an ID and a source; latency from the moment of the prediction |
| [`hexk_delay_analysis_fifo`](../../docs/api/hexk_delay_analysis_fifo.md) | `env/hexk_ref_predictor.sv` | predicted commits released at the edge of the commit, counted in clock edges |
| [`hexk_mem_model`](../../docs/api/hexk_mem_model.md) | `env/hexk_ref_mem_model.sv`, `env/hexk_ref_predictor.sv` | the RAM with byte enables, and its end-of-test check |
| [`hexk_crc`](../../docs/api/hexk_crc.md), [`hexk_lfsr`](../../docs/api/hexk_lfsr.md), [`hexk_ecc`](../../docs/api/hexk_ecc.md) | `env/hexk_ref_predictor.sv` | the models of the DUT's CRC, scrambler and SECDED code |
| [`hexk_csr_util`](../../docs/api/hexk_csr_util.md) | `sequences/hexk_ref_vseq_base.sv`, `sequences/hexk_ref_regs_vseq.sv`, `tests/hexk_ref_regs_test.sv` | every register access, `read_check()`, `spinwait()`, `check_reset_values()`, `bit_bash()`, `exclude()` |
| [`hexk_hdl_macros`](../../docs/api/hexk_hdl_macros.md) | `sequences/hexk_ref_scenario_vseq.sv`, `sequences/hexk_ref_ecc_vseq.sv` | fault injection into the RAM by HDL path |
| [`hexk_check_macros`](../../docs/api/hexk_check_macros.md) | everywhere | `` `hexk_check_eq ``, `` `hexk_check_ne `` and the other checks |
| [`hexk_report_catcher`](../../docs/api/hexk_report_catcher.md) | `tests/hexk_ref_corrupt_test.sv` | `expect_check()`: a negative test that expects its mismatches |
| [`hexk_watchdog`](../../docs/api/hexk_watchdog.md) | `tests/hexk_ref_base_test.sv`, `env/hexk_ref_predictor.sv` | limits of the test; heartbeats per packet; the fatal of `hexk_ref_stall_test` |
| [`hexk_objection_aggregator`](../../docs/api/hexk_objection_aggregator.md) | `env/hexk_ref_env.sv` | what keeps the test running until nothing is in flight (see below); `hexk_busy_group` for the waits until the env is drained or quiet |
| [`hexk_eot_registry`](../../docs/api/hexk_eot_registry.md) | `env/hexk_ref_env.sv` | the end-of-test check of the RAM model, an object and not a component |
| [`hexk_wait_macros`](../../docs/api/hexk_wait_macros.md) | `sequences/hexk_ref_vseq_base.sv` | the wait for the interrupt with a time limit |
| [`hexk_coverage`](../../docs/api/hexk_coverage.md) | `env/hexk_ref_predictor.sv` | `` `hexk_cg_new ``: a covergroup that the knob `coverage` can switch off |
| [`hexk_rand_once`](../../docs/api/hexk_rand_once.md) | `env/hexk_ref_env_cfg.sv` | a cfg that must be randomized once |
| [`hexk_util_macros`](../../docs/api/hexk_util_macros.md) | `tb/hexk_ref_tb.sv`, `env/hexk_ref_predictor.sv`, `sequences/hexk_ref_layout.sv` | `` `hexk_vif_set `` / `` `hexk_vif_get_or_fatal ``, an indexed analysis imp, `` `hexk_constraint_no_overlap `` |
| [`hexk_rand_stream`](../../docs/api/hexk_rand_stream.md), [`hexk_plusarg`](../../docs/api/hexk_plusarg.md) | `tb/hexk_ref_ready_bfm.sv` | random numbers in a module that follow a seed on every simulator |

## The tests

| Test | What it does | Must end with |
|---|---|---|
| `hexk_ref_pass_test` | random packets; `+ref_mode=plain\|scramble\|mixed`, `+ref_irq=0` polls instead of the interrupt, `+ref_packets=<n>` | `TEST PASSED` |
| `hexk_ref_vectors_test` | the fixed packets; registers compared with the fixed values | `TEST PASSED` |
| `hexk_ref_regs_test` | reset values of the non-volatile registers; byte enables of register writes; unmapped addresses; the bit-bash sequence of UVM | `TEST PASSED` |
| `hexk_ref_control_test` | the gate of CTRL.EN, STATUS.BUSY, the edge at which DONE comes, the mask of IRQ_EN, the write-1-to-clear of IRQ.DONE (`hexk_ref_control_vseq`); once with the interrupt, once polling | `TEST PASSED` |
| `hexk_ref_mem_test` | the RAM through plain bus accesses: written whole first, then every pattern of byte enables, then partial writes to words with one and with two flipped bits | `TEST PASSED` |
| `hexk_ref_multi_test` | packets at randomized places that must not overlap, then byte writes, then every word read back against the RAM model | `TEST PASSED` |
| `hexk_ref_warm_reset_test` | a warm reset with the clock stopped and restarted at a new period, then a reset between two edges that cuts a packet with words in the pipeline; after each, every register at its reset value (the volatile ones too) and the RAM as it was | `TEST PASSED` |
| `hexk_ref_ecc_test` | errors injected through the DUT, and by HDL access at every one of the 39 positions alone and at every pair of neighbouring positions; the error counters driven to their limit | `TEST PASSED` |
| `hexk_ref_corrupt_test` | every read corrupted; the test expects exactly one mismatch per packet, and checks that CRC and CYCLES are right and that every word differs in bit 0 only | `TEST PASSED` |
| `hexk_ref_back_to_back_test` | bursts of packets without gaps, so that a packet is accepted while the one before it is still in the pipeline; the result registers against the last expected result, the RAM against the predictor; a burst of 260 packets takes STATUS.PKT_COUNT through 255 | `TEST PASSED` |
| `hexk_ref_hang_test` | the DUT never finishes a packet | `TEST FAILED` with exactly `REF_DONE`, `HEXK_SB_TIMEOUT` and `REF_MATCHED` |
| `hexk_ref_stall_test` | the DUT never takes a word | the fatal `HEXK_WATCHDOG` for inactivity, naming the busy input agent |

Every test also compares ERR with the error counters of the predictor at the end of its traffic,
so that an error that a read corrected unnoticed does not pass.

## What it does not show

The environment is the top of this testbench: it always builds its three agents and, unless a
parent assigned one, its register model. An environment meant to be reused inside a bigger one
would also take a switch per agent and pass its analysis ports up (guide rules CFG-8, REU-2).

## What it does not check

- The result registers of a packet that the next one overwrote before they could be read: in a
  burst only the last result is compared; the commits of every packet are compared all the same.
- A register access to a word of the RAM while a packet commits to it: the predictor does not
  model the order of the two at one edge, and the tests keep them apart.
- The timing of STATUS.BUSY while the pipeline drains, and DONE when HANG is set beyond the hang
  test: they are checked at a few points, not at every edge.
- Simulation on Verilator: Gate 1 lints and elaborates the testbench only.

## How a test ends

The base test raises an objection for the main phase while the test's virtual sequence runs, and
drops it when the traffic is done. That alone would end the test while results are still in flight, so
the environment registers what can still be busy with the test's `hexk_objection_aggregator`:
the input agent (a word on its way), `hexk_csr_util` (a register access), the predictor (a packet
not yet committed), and both scoreboards, which register themselves (`hold_objection` of their
cfg). The aggregator keeps the run-time phases alive until all of them are idle; then the phases
end and the check phase compares what was sent with what was matched.

In the middle of a test the same objects answer a narrower question through two
`hexk_busy_group`s of the environment: `drained` (the input agent and the predictor: every word
sent is committed), for which a burst waits before it waits for DONE, and `quiet` (`drained`, the
register accesses of `hexk_csr_util`, and an access that the bus driver holds, which is a
`hexk_objectable` too), for which a sequence waits before a reset that must lose nothing. Each wait
ends at the first look at which the group is idle, and after 2 us is an error that names who is
still busy (`REF_DRAINED`, `REF_QUIET`).

Three time limits make sure that a test ends even when the DUT does not: the wait for DONE (2 us
after the last word, `REF_DONE`), the time an expected result may wait in the result scoreboard
(50 us, `HEXK_SB_TIMEOUT`, after which it is dropped and the aggregator lets go), and the
watchdog (no heartbeat for 100 us, or 2 ms in all: a fatal that lists who is busy). The hang
test runs into the first two, the stall test into the third.

## How the scoreboards are set

- Results (`hexk_ref_result_sb`): keyed by the packet number in `HEXK_SB_IN_ORDER_PER_KEY`, so a
  missing result names its packet; at most 50 us of waiting; emptied at every reset.
- Commits (`commit_sb`): in order; `allow_unexpected` because the commit that the bus monitor saw
  and the one the predictor released reach the scoreboard at the same clock edge in an order that
  the simulator chooses, so an actual commit may come first and must wait for its expected one;
  `max_wait_ps` of 1 ns bounds that wait: shorter than any clock period of the tests, so a commit
  that waited longer came at another edge, which is an error.

## How the predictor keeps in step with the DUT

The monitors report what happens at a clock edge in an order that the simulator chooses: the
input agent's words and edges, and the bus monitor's register accesses. A predictor that used
them in the order they arrive would sometimes apply a register write to a word that the DUT
accepted before the write. So:

- the bus monitor publishes a write at the edge at which the DUT takes it, a read at its ack, and
  stamps each access with the time of the edge at which the DUT took it;
- the predictor handles the words of an edge at the next edge, when everything of that edge has
  arrived, and a register write counts only for words accepted after the write's edge;
- the predictor changes its RAM model when a word reaches the RAM, at the edge of the commit,
  and completes a packet's expected result then, with the words the RAM holds;
- the bus driver hands an item back one edge after its ack, when the monitor has published it,
  so that a test that asks the predictor something after an access sees that access.

## Running it

From the root of the repository, with the UVM sources fetched once (`make uvm_fetch`, or
`UVM_HOME` pointing to a UVM of your own) and the simulator set up as described in
[tests/README.md](../README.md) (Gate 2) and, for Questa on Windows,
[tests/unit/README.md](../unit/README.md):

```bash
make reference SIM=questa UVM=2020
```

`SIM` is `questa` or `vcs`, `UVM` is `1.2` or `2020`. `make reference` first checks the list of
runs (`hexk_ref_regression.txt`), then compiles the testbench once, with read and write access to
signals by path, and runs every line of the list. Each line is a test, a seed, plusargs, the
verdict the run must end with (`PASSED`, `FAILED`, or `NONE` when a fatal ends it before the
verdict), and what it must report: `ID:W|E|F:count` for every warning, error and fatal, and
`match=REGEX` for a line the log must contain (a space written as `\s`). Every run gets
`+hexk_knobs_strict`, so a misspelled knob such as `+ref_packtes=3` is an error, not a silent
default. `scripts/hexk_check_run.py` checks each run against its line: any other warning, error
or fatal fails the run, and so does an error that the simulator reports outside UVM (a `$error`,
a failed assertion, a runtime error), and a run that did not end normally (no complete summary
table, no `$finish`, a time limit, an exit status of the simulator other than 0). A mistake in the
list (an unreadable file, a line that is not a run, a bad expression) is reported with its line
before anything is compiled.

The logs are in `REF_OUT`, one per line of the list, named `<line>_<test>_<seed>.log` (`01_...`
for the first run).

| Control | Default | Meaning |
|---|---|---|
| `REF_REGRESSION=<file>` | `tests/reference/hexk_ref_regression.txt` | the list of runs |
| `REF_OUT=<dir>` | `build/reference_<sim>_uvm<uvm>` | where the testbench is built and the logs go |
| `REF_COMPILE=0` | `1` | reuse the build in `REF_OUT` instead of building again; the logs of earlier runs stay unless a run of the same line, test and seed replaces them |
| `REF_RUN_TIME=<n> <unit>` | `50 ms` | the simulated time after which Questa stops a run (VCS has no such limit; the watchdog of the test ends a hung test earlier on both) |
| `REF_TIMEOUT=<seconds>` | `600` | the wall-clock time after which a run is stopped, on both simulators |
| `+ref_packets=<n>`, `+ref_mode=<mode>`, `+ref_irq=0` | `10`, `mixed`, `1` | knobs of the base test (see the tests above) |
| `+hexk_ref_ready_percent=<0..100>` | `100` | share of the cycles in which the DUT may take a word; the run prints it as `REF_READY` |
| `+hexk_ref_ready_seed=<n>` | `1` | seed of the pattern of the throttle, separate from the seed of the run |
| `+UVM_VERBOSITY=UVM_HIGH` | `UVM_MEDIUM` (that of UVM) | `UVM_MEDIUM` shows every packet (`REF_PACKET`); `UVM_HIGH` also its words and every bus access (`REF_BUS`); `UVM_LOW` neither |

To run one test, give a list of one line; to run it again, for instance with more messages,
change the line and reuse the build:

```bash
echo "hexk_ref_pass_test | 7 | +ref_packets=3 +ref_mode=plain | PASSED |" > my_list.txt
make reference SIM=vcs UVM=1.2 REF_REGRESSION=my_list.txt
echo "hexk_ref_pass_test | 7 | +ref_packets=3 +ref_mode=plain +UVM_VERBOSITY=UVM_HIGH | PASSED |" > my_list.txt
make reference SIM=vcs UVM=1.2 REF_REGRESSION=my_list.txt REF_COMPILE=0
```

The fixed vectors are computed by `vectors/hexk_ref_vectors.py` (Python 3, nothing else), which
prints them; `make reference_vectors` writes them again as the repository holds them (the script,
then Verible to format the file).

The testbench runs on Questa and VCS. Verilator 5.046 does not simulate it correctly, so it is
not run there; Gate 1 elaborates it with slang against both UVM versions and lints it with
Verible and Verilator.

## Adding a test

A test configures and decides; the scenario is a virtual sequence, which another test or a
bigger testbench can start as well.

1. Unless an existing sequence is the scenario, write `sequences/hexk_ref_<name>_vseq.sv`: a class
   that extends `hexk_ref_scenario_vseq`, registered with `` `uvm_object_utils ``, with the file
   template of the others and a header that says what it does. Its `body()` sends packets
   (`send_random_packet(i)`, `send_packet(len, scramble, base)`, or a sequence of its own with
   `start_child()`) and checks what the scoreboards do not see: `check_code()` (the code word of
   a RAM word through RAW_*), `flip_code_bits()` (an error injected by HDL access),
   `wait_quiet()`, `env.check_error_counters(this)`, and the read checks of `env.csr`, each with
   the sequence as its last argument (`this`), which makes it the parent of the access;
   `hexk_ref_bus_seq::write(this, ...)` and `read(this, ...)` make a plain bus access, outside
   the register model, for byte enables or unmapped addresses. Every sequence is randomized
   before it starts, also one whose members are then set by hand (guide rule SEQ-3). Results that a later check needs, the
   sequence keeps in members (see `hexk_ref_warm_reset_vseq`).
2. Write `tests/hexk_ref_<name>_test.sv`: a class that extends `hexk_ref_base_test`, registered
   with `` `uvm_component_utils ``, with a header that says what the test shows and how it must
   end. Override `create_traffic()` to return the sequence, with its members set; the base test
   gives it the environment and the settings of the knobs (`prepare()`) and starts it.
3. To change the configuration, override `configure_test()` and change `env_cfg` there: it is
   called in the build phase after the cfg is randomized and the knobs are applied, before the
   environment is built (see `hexk_ref_back_to_back_test`); the expectations of the catcher and
   exclusions of registers go there too (`hexk_ref_corrupt_test`, `hexk_ref_regs_test`). A test
   does not override `build_phase()`. A setting of a component of the environment goes into
   `end_of_elaboration_phase()`, when the environment is built. For a different cfg class,
   override `create_cfg()`.
4. When the test makes results fail on purpose, override `expected_matches()`, and declare the
   failed checks it expects with `catcher.expect_check(id, count)` (see
   `hexk_ref_corrupt_test`).
5. A warning that the test provokes on purpose must be allowed twice: in the test, with
   `allow_warning("^ID$")` (otherwise `hexk_base_test` reports `HEXK_TEST_WARNING`), and in the
   regression line, as `ID:W:<count>` (otherwise the run checker rejects it). A message that a
   catcher demoted counts with the severity it has after the catcher.
6. Add the sequence to `hexk_ref_pkg.sv` with the other scenarios, before the base test, and
   `` `include "hexk_ref_<name>_test.sv" `` after the base test; add a line to
   `hexk_ref_regression.txt` with the verdict and the messages the run must end with.

## Adding a register

1. In the DUT: the register in `write_register()` and `register_value()`, and in the register
   map of the header, with its reset value.
2. In `env/hexk_ref_regs.sv`: its offset (`*_OFFSET`), a member, and `new_reg()` and
   `new_field()` in `build()`, with the access of each field and whether the DUT changes it by
   itself (volatile). A block of your own may extend `build()` instead; the environment locks the
   model after it.
3. If the register changes what the DUT does with packets, in `register_write()` of the
   predictor, so that the model follows it.
4. Where the map is known: `hexk_ref_regs_test` excludes from the bit bash a register whose
   bits have side effects (as DEBUG), and `hexk_ref_regs_vseq` reads unmapped addresses
   (`UNMAPPED`), which must stay unmapped. A volatile register needs nothing more:
   `hexk_ref_warm_reset_vseq` checks every one with a reset value after a reset.
