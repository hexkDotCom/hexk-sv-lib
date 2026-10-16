# hexk_knobs

## 1. Summary

Global test knobs: a singleton that holds the few test-wide switches of a testbench, each
with a default, a help text and a plusarg, final after `lock()`.

## 2. When to use / when not to use

Use a knob for a mode that cuts across the whole testbench and that people want to change
from the command line without recompiling (guide rule TST-4): functional coverage on or off,
gate-level run, performance mode, the kind of netlist, the number of items of a smoke run.
Each knob is defined once, in the base test, with a help text, so `+hexk_knobs_help` documents
the command line of the testbench.

Knobs are **not** a replacement for cfg objects (guide rules CFG-1 to CFG-10). What
configures one agent or one env belongs in its cfg object, is randomized there and is passed
down the hierarchy. A rule of thumb: if two instances of a component could want different
values, it is not a knob. Do not use knobs to pass data between components, and do not read
them in hot paths; read once and keep the value.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/config/hexk_enum_knob.sv`
- `src/uvm/config/hexk_knob.sv`
- `src/uvm/config/hexk_knobs.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/config/hexk_enum_knob.sv`:

```systemverilog
// Defines the knob; its legal values are the texts of all members of E. Two members with the same text, such as MODE_A and MODE_a, could not be told apart on the command line: the error HEXK_KNOBS_ENUM, and the knob is not defined.
static function void add(string name, E default_value, string help_text);
// Sets the knob before hexk_knobs::lock(); a value from the command line is kept.
static function void set(string name, E value);
// Value of the knob; fatal like hexk_knobs::get_str, and an error when the knob was not defined with add().
static function E get(string name);
// Text of a member on the command line: its name in lower case without the common prefix; "" for no member.
static function string text_of(E value);
```

From `src/uvm/config/hexk_knobs.sv`:

```systemverilog
// Creates a set of knobs; use get(), which returns the one set of the simulation.
function new(string name = "hexk_knobs");
// The one set of knobs of the simulation.
static function hexk_knobs get();
// Defines an integer knob; values outside lo..hi are rejected when hi is not below lo.
function void add_int(string name, longint default_value, string help_text, longint lo = 0, longint hi = -1);
// Defines a knob that is 0 or 1; +<name> without a value sets it to 1.
function void add_bit(string name, bit default_value, string help_text);
// Defines a knob that holds any string.
function void add_str(string name, string default_value, string help_text);
// Defines a knob that holds one of the strings in legal; enum_type is set by hexk_enum_knob, which checks it.
function void add_enum_str(string name, string default_value, const ref string legal[$], input string help_text, input string enum_type = "");
// Sets an integer or bit knob before lock(); a value from the command line is kept.
function void set_int(string name, longint value);
// Sets a string or enumerated string knob before lock(); a value from the command line is kept.
function void set_str(string name, string value);
// Makes the values final and readable, prints the table, and handles +hexk_knobs_help and +hexk_knobs_strict.
function void lock();
// Value of an integer knob; fatal for an unknown name, another kind of knob, or a read before lock().
function longint get_int(string name);
// Value of a bit knob; fatal for an unknown name, another kind of knob, or a read before lock().
function bit get_bit(string name);
// The $typename of the enumeration that hexk_enum_knob defined the knob with; "" for any other or no knob.
function string enum_type_of(string name);
// Value of a string or enumerated string knob; fatal like get_int.
function string get_str(string name);
// 1 when a knob with this name is defined; may be called at any time.
function bit has(string name);
// Table of all knobs in the order of definition: name, value, source, help text.
function string help();
// Waits until lock() has been called; for code outside the UVM phases, such as initial blocks.
static task wait_locked();
// Reports every plusarg that is no knob but is one or two characters away from a knob name; returns their number.
function int unsigned check_plusargs(const ref string plusargs[$]);
// Removes every knob and the lock; for unit tests, which run many tests in one simulation.
static function void reset_for_test();
```
<!-- HEXK_GEN:END api -->

`hexk_knob` is internal. `new` exists for the UVM factory; user code calls `get()`.
`hexk_enum_knob #(E)` has static functions only and is never created. `E` is the enum type
of the knob; its default, `hexk_core_pkg::hexk_enum_util_none_e`, only gives the class one.

