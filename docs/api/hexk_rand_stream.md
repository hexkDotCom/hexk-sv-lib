# hexk_rand_stream

## 1. Summary

Seed-stable stream of random numbers: an object that owns its seed and draws from it with
the seeded system functions `$dist_*`, so the values do not depend on thread scheduling or
on the randomization of other objects, and a seed gives the same values on every simulator.

## 2. When to use / when not to use

Use it where random values are needed outside the constraint solver and must stay the same
when unrelated code changes: back-pressure and jitter in modules, interfaces and BFMs,
delays in library classes (`hexk_delay` builds on it), distributions that constraints
express poorly (normal, exponential, Poisson).

Do not use it for class-based stimulus: declare `rand` variables and constrain them (guide
rule LNG-11). Do not use it for anything security related.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_rand_stream.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_rand_stream.sv`:

```systemverilog
// Creates a stream; scope is only a label for messages. The start value is drawn from $urandom.
function new(string scope = "");
// Restarts the stream from s: the same seed always gives the same sequence of draws.
function void seed(int unsigned s);
// Next value, uniformly distributed over all 32-bit values. It is made of two 16-bit draws of $dist_uniform, whose algorithm the standard gives; $random gives other values on some simulators for the same seed.
function int unsigned next_u32();
// Value uniformly distributed over lo to hi (inclusive).
function longint uniform(longint lo, longint hi);
// Normally distributed value with the given mean and standard deviation ($dist_normal).
function int normal(int mean, int std_dev);
// Exponentially distributed value with the given mean, which must be positive ($dist_exponential).
function int exponential(int mean);
// Poisson distributed value with the given mean, which must be positive ($dist_poisson).
function int poisson(int mean);
// True with a probability of percent in 100; 0 is never true, 100 or more is always true.
function bit chance(int unsigned percent);
// Index into weights, picked with a probability proportional to its weight.
function int unsigned pick_weighted(const ref int unsigned weights[$]);
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- Each stream holds one 32-bit seed variable. Every draw passes it to a seeded system
  function, which updates it. Nothing else influences a stream: not other streams, not
  `randomize()` calls, not the order in which threads run.
- After `seed(s)` the sequence of draws is a function of `s` and of the calls made. The same
  calls in the same order give the same values, also on another simulator.
- Every draw goes through `$dist_uniform`, `$dist_normal`, `$dist_exponential` or
  `$dist_poisson`, whose algorithms the standard gives. `next_u32()` is two draws of 16 bits
  of `$dist_uniform`; `$random(seed)` is not used, because Verilator 5.046 gives other values
  for it than Questa and VCS. `uniform()` makes its 64-bit draw from two `next_u32()` in two
  statements, high half first: the order in which the operands of a concatenation are
  evaluated is not defined, and Questa and VCS evaluate them in opposite orders.
- Without `seed()`, the start value is taken from `$urandom` once, in the constructor. It
  therefore follows the random stability of the thread that constructs the stream, and two
  streams constructed one after the other start differently.
- The `scope` given to the constructor is a label for error messages only. It does not
  influence the values.
- `uniform` is inclusive at both ends and works for any 64-bit range, including the full
  one. It makes a 64-bit draw from two 32-bit draws and takes it again when it falls into
  the part of the 64-bit range that is left over after the last whole copy of the range, so
  the reduction to the range favours no value. A draw is taken again with a probability
  below (number of values of the range) / 2^64: almost never for ranges up to 32 bits, at
  most every second time for the largest ranges.
- `normal`, `exponential` and `poisson` return what `$dist_normal`, `$dist_exponential` and
  `$dist_poisson` return for the stream's seed.
- `chance(percent)` consumes one draw whatever `percent` is, so changing a percentage does
  not shift the rest of the sequence.
- `pick_weighted` returns an index with probability weight / sum of weights. An index with
  weight 0 is never returned.
- Reproducibility across tools: Questa 2024.1, VCS X-2025.06 and Verilator 5.046 give the
  same values for a seed. A check of 1000 draws of every function showed it (2026-10-14), and
  the unit test `a_seed_gives_the_same_values_on_every_simulator` compares checksums of
  `next_u32`, `uniform`, `normal` and `pick_weighted` with fixed values on every simulator
  that runs the tests.

Illegal arguments are reported with `$error`:

| Call | Reported when | Returns |
|---|---|---|
| `uniform` | `lo` > `hi` | `lo` |
| `normal` | `std_dev` is negative | `mean` |
| `exponential`, `poisson` | `mean` is 0 or negative | 0 |
| `pick_weighted` | the queue is empty or all weights are 0 | 0 |

## 5. Configuration

None. There is no plusarg: the seed is set in code with `seed()`. `hexk_delay` (UVM layer)
derives its seed from its name and the global seed.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

`$error` text starts with `hexk_rand_stream(<scope>)::<function>:`. It has no UVM message ID
because the core layer does not use UVM. On Verilator a `$error` stops the simulation unless
`+verilator+error+limit+<n>` raises the limit.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_rand_stream/hexk_rand_stream_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_stream_example.sv
//
// Minimal use of hexk_rand_stream in a module: a ready pattern for random back-pressure, a
// weighted choice and a gap length, all from one stream with its own seed, so the pattern
// does not change when other random code in the testbench does.
// Needs only src/core/hexk_core.f.

module hexk_rand_stream_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_rand_stream;

   localparam int unsigned STREAM_SEED = 2026;
   localparam int unsigned READY_PERCENT = 70;
   localparam int unsigned CYCLES = 8;

   string           ready_pattern;
   int unsigned     burst_weights [$];
   int unsigned     burst_kind;
   longint          gap_cycles;
   hexk_rand_stream backpressure;

   initial begin
      backpressure = new("ready");
      backpressure.seed(STREAM_SEED);
      burst_weights = '{6, 3, 1};

      repeat (CYCLES) begin
         ready_pattern = {ready_pattern, backpressure.chance(READY_PERCENT) ? "1" : "0"};
      end
      $info("ready for the next %0d cycles: %s", CYCLES, ready_pattern);
      // One draw per statement: the order of the arguments of one call differs between simulators.
      burst_kind = backpressure.pick_weighted(burst_weights);
      gap_cycles = backpressure.uniform(1, 4);
      $info("burst kind %0d, then a gap of %0d cycles", burst_kind, gap_cycles);
   end

endmodule : hexk_rand_stream_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **One stream shared by several consumers.** Adding a draw in one consumer then changes the
  values of all the others, which is exactly what a stream is meant to prevent. Give each
  consumer its own stream.
- **Expecting reproducibility without `seed()`.** An unseeded stream starts from `$urandom`.
  Call `seed()` with a value derived from the test seed and something stable, such as a
  hash of the instance name.
- **The same seed for every stream.** All streams then produce the same sequence, and
  "independent" interfaces move in lockstep. Derive a different seed per stream.
- **`$urandom_range` next to a stream in a BFM.** It draws from the thread's generator, so
  the BFM's behaviour depends on scheduling again. Use the stream for every draw.
- **Comparing against stored random values.** The numbers for a seed are the same on the
  simulators that were checked, but they changed between versions of the library once and
  may again. Test properties (range, share, mean), not exact values.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
