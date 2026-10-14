# hexk_rand_once

## 1. Summary

Guard that reports the accidental second randomization of an object which must be
randomized exactly once, with the name of the object and a stack trace.

## 2. When to use / when not to use

Use it on objects whose random values other code reads and builds on: the top cfg of an
environment (guide rule CFG-3: one `randomize()` of the top cfg randomizes everything), the
plan of a test, a memory map. If such an object is randomized a second time, by a helper, by
a `` `uvm_do ``-style macro or by a copied line, the values change under the components that
already used them, and the test fails much later in a way that is hard to trace. The guard
makes the second randomization itself the error.

Do not use it on sequence items and other objects that are meant to be randomized again and
again. Do not use it to forbid randomization of a class altogether; clear `rand_mode` for
that.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_rand_once_macros.svh`
- `src/uvm/stim/hexk_rand_once_guard.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_rand_once_macros.svh`:

```systemverilog
// Declares the member rand_once, a pre_randomize() that reports every randomization after a successful one, and a post_randomize() that notes a successful one.
`define hexk_rand_once_guard_decl
```

From `src/uvm/stim/hexk_rand_once_guard.sv`:

```systemverilog
// Creates the guard of owner, whose full name is used in the messages.
function new(uvm_object owner);
// To be called from pre_randomize() of the owner: reports a randomization after a successful one, before the solver replaces any value.
function void on_pre_randomize();
// To be called from post_randomize() of the owner, which runs only after a successful randomization: from now on the owner counts as randomized, and a successful rerandomization uses up its allowance.
function void on_post_randomize();
// Allows the next successful randomization of the owner; later ones are errors again.
function void allow_rerandomize();
// 1 once a randomization of the owner succeeded; a failed one does not count.
function bit was_randomized();
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

The macro:

- `` `hexk_rand_once_guard_decl `` is written in the body of a class that extends
  `uvm_object`, without a semicolon. It declares the public member `rand_once`, a
  `hexk_rand_once_guard` that is created with the object, a `pre_randomize()` that calls
  `super.pre_randomize()` and then `rand_once.on_pre_randomize()`, and a `post_randomize()`
  that calls `super.post_randomize()` and then `rand_once.on_post_randomize()`.
- The macro names its types with the package, so the class needs no import for it.
- A class that needs its own `pre_randomize()` or `post_randomize()` cannot use the macro,
  because the function would be defined twice. It declares a guard member, creates it with
  `new(this)`, and calls `on_pre_randomize()` from its `pre_randomize()` and
  `on_post_randomize()` from its `post_randomize()`.
- A class derived from a guarded class is guarded as well. If it overrides
  `pre_randomize()` or `post_randomize()`, it must call the function of `super`.

The guard:

- Only a randomization that succeeds counts. `post_randomize()` runs only then, and
  `on_post_randomize()` makes `was_randomized()` 1. A randomization that fails changes
  nothing in the guard: the object is not randomized yet, or keeps its earlier values.
- Every randomization after a successful one is the error `HEXK_RAND_ONCE` with the full
  name of the owner, followed by a stack trace from `` `HEXK_STACKTRACE `` (see
  `hexk_sim_compat`). The guard reports it in `pre_randomize()`, before the solver replaces
  a value; the randomization itself goes on: `pre_randomize()` cannot stop it.
- `allow_rerandomize()` allows the next successful randomization: it is silent, and the one
  after it is an error again. A failed attempt does not use the allowance up. A call before
  the first randomization is kept for the second.
- `randomize(null)`, which only checks constraints, calls `pre_randomize()`, and
  `post_randomize()` when the constraints hold (Questa 2024.1 and VCS X-2025.06, probed
  2026-10-14). It therefore counts as a randomization when the constraints hold. Verilator
  5.046 does not compile `randomize(null)`.
- Verilator 5.046 calls `post_randomize()` also after a `randomize()` that failed (probed
  2026-10-14), against the standard. There a failed attempt counts like a successful one and
  uses up an allowance; the tests of that rule run on Questa and VCS only.
- A guard created with a null owner works and calls the object "an object without a name".

The trap:

- `+hexk_rand_once_trap=<full name>` makes the guard of the object with exactly that full
  name report its first randomization with `HEXK_RAND_ONCE_TRAP` and a stack trace. Use it
  when the error shows the second randomization and the question is who did the first.
- The full name is `get_full_name()` of the owner: for a plain `uvm_object` that is the name
  given to its constructor.

## 5. Configuration

| Plusarg | Meaning |
|---|---|
| `+hexk_rand_once_trap=<full name>` | Report the first randomization of that object with a stack trace. |

The stack trace needs a simulator with a stack-trace task; `HEXK_NO_STACKTRACE` and
`HEXK_STACKTRACE=<task>` change that (see `hexk_sim_compat`).

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_RAND_ONCE` | error |  |
| `HEXK_RAND_ONCE_TRAP` | info |  |
<!-- HEXK_GEN:END emits -->

`HEXK_RAND_ONCE_TRAP` has verbosity `UVM_NONE`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_rand_once/hexk_rand_once_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_once_example.sv
//
// Minimal use of the randomize-once guard: an environment cfg that the base test randomizes
// once. A helper further down randomizes it again by mistake, after the address map was
// already built from its values; the guard reports that with an error and a stack trace.
// Then the cfg is re-randomized on purpose, which allow_rerandomize() permits once.
// Run it with +hexk_rand_once_trap=env_cfg to see who randomizes the cfg first.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_rand_once_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;

   class hexk_example_env_cfg extends uvm_object;
      rand int unsigned num_channels;

      constraint num_channels_cstr {num_channels inside {[1 : 8]};}

      `hexk_rand_once_guard_decl

      function new(string name = "hexk_example_env_cfg");
         super.new(name);
      endfunction : new
   endclass : hexk_example_env_cfg

   hexk_example_env_cfg cfg;

   // Stands for a helper that should only read the cfg.
   function automatic void careless_helper();
      if (cfg.randomize() != 1) begin
         `uvm_error("EXAMPLE", "randomization failed")
      end
   endfunction : careless_helper

   initial begin
      cfg = new("env_cfg");
      if (cfg.randomize() != 1) begin
         `uvm_error("EXAMPLE", "randomization failed")
      end
      `uvm_info("EXAMPLE", $sformatf("building %0d channels", cfg.num_channels), UVM_NONE)

      // Reported by the guard: the channels were built from the first value.
      careless_helper();

      // Intended: the test asks for it first.
      cfg.rand_once.allow_rerandomize();
      if (cfg.randomize() != 1) begin
         `uvm_error("EXAMPLE", "randomization failed")
      end
   end

endmodule : hexk_rand_once_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`allow_rerandomize()` right before every `randomize()`.** The guard then guards
  nothing. Call it only in the one place of a test that re-randomizes on purpose.
- **Demoting `HEXK_RAND_ONCE` because "it still passes".** The values changed under
  components that used the old ones; the pass is luck.
- **A guarded sequence item.** Items are randomized for every transfer.
- **Overriding `pre_randomize()` or `post_randomize()` in a derived class without calling
  the function of `super`.** The guard of the base class is then never asked, or never
  learns that the object was randomized.
- **Several objects with the same name and `+hexk_rand_once_trap`.** All of them match. Give
  cfg objects distinct names.
- **Reading values of a guarded object before it was randomized.** The guard cannot see
  that; check `rand_once.was_randomized()` where it matters.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests count the
messages; the stack traces go to the log and are not checked. They were seen on Questa
2024.1 and VCS X-2025.06; on Verilator there is no stack trace. The example runs in
`make examples` on Questa and VCS.