## 4. Behaviour and invariants

Life cycle:

- `get()` always returns the same object.
- **Definition.** `add_int`, `add_bit`, `add_str` and `add_enum_str` define a knob with its
  default and a one-line help text. The name of a knob is also the name of its plusarg, so
  `add_int("num_items", ...)` is set by `+num_items=<value>`.
- **Changes.** `set_int` and `set_str` change a value before `lock()`: `set_int` for integer
  and bit knobs, `set_str` for string and enumerated string knobs.
- **Lock.** `lock()` makes the values final. It then handles `+hexk_knobs_strict` and
  `+hexk_knobs_help`, and reports the table of knobs with `HEXK_KNOBS_TABLE`. A second
  `lock()` does nothing. `hexk_base_test` calls `lock()` at the end of its `build_phase`.
- **Reads.** `get_int`, `get_bit` and `get_str` are legal only after `lock()`. `get_str`
  reads string and enumerated string knobs.
- `wait_locked()` blocks until `lock()` has been called. It is for code outside the UVM
  phases, such as an `initial` block of the testbench top.
- `has(name)` is 1 when a knob with that name is defined. It may be called at any time, also
  before `lock()`; library code uses it to read a knob only when the testbench has it.

Where a value comes from, in order of priority:

1. **The command line.** If `+<name>` is given, the knob takes its value when it is defined,
   and a later `set_int`/`set_str` does not change it (`HEXK_KNOBS_KEPT`, an info). Integer
   values are read by `hexk_plusarg::get_int`, bit values by `hexk_plusarg::get_bit`, so
   `+<name>` without a value sets a bit knob to 1.
2. **`set_int` / `set_str`**, the latest call.
3. **The default.**

Every knob records its source, `plusarg`, `set` or `default`, for the table.

Legal values:

- An integer knob takes any value when `hi` is below `lo`, which is the default; otherwise
  only `lo` to `hi`. A bit knob takes 0 and 1. An enumerated string knob takes the strings of
  its list.
- A value that is not legal is the error `HEXK_KNOBS_VALUE`, whether it comes from the
  command line or from a set function; the knob keeps the value it had.
- So is a plusarg of an integer or bit knob that cannot be read as such, `+items=12abc` or
  `+items` without a value: the knob keeps its default, its source stays `default`, and a
  set function can still change it.
- `set_int` on a string knob, `set_str` on an integer knob and a set of a knob that does not
  exist are `HEXK_KNOBS_VALUE` as well.

Enumeration knobs:

- When the legal values of a knob are the members of an enumeration, define it with
  `hexk_enum_knob #(my_mode_e)::add(name, default_member, help_text)` and read it with
  `hexk_enum_knob #(my_mode_e)::get(name)`, which returns the member. `set(name, member)`
  sets it before `lock()`. The code that uses the knob then compares enumeration values and
  holds no strings.
- On the command line and in the table the value is the name of the member in lower case
  without the text that all member names start with up to an underscore: for
  `MY_MODE_FAST` and `MY_MODE_SLOW` the values are `fast` and `slow`, as in `+mode=slow`.
  `hexk_enum_knob #(my_mode_e)::text_of(member)` returns that text.
- Such a knob is an enumerated string knob of `hexk_knobs` under the same name: the table,
  `+hexk_knobs_help`, `+hexk_knobs_strict`, the sources and "a plusarg wins over set" work
  as for every other knob, and `get_str(name)` returns the text.
- The knob keeps the type of its enumeration: `add` stores `$typename(E)`, and
  `enum_type_of(name)` returns it ("" for a knob that `hexk_enum_knob` did not define). The
  text differs between simulators but is distinct for every type on each of them.
