# hexk_util_macros

## 1. Summary

Declaration macros for four patterns that every testbench writes again: a singleton, an
analysis imp that knows which port it is, a checked hand-over of a virtual interface, and a
constraint for address ranges that must not overlap.

## 2. When to use / when not to use

- `` `hexk_singleton_decl `` for the rare class of which exactly one object must exist, such
  as a registry or a statistics collector. Do not turn configuration into singletons; cfg
  objects are passed down the hierarchy (guide rules CFG-1 to CFG-3).
- `` `hexk_analysis_imp_indexed_decl `` for a component that receives the same kind of item
  from several sources and must know the source, typically a scoreboard with one port per
  channel. For one or two fixed sources, UVM's own `` `uvm_analysis_imp_decl `` is enough.
- `` `hexk_vif_set `` and `` `hexk_vif_get_or_fatal `` to hand a virtual interface from the
  testbench module to the test through `uvm_config_db` (guide rule CFG-4), with the check
  that must follow every get (CFG-6). They take interface types only; do not call them at
  run time.
- `` `hexk_constraint_no_overlap `` in a randomized object that holds several address or
  index ranges, such as the regions of a memory map.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/hexk_util_macros.svh`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/hexk_util_macros.svh`:

```systemverilog
// Makes TYPE a singleton: declares the static functions get(), which creates the one object, and reset_for_test().
`define hexk_singleton_decl(TYPE)
// Declares class hexk_analysis_imp_indexed_<SUFFIX> #(T, IMP): its write(t) calls write_<SUFFIX>(index, t) of IMP; get_index() gives the index. FAC-11 waived: the constructor sets m_if_mask, as the imp macros of UVM do; uvm_port_base has no public way to give an imp its interface mask.
`define hexk_analysis_imp_indexed_decl(SUFFIX)
// Puts virtual interface VIF of interface type TYPE into uvm_config_db under NAME, for the components that match PATH.
`define hexk_vif_set(TYPE, PATH, NAME, VIF)
// Gets the virtual interface NAME of interface type TYPE for this component into VIF; fatal when there is none.
`define hexk_vif_get_or_fatal(TYPE, NAME, VIF)
// Declares constraint <LO_ARRAY>_no_overlap_cstr: the ranges LO_ARRAY[i]..HI_ARRAY[i] are in order and share no value. The pragma comments silence a lint that takes the loop variables for signals without a driver.
`define hexk_constraint_no_overlap(LO_ARRAY, HI_ARRAY)
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

All four are included through `hexk_macros.svh`. None needs a semicolon after it.

`` `hexk_singleton_decl(TYPE) ``:

- Written in the body of class `TYPE`. It declares `static function TYPE get()`, which
  creates the object with `new()` on the first call and returns the same object from then
  on, and `static function void reset_for_test()`, after which `get()` creates a new object.
- `TYPE` must have a constructor that can be called without arguments.
- It also declares the local static member `hexk_singleton`.
- Handles that were taken before `reset_for_test()` keep pointing at the old object.
- It is not for components: a component needs a name and a parent (see `hexk_eot_registry`
  for a singleton component).

`` `hexk_analysis_imp_indexed_decl(SUFFIX) ``:

- Written where a class may be declared, usually in the package of the component, once per
  suffix. `SUFFIX` is written without an underscore; the macro adds it: `stream` declares
  class `hexk_analysis_imp_indexed_stream #(type T = int, type IMP = int)`, derived from
  `uvm_port_base`. Its `get_type_name()` returns the name of the class,
  `"hexk_analysis_imp_indexed_stream"`.
- The constructor is `new(string imp_name, IMP imp_owner, int imp_index = 0)`.
  `get_index()` returns `imp_index`, which cannot be changed afterwards.
- `write(t)` of the imp calls `imp_owner.write_stream(index, t)`; the component declares
  `function void write_stream(int idx, T t)`.
- It connects to an analysis port or export like any analysis imp.

`` `hexk_vif_set(TYPE, PATH, NAME, VIF) `` and `` `hexk_vif_get_or_fatal(TYPE, NAME, VIF) ``:

- `TYPE` is the interface type without the word `virtual`; the macros add it.
- `hexk_vif_set` is called from the testbench module before `run_test()`. `PATH` is the
  component, or a pattern of components, that may fetch the interface, for example
  `"uvm_test_top"`. `NAME` is the key.
- `hexk_vif_get_or_fatal` is called in `build_phase` of a component and writes the interface
  to `VIF`. When nothing was set under that name for this component, or a null interface was
  set, it reports the fatal `HEXK_VIF_GET` with the name, the type and the full name of the
  component.
- `TYPE` is a macro argument: a parameterized interface type with a comma in its parameter
  list cannot be passed.

`` `hexk_constraint_no_overlap(LO_ARRAY, HI_ARRAY) ``:

- Written in the body of a class, like a constraint. It declares the constraint
  `<LO_ARRAY>_no_overlap_cstr`: for every index, `LO_ARRAY[i] <= HI_ARRAY[i]`, and for every
  pair of indexes the two ranges share no value. Limits are inclusive.
- Both arguments are names of array members of the class, of the same size; fixed-size and
  dynamic arrays and queues work. An expression such as `cfg.lo` cannot be passed, because
  the name of the constraint is made from the first argument.
- The ranges are not ordered among each other; add a constraint for that if needed.
- The constraint can be switched off like any other:
  `obj.<LO_ARRAY>_no_overlap_cstr.constraint_mode(0)`.
- The number of pair conditions grows with the square of the number of ranges.

## 5. Configuration

None. There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_VIF_GET` | fatal |  |
<!-- HEXK_GEN:END emits -->

