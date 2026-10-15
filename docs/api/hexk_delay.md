# hexk_delay

## 1. Summary

Delay generator: produces delays as plain counts according to a randomizable cfg, with seven
kinds of distribution and a random stream of its own per instance.

## 2. When to use / when not to use

Use it wherever a testbench needs "wait a random while": the back-pressure of a driver or
responder, the gap between two items of a sequence, the time a model takes to answer. The
kind of delay is then a property of the cfg, which a test can constrain or replace, instead
of a `$urandom_range` call buried in a driver. Because every generator has its own stream,
adding a delay somewhere does not change the delays everywhere else.

Do not use it for protocol timing that the specification fixes; that is a constant in the
agent. Do not use it for time-outs; those are `` `hexk_wait_timeout `` and `hexk_watchdog`.
Do not use it where the count itself is stimulus that coverage must see as a field of an
item; randomize a field of the item there.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/stim/hexk_delay.sv`
- `src/uvm/stim/hexk_delay_cfg.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/stim/hexk_delay.sv`:

```systemverilog
// Creates a generator for cfg; name is used for messages and for the seed, which is derived when seed is 0.
function new(hexk_delay_cfg cfg, string name, int unsigned seed = 0);
// The next delay as a count without a unit: clock cycles, or a number of time steps.
function int unsigned next();
// Waits for next() triggers of the event; with a delay of 0 it returns at once.
task wait_cycles(event clk);
// Waits for next() times unit_ps picoseconds; with a delay of 0 it returns at once.
task wait_time(longint unsigned unit_ps);
// The name of the generator and the settings of its cfg, on one line.
function string convert2string();
```

From `src/uvm/stim/hexk_delay_cfg.sv`:

```systemverilog
// Kind of delays a hexk_delay produces.
typedef enum bit [2:0] { HEXK_DELAY_NONE, HEXK_DELAY_CONSTANT, HEXK_DELAY_UNIFORM, HEXK_DELAY_NORMAL, HEXK_DELAY_EXPONENTIAL, HEXK_DELAY_BURSTY, HEXK_DELAY_WEIGHTED } hexk_delay_mode_e;
// Creates a cfg for uniform delays of 0 to 4.
function new(string name = "hexk_delay_cfg");
// What is wrong with the values for the current mode; empty when the cfg is legal.
function string illegal_reason();
// Sum of the weights of mode HEXK_DELAY_WEIGHTED, in 64 bits so that it does not wrap; 0 when no value has a weight above 0.
function longint unsigned total_weight();
// The mode and the values that the mode uses, on one line.
function string convert2string();
// UVM hook of copy() and clone(): copies every member.
function void do_copy(uvm_object rhs);
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

`hexk_delay`:

- `next()` returns the next delay as a count without a unit. The caller decides what one
  count is: a clock cycle (`repeat (d.next()) @(vif.cb);`) or a time.
- `wait_cycles(clk)` waits for `next()` triggers of a named event. `wait_time(unit_ps)`
  waits for `next()` times `unit_ps` picoseconds. Both return at once for a delay of 0, and
  both draw exactly one delay.
- The cfg is read at every call. A change of the cfg, also of its mode, takes effect at the
  next delay; the generator can share one cfg with other generators.
- Every generator draws from its own `hexk_rand_stream`. With a `seed` other than 0, two
  generators with the same seed and cfg produce the same delays. With `seed` 0 the seed comes
  from `uvm_create_random_seed("hexk_delay", name)`: it depends on the name and on the seed
  of the simulation, not on how many random numbers other code draws.
- An illegal cfg (see below) and a null cfg are the error `HEXK_DELAY_CFG`. It is reported
  once, and every delay is 0 until the cfg is legal.
- `convert2string()` is `<name>: <cfg.convert2string()>`.

The modes of `hexk_delay_cfg`:

| `mode` | Delay | Members used |
|---|---|---|
| `HEXK_DELAY_NONE` | always 0 | none |
| `HEXK_DELAY_CONSTANT` | always `fixed_value` | `fixed_value` |
| `HEXK_DELAY_UNIFORM` | uniform over `lo` to `hi`, both included | `lo`, `hi` |
| `HEXK_DELAY_NORMAL` | normal distribution, rounded to an integer; a value below 0 becomes 0 | `mean`, `std_dev` |
| `HEXK_DELAY_EXPONENTIAL` | exponential distribution, rounded to an integer; 0 when `mean` is 0 | `mean` |
| `HEXK_DELAY_BURSTY` | bursts of delays of 0, one longer delay between two bursts | `burst_on_min`, `burst_on_max`, `burst_off_min`, `burst_off_max` |
| `HEXK_DELAY_WEIGHTED` | one of the keys of `weights`, with a probability proportional to its weight | `weights` |

- `lo` and `hi` limit the uniform mode only. The normal and exponential modes have no upper
  limit; a rare long delay is part of those distributions.
- **Bursty** is defined in calls, not in time, so it works for cycles and for times: the
  generator draws a burst length from `burst_on_min` to `burst_on_max`; that many calls of
  `next()` return 0; the next call returns a delay from `burst_off_min` to `burst_off_max`;
  then a new burst length is drawn. With a burst length of 0 every call returns a delay
  between bursts. The generator starts with a burst.
- A change of the cfg takes effect at the next call of `next()`, also in the middle of a
  burst: a burst that is going on ends when a call finds another mode, a change of one of
  the four burst limits, or an illegal cfg. The next call in bursty mode then starts a new
  burst from the limits of that moment. Without such a change a burst keeps the length that
  was drawn at its start.
- **Weighted**: `weights[value] = weight`. A weight of 0 excludes the value.
  `total_weight()` is the sum of the weights in 64 bits. A draw reads the weights twice: one
  pass adds them up, which is also the check that one is above 0, and one picks the value.
- A new cfg, and a cfg after a plain `randomize()`, has mode `HEXK_DELAY_UNIFORM` with 0 to 4:
  the defaults are soft constraints, and the caller overrides the ones it wants different
  with `randomize() with { ... }` or by assignment.
- A cfg is illegal for its mode when: uniform with `lo` above `hi`; bursty with a minimum
  above its maximum; weighted without a weight above 0; normal or exponential with `mean` or
  `std_dev` above 2147483647; and with a `mode` that is no value of `hexk_delay_mode_e`.
  The hard constraints keep a randomized cfg legal; `illegal_reason()` says what is wrong
  with one that was assigned by hand.
- `convert2string()` shows the mode and the members that the mode uses. `copy()` and
  `clone()` copy every member, the weights included.

Performance mode:

- When `honor_perf_knob` is 1, which is the default, and `hexk_knobs` has a bit knob named
  `perf_mode` that is 1, every delay is 0, whatever the mode. This is how one plusarg,
  `+perf_mode`, removes all delays of a testbench for a throughput run.
- The knob is read at the first `next()` at which it exists; knobs must be locked by then.
  When no knob `perf_mode` is defined, nothing changes.
- Set `honor_perf_knob` to 0 for a delay that the protocol needs, such as a minimum
  turn-around time.

## 5. Configuration

The members of `hexk_delay_cfg`, all `rand` except the last two:

| Member | Default | Meaning |
|---|---|---|
| `mode` | `HEXK_DELAY_UNIFORM` | Kind of delays. |
| `fixed_value` | 1 | The constant delay. |
| `lo`, `hi` | 0, 4 | Limits of the uniform mode. |
| `mean` | 2 | Mean of the normal and exponential modes. |
| `std_dev` | 1 | Standard deviation of the normal mode. |
| `burst_on_min`, `burst_on_max` | 1, 4 | Number of delays of 0 in one burst. |
| `burst_off_min`, `burst_off_max` | 1, 8 | Delay between two bursts. |
| `weights` | empty | Weight per delay value for the weighted mode. |
| `honor_perf_knob` | 1 | Whether the knob `perf_mode` makes every delay 0. |

There are no plusargs of this module. The knob `perf_mode` is defined by the testbench, or
by `hexk_base_test`, and is then set with `+perf_mode`.

`wait_time(unit_ps)` takes a whole number of picoseconds (`docs/integration.md`, "Times"):
write `` `hexk_ps(100ps) `` or `100`.