- `get` or `set` through another enumeration, or on a knob defined with `add_enum_str`, is
  the error `HEXK_KNOBS_TYPE`, which names both types; `set` then changes nothing and `get`
  returns the first member. Two enumerations whose members have the same names are
  different types. A value that is no member of the enumeration is the error
  `HEXK_KNOBS_VALUE`, with the first member returned. The other errors and the fatals are
  those of `get_str`.
- An enumeration with two members of the same text, such as `MODE_A` and `MODE_a` (both
  `a`), cannot be told apart on the command line: `add` reports the error
  `HEXK_KNOBS_ENUM` and does not define the knob.
- `add_enum_str` stays for a list of values that is only known at run time.

Other errors:

- A default that is not legal, a second definition of a name and an empty name are
  `HEXK_KNOBS_DEFINE`. Of two definitions the first is kept.
- A definition or a set after `lock()` is `HEXK_KNOBS_LOCKED` and changes nothing.
- A read of a knob that does not exist, with the get function of another kind, or before
  `lock()`, is the fatal `HEXK_KNOBS_READ`. For a read before `lock()` the message says that
  `hexk_base_test` locks the knobs in its `build_phase` and that a component that reads a
  knob, such as one whose covergroup `` `hexk_cg_new `` creates, is created after that.

Command line helpers:

- `+hexk_knobs_help` makes `lock()` report the table with `HEXK_KNOBS_HELP` and end the
  simulation with `$finish`.
- `+hexk_knobs_strict` makes `lock()` look at all plusargs of the command line. A plusarg
  that is not a knob, but whose name differs from the name of a knob by one or two inserted,
  deleted or replaced characters, is the error `HEXK_KNOBS_STRICT`. The difference must also
  be less than half the length of the knob name, so a knob with a name of two characters is
  never suggested. Other unknown plusargs are not errors; they may belong to the flow.
- `check_plusargs(plusargs)` is that check on a list of plusargs given by the caller; it
  returns the number of findings.

`help()`:

- A table with a header line and one line per knob in the order of definition, with the
  columns name, value, source and help text. The name and value columns are as wide as their
  longest entry.
- `no knobs are defined` when there are none.

`reset_for_test()` removes every knob and the lock. It is for unit tests that run several
tests in one simulation.

## 5. Configuration

| Plusarg | Meaning |
|---|---|
| `+<knob name>[=<value>]` | Value of that knob. |
| `+hexk_knobs_help` | Print the table of knobs and end the simulation. |
| `+hexk_knobs_strict` | Report plusargs that look like misspelled knob names. |

`+hexk_knobs_strict` needs the plusargs of the command line from UVM
(`uvm_cmdline_processor`). Where UVM is compiled without that part of its DPI code
(`UVM_CMDLINE_NO_DPI`, `UVM_NO_DPI`), the list is empty and nothing is found.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_KNOBS_DEFINE` | error |  |
| `HEXK_KNOBS_ENUM` | error |  |
| `HEXK_KNOBS_HELP` | info |  |
| `HEXK_KNOBS_KEPT` | info |  |
| `HEXK_KNOBS_LOCKED` | error |  |
| `HEXK_KNOBS_READ` | fatal |  |
| `HEXK_KNOBS_STRICT` | error |  |
| `HEXK_KNOBS_TABLE` | info |  |
| `HEXK_KNOBS_TYPE` | error |  |
| `HEXK_KNOBS_VALUE` | error |  |
<!-- HEXK_GEN:END emits -->