`HEXK_VIF_GET` is reported by the component in which the macro is written.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_util_macros/hexk_util_macros_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_util_macros_example.sv
//
// Minimal use of the macros of hexk_util_macros.svh in one small testbench:
// the testbench module hands a virtual interface to the test with `hexk_vif_set, the test
// fetches it with `hexk_vif_get_or_fatal; a scoreboard receives the items of two monitors
// through one indexed imp type and knows which stream an item came from; an address map is
// randomized with ranges that cannot overlap; a statistics object is a singleton.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

interface hexk_example_bus_if (
    input logic clk
);
   timeunit 1ns; timeprecision 1ps;
   logic [7:0] data;
endinterface : hexk_example_bus_if

module hexk_util_macros_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;

   localparam int unsigned NUM_STREAMS = 2;
   localparam int unsigned NUM_REGIONS = 3;

   // Counts items for the whole testbench.
   class hexk_example_stats;
      int unsigned items;

      `hexk_singleton_decl(hexk_example_stats)
   endclass : hexk_example_stats

   // Memory regions of a test; no two may share an address.
   class hexk_example_map extends uvm_object;
      rand bit [15:0] first_addr[NUM_REGIONS];
      rand bit [15:0] last_addr [NUM_REGIONS];

      `hexk_constraint_no_overlap(first_addr, last_addr)

      `uvm_object_utils(hexk_example_map)

      function new(string name = "hexk_example_map");
         super.new(name);
      endfunction : new
   endclass : hexk_example_map

   `hexk_analysis_imp_indexed_decl(stream)

   // Scoreboard with one imp per stream, all of one type.
   class hexk_example_scoreboard extends uvm_scoreboard;
      hexk_analysis_imp_indexed_stream #(
          .T  (int),
          .IMP(hexk_example_scoreboard)
      ) stream_imps[NUM_STREAMS];

      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
         foreach (stream_imps[i]) begin
            stream_imps[i] = new($sformatf("stream_imp_%0d", i), this, i);
         end
      endfunction : new

      function void write_stream(int idx, int t);
         hexk_example_stats stats = hexk_example_stats::get();
         stats.items++;
         `uvm_info("EXAMPLE", $sformatf("stream %0d delivered %0d", idx, t), UVM_NONE)
      endfunction : write_stream
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      virtual hexk_example_bus_if vif;
      hexk_example_scoreboard     scoreboard;
      hexk_example_map            map;
      uvm_analysis_port #(int)    monitor_ports[NUM_STREAMS];

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         `hexk_vif_get_or_fatal(hexk_example_bus_if, "bus_vif", vif)
         scoreboard = hexk_example_scoreboard::type_id::create("scoreboard", this);
         map        = hexk_example_map::type_id::create("map");
         foreach (monitor_ports[i]) begin
            monitor_ports[i] = new($sformatf("monitor_port_%0d", i), this);
         end
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         foreach (monitor_ports[i]) begin
            monitor_ports[i].connect(scoreboard.stream_imps[i]);
         end
      endfunction : connect_phase

      task run_phase(uvm_phase phase);
         hexk_example_stats stats = hexk_example_stats::get();
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         `hexk_randomize_or_fatal(map, "EXAMPLE")
         foreach (map.first_addr[i]) begin
            `uvm_info("EXAMPLE", $sformatf("region %0d: 0x%04h to 0x%04h", i, map.first_addr[i], map.last_addr[i]),
                      UVM_NONE)
         end
         @(posedge vif.clk);
         monitor_ports[1].write(11);
         monitor_ports[0].write(22);
         `uvm_info("EXAMPLE", $sformatf("%0d items counted", stats.items), UVM_NONE)
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   bit clk;
   hexk_example_bus_if bus_if (.clk(clk));

   always #5ns clk = !clk;

   initial begin
      `hexk_vif_set(hexk_example_bus_if, "uvm_test_top", "bus_vif", bus_if)
      run_test("hexk_example_test");
   end

endmodule : hexk_util_macros_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`uvm_config_db::get` without a check**, or with an `` `uvm_error `` that lets the build
  go on. The null interface then crashes the first driver that touches it, far from the
  cause. Use `` `hexk_vif_get_or_fatal ``.
- **`` `hexk_vif_set `` with `PATH` `"*"`.** Every component can then fetch the interface,
  and a typo in a name finds the wrong one. Name the component that fetches it.
- **Passing cfg objects through `uvm_config_db` "because the macros are there".** The macros
  take interface types only. Configuration is assigned top-down (CFG-2); the agents of the
  library read their cfg from `uvm_config_db` only as a fallback, for a parent that cannot
  assign it (see their contracts).
- **A singleton for convenience access to the env or a cfg.** It hides who depends on what
  and breaks reuse of the env at a higher level (guide rule TST-5).
- **One imp class per channel** written by hand or with `` `uvm_analysis_imp_decl `` for
  channel 0, 1, 2 and so on. Use one indexed imp type and an array.
- **`` `hexk_constraint_no_overlap `` on arrays of different sizes.** The constraint indexes
  both arrays with the indexes of the first.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The example runs in
`make examples` on Questa and VCS.