Cost: `next()` checks the cfg for the current mode on every call, because the cfg is read
live. For `HEXK_DELAY_WEIGHTED` the weights are read twice, once to add them up, which is
also the check that one is above 0, and once to pick: the cost grows with the number of
weights. `make bench` measures a uniform draw and one with 8 weights; the numbers are in
section 9.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | error |  |
| `HEXK_DELAY_CFG` | error |  |
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_delay/hexk_delay_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_example.sv
//
// Minimal use of hexk_delay: a driver loop that waits a random number of clock cycles
// between two items. The delay cfg would normally be a member of the agent cfg; here it is
// made bursty by hand: bursts of 2 to 4 items back to back, then a gap of 5 to 10 cycles.
// A second generator with the same cfg and another name gets other delays of the same kind.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_delay_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_delay;
   import hexk_uvm_pkg::hexk_delay_cfg;
   import hexk_uvm_pkg::HEXK_DELAY_BURSTY;
   `include "uvm_macros.svh"

   localparam int unsigned NUM_ITEMS = 12;

   bit            clk;
   hexk_delay_cfg gap_cfg;
   hexk_delay     gap;
   hexk_delay     response_time;

   always #5ns clk = !clk;

   initial begin
      gap_cfg               = hexk_delay_cfg::type_id::create("gap_cfg");
      gap_cfg.mode          = HEXK_DELAY_BURSTY;
      gap_cfg.burst_on_min  = 2;
      gap_cfg.burst_on_max  = 4;
      gap_cfg.burst_off_min = 5;
      gap_cfg.burst_off_max = 10;
      gap                   = new(gap_cfg, "driver.gap");
      response_time         = new(gap_cfg, "responder.time");
      `uvm_info("EXAMPLE", gap.convert2string(), UVM_NONE)

      repeat (NUM_ITEMS) begin
         // The count is used as clock cycles.
         repeat (gap.next()) begin
            @(posedge clk);
         end
         `uvm_info("EXAMPLE", $sformatf("item sent at %0t", $realtime), UVM_NONE)
         @(posedge clk);
      end

      // The same kind of count used as a time: the delay times 100 ps.
      response_time.wait_time(`hexk_ps(100ps));
      `uvm_info("EXAMPLE", $sformatf("response at %0t", $realtime), UVM_NONE)
      $finish;
   end

endmodule : hexk_delay_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **A `hexk_delay` built in a loop**, one per item. Each one starts a new stream, and with a
  seed of 0 UVM gives the same name a new seed every time, so reproducibility across code
  changes is lost. Build one generator per place that waits, in `build_phase` or `new`.
- **One generator shared by two drivers.** The delays of one driver then depend on how
  often the other asks. Share the cfg, not the generator.
- **The same explicit seed for every generator.** They then all produce the same delays,
  and the interfaces of the testbench move in step. Leave the seed at 0.
- **Using `next()` twice for one wait** ("is it 0? then wait `next()`"). The second call is
  another delay. Keep the count in a variable.
- **A delay in time units where the DUT is clocked.** A count of clock cycles keeps the
  stimulus aligned to the clock; use `wait_time` for asynchronous inputs.
- **Constraining the cfg to one value in the base test.** The point of a cfg is that tests
  can change it; set defaults with soft constraints or leave the cfg alone.
- **Clearing `honor_perf_knob` everywhere.** `+perf_mode` then does nothing. Clear it only
  where a delay is required for correctness.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.

Cost of one `next()`, measured with `make bench` on VCS X-2025.06 with UVM 2020.3.1 (Linux in WSL, 2026-10-14; two runs, which agreed within 15 percent): 0.4 us for `HEXK_DELAY_UNIFORM` from 0 to 10, 2.0 us
for `HEXK_DELAY_WEIGHTED` with 8 weights. On Questa 2024.1 (Windows): 1.0 to 1.4 us and 1.9
to 2.2 us. Verilator 5.046 treats a
soft constraint as a hard one: `randomize() with { ... }` that contradicts a default of the
cfg fails there, and the unit test for it is skipped on Verilator; set the members by
assignment on that simulator. The test runs on Questa and VCS, and so does the example
(`make examples`).