`HEXK_KNOBS_TABLE` has verbosity `UVM_LOW`, `HEXK_KNOBS_KEPT` has `UVM_MEDIUM`,
`HEXK_KNOBS_HELP` has `UVM_NONE`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_knobs/hexk_knobs_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_knobs_example.sv
//
// Minimal use of hexk_knobs: the base test defines three test-wide knobs, a derived test
// changes one, lock() makes them final at the end of build_phase, and the run phase reads
// them. Try +num_items=3, +gate_level, +hexk_knobs_help, or +num_itms=3 together with
// +hexk_knobs_strict on the command line. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_knobs_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_knobs;
   import hexk_uvm_pkg::hexk_enum_knob;
   `include "uvm_macros.svh"

   // Kind of netlist that is simulated; on the command line +netlist=rtl, +netlist=gate or +netlist=power.
   typedef enum {
      HEXK_EXAMPLE_NETLIST_RTL,
      HEXK_EXAMPLE_NETLIST_GATE,
      HEXK_EXAMPLE_NETLIST_POWER
   } hexk_example_netlist_e;

   class hexk_example_base_test extends uvm_test;
      hexk_knobs knobs;

      `uvm_component_utils(hexk_example_base_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      // Hook for derived tests (guide rule TST-2); it runs before the knobs are locked.
      virtual function void modify_knobs();
      endfunction : modify_knobs

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         knobs = hexk_knobs::get();
         knobs.add_int("num_items", 10, "items per sequence", 1, 1000);
         knobs.add_bit("gate_level", 0, "gate-level netlist: no backdoor access");
         hexk_enum_knob#(hexk_example_netlist_e)::add("netlist", HEXK_EXAMPLE_NETLIST_RTL, "kind of netlist");
         modify_knobs();
         knobs.lock();
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         `uvm_info("EXAMPLE", $sformatf("sending %0d items, gate_level=%0b", knobs.get_int("num_items"), knobs.get_bit(
                                        "gate_level")), UVM_NONE)
         #10ns;
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_base_test

   class hexk_example_long_test extends hexk_example_base_test;
      `uvm_component_utils(hexk_example_long_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function void modify_knobs();
         knobs.set_int("num_items", 500);
      endfunction : modify_knobs
   endclass : hexk_example_long_test

   // Code outside the UVM phases waits until the knobs are final.
   initial begin
      hexk_example_netlist_e netlist;
      hexk_knobs::wait_locked();
      netlist = hexk_enum_knob#(hexk_example_netlist_e)::get("netlist");
      if (netlist != HEXK_EXAMPLE_NETLIST_RTL) begin
         $info("netlist is %s: no backdoor access", netlist.name());
      end
   end

   initial begin
      run_test("hexk_example_long_test");
   end

endmodule : hexk_knobs_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **A knob per agent setting** (`+agent0_delay`, `+agent1_delay`). That is configuration of
  a component: it belongs in the cfg object of the agent (CFG-1, CFG-3).
- **Reading a knob in `new()` or in a constructor-time initialiser.** The knobs are not
  locked then; the read is fatal. Read in `build_phase` of a component below the test, or
  later.
- **Reading a knob per transaction.** A read is two array lookups and three checks. Read
  once and keep the value in a member.
- **A string knob for a fixed set of values.** `add_enum_str` with `get_str` makes every
  user of the knob compare strings, and a misspelled value in such a comparison compiles.
  Declare an enumeration and use `hexk_enum_knob`.
- **Defining knobs in several places.** `+hexk_knobs_help` is only complete, and
  `+hexk_knobs_strict` only reliable, when all knobs are defined before `lock()`; define them
  in the base test.
- **`$value$plusargs` next to knobs for the same purpose.** The value then has no default,
  no help text and no entry in the table. Define a knob.
- **A knob name that is the prefix of another** is fine: plusargs are matched by their whole
  name. A name of one or two characters is legal but cannot be found by
  `+hexk_knobs_strict`.
- **Using `set_int` to force a value the command line must not change.** The command line
  wins on purpose. A value that must not change is a constant, not a knob.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. `+hexk_knobs_help` and
`+hexk_knobs_strict` are not given to the unit test simulation, which all suites share; the
check behind the second is tested through `check_plusargs()`. Both plusargs, and knobs set
from the command line, were run by hand with the example on Questa 2024.1; the example
itself runs in `make examples` on Questa and VCS. On Verilator
`+hexk_knobs_strict` finds nothing, because UVM is compiled there without access to the
command line.
