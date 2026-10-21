# hexk_valid_ready

## 1. Summary

Valid/ready agent: drives or answers a data channel with a valid/ready handshake, as an
initiator or as a responder, with random gaps and back-pressure, protocol assertions in the
interface, a monitor that publishes every transfer, and handshake coverage.

## 2. When to use / when not to use

Use it for every channel of a DUT that moves one word of data per clock cycle in which
`valid` and `ready` are both 1: a stream input or output, a request or a response channel,
one channel of a larger protocol. Use an initiator on a DUT input, a responder on a DUT
output, and a passive agent on a channel between two blocks of the DUT. The monitor feeds a
scoreboard through `ap`. It is also the example of a complete agent built on the library:
copy its structure for an agent of your own protocol.

Do not use it for a protocol with more than valid, ready and data: packet boundaries, byte
enables, IDs or responses with a status belong in an agent of that protocol, which can use
this one as a pattern. Pack side-band signals that travel with the data into `data` when
they have no meaning of their own for the handshake. Do not use it where `ready` may only
come after `valid` or the other way round: this agent allows both, as AXI-Stream does.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/agents/hexk_valid_ready/hexk_valid_ready_agent.sv`
- `src/agents/hexk_valid_ready/hexk_valid_ready_agent_cfg.sv`
- `src/agents/hexk_valid_ready/hexk_valid_ready_driver.sv`
- `src/agents/hexk_valid_ready/hexk_valid_ready_if.sv`
- `src/agents/hexk_valid_ready/hexk_valid_ready_item.sv`
- `src/agents/hexk_valid_ready/hexk_valid_ready_monitor.sv`
- `src/agents/hexk_valid_ready/hexk_valid_ready_pkg.sv`
- `src/agents/hexk_valid_ready/sequences/hexk_valid_ready_data_seq.sv`
- `src/agents/hexk_valid_ready/sequences/hexk_valid_ready_random_seq.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/agents/hexk_valid_ready/hexk_valid_ready_agent.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the agent; the children, and with the monitor the ports, come in build_phase.
function new(string name, uvm_component parent);
// UVM callback: checks the cfg and its interface, creates the monitor, the coverage and, in active mode, the rest.
function void build_phase(uvm_phase phase);
// UVM callback: connects the coverage to the records of the monitor, and the driver to the sequencer.
function void connect_phase(uvm_phase phase);
// UVM callback: tells the interface which side this agent drives and whether its protocol assertions are on.
function void start_of_simulation_phase(uvm_phase phase);
// UVM hook: the mode of the cfg.
function uvm_active_passive_enum get_is_active();
// hexk_objectable: 1 while the driver holds an item of a sequence (also during its delay), or while a transfer is offered and not yet accepted. A responder that waits for traffic without an item is not busy.
virtual function bit is_busy();
// hexk_objectable: whether the driver holds an item, and for how long the transfer has waited.
virtual function string busy_reason();
```

From `src/agents/hexk_valid_ready/hexk_valid_ready_agent_cfg.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates a cfg for an active initiator with uniform delays of 0 to 4, checks and coverage.
function new(string name = "hexk_valid_ready_agent_cfg");
// The mode, the role, the switches and the delays, on one line.
function string convert2string();
// UVM hook of copy() and clone(): copies every member; the copy shares the interface and has a delay_cfg of its own, a clone of that of the original with its class, or none when the original has none.
function void do_copy(uvm_object rhs);
// UVM hook of compare(): compares every member, the delay_cfg by its members; the interfaces must be the same.
function bit do_compare(uvm_object rhs, uvm_comparer comparer);
// UVM hook of print() and sprint(): every member; the interface as set or null.
function void do_print(uvm_printer printer);
```

From `src/agents/hexk_valid_ready/hexk_valid_ready_driver.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the driver.
function new(string name, uvm_component parent);
// UVM callback: takes the interface from the cfg, which the agent has checked, and creates the delay generator.
function void connect_phase(uvm_phase phase);
// UVM callback: drives the side of the channel that the role of the cfg names, until the phase ends.
task run_phase(uvm_phase phase);
// 1 while the driver holds an item of a sequence: from get_next_item() to item_done(), also during its delay.
function bit holds_item();
```

From `src/agents/hexk_valid_ready/hexk_valid_ready_if.sv`:

```systemverilog
// Says whether an agent drives the side of an initiator (1) or of a responder (0); the agents call it at time 0. A side that is given back takes the values of the DUT.
function automatic void set_driver(bit as_initiator, bit drives);
// Switches the protocol assertions on or off.
function automatic void set_checks(bit enable);
// 1 while the protocol assertions are on.
function automatic bit get_checks();
// 1 when valid or ready has no level now, or a bit of data while valid is 1: what the assertion known_a checks.
function automatic bit has_unknown();
// 1 while the reset is asserted or has no level.
function automatic bit in_reset();
// Number of times the reset was asserted so far.
function automatic int unsigned get_reset_count();
// Waits until the reset is released; returns at once when it is.
task automatic wait_reset_released();
// Waits until the reset is asserted; returns at once when it is.
task automatic wait_reset_asserted();
// Initiator: no transfer is offered. With data_x the data is X, otherwise it keeps its value.
task automatic idle_initiator(bit data_x);
// Initiator: offers one word after delay clock cycles and returns at the rising edge of its transfer. valid stays 1 at the end: the caller offers the next word or calls idle_initiator() in the same time step. waited is the number of rising edges at which valid was 1 and ready was not.
task automatic send(input logic [DATA_WIDTH-1:0] word, input int unsigned delay, input bit data_x, output int unsigned waited);
// Responder: no transfer is accepted.
task automatic idle_responder();
// Responder: keeps ready 0 for delay clock cycles, then 1, and returns at the rising edge of the transfer with the word. ready stays 1 at the end: the next call takes it back when it has a delay. waited is the number of rising edges since the call at which valid was 1 and ready was not: what send() returns for the same transfer and what the monitor counts.
task automatic receive(input int unsigned delay, output logic [DATA_WIDTH-1:0] word, output int unsigned waited);
// Monitor: waits for the next rising edge of the clock and returns what the channel holds there. A valid or a ready without a level counts as 0.
task automatic sample (output bit reset_active, output bit valid_seen, output bit ready_seen, output logic [DATA_WIDTH-1:0] data_seen);
```

From `src/agents/hexk_valid_ready/hexk_valid_ready_item.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates an item; the delay is that of the cfg until it is randomized or assigned.
function new(string name = "hexk_valid_ready_item");
// The word and the timing of the transfer, on one line.
function string convert2string();
// UVM hook of copy() and clone(): copies every member.
function void do_copy(uvm_object rhs);
// UVM hook of compare(): the words are equal, X and Z bits included; the timing is not compared.
function bit do_compare(uvm_object rhs, uvm_comparer comparer);
// UVM hook of print() and sprint(): the word, the timing and the status.
function void do_print(uvm_printer printer);
// UVM hook of pack(): every member, in the order of the declarations; X and Z bits of the word become 0.
function void do_pack(uvm_packer packer);
// UVM hook of unpack(): the members in the order in which do_pack() wrote them.
function void do_unpack(uvm_packer packer);
```

From `src/agents/hexk_valid_ready/hexk_valid_ready_monitor.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the monitor and its ports.
function new(string name, uvm_component parent);
// UVM callback: takes the interface from the cfg; the agent has checked both.
function void connect_phase(uvm_phase phase);
// UVM callback: looks at the channel at every rising edge of the clock. A reset that came and went between two rising edges is not seen there: the interface counts the assertions of the reset, and a count that changed stands for such a reset.
task run_phase(uvm_phase phase);
// Number of clock cycles for which a valid has waited for ready so far; 0 when none waits, during a reset and after a reset until the next rising edge.
function int unsigned num_waiting_cycles();
```

From `src/agents/hexk_valid_ready/hexk_valid_ready_pkg.sv`:

```systemverilog
// Which side of the channel an active agent drives.
typedef enum bit { HEXK_VALID_READY_INITIATOR, HEXK_VALID_READY_RESPONDER } hexk_valid_ready_role_e;
```

From `src/agents/hexk_valid_ready/sequences/hexk_valid_ready_data_seq.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the sequence without words.
function new(string name = "hexk_valid_ready_data_seq");
// Sends one item per word; returns at the transfer of the last one.
task body();
```

From `src/agents/hexk_valid_ready/sequences/hexk_valid_ready_random_seq.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the sequence.
function new(string name = "hexk_valid_ready_random_seq");
// Sends num_items items with random words; returns at the transfer of the last one.
task body();
```
<!-- HEXK_GEN:END api -->

Types, signals and members that the listing above does not show. `DATA_WIDTH` (default 32)
is a parameter of the interface and of every class. `compare()`, `pack()` and the printout of
an item go through the bit stream of UVM, `UVM_MAX_STREAMBITS` bits (4096 unless your flow
defines it larger): a wider `DATA_WIDTH` is compared, packed and printed in its low 4096 bits
only. The driver and the monitor have no such limit.

| Interface `hexk_valid_ready_if #(DATA_WIDTH) (input logic clk, input logic rst_n)` | |
|---|---|
| `logic valid`, `logic ready`, `logic [DATA_WIDTH-1:0] data` | The channel: what the agents and the DUT see. Connect the inputs of the DUT to them. |
| `logic ext_valid`, `logic [DATA_WIDTH-1:0] ext_data` | What a DUT drives on the side of an initiator; the testbench assigns them. |
| `logic ext_ready` | What a DUT drives on the side of a responder; the testbench assigns it. |
| `clocking mon_cb @(posedge clk)` | Samples `valid`, `ready` and `data`, for testbench code. |

| `hexk_valid_ready_role_e` | An active agent |
|---|---|
| `HEXK_VALID_READY_INITIATOR` | drives `valid` and `data` |
| `HEXK_VALID_READY_RESPONDER` | drives `ready` |

| Member of `hexk_valid_ready_item` | Meaning |
|---|---|
| `rand logic [DATA_WIDTH-1:0] data` | The word of the transfer: what an initiator sends, and what a responder or the monitor saw. |
| `rand int delay_cycles` | Clock cycles before the driver offers the transfer; below 0, the default, the driver takes the delay of the cfg. |
| `int unsigned wait_cycles` | Set by the monitor and by a driver: clock cycles for which `valid` waited for `ready`. |
| `bit aborted` | Set by a driver: 1 when a reset ended the item before its transfer. |
| `uvm_status_e status` | Set by a driver and by the monitor: `UVM_IS_OK`; `UVM_NOT_OK` when a reset ended the item; `UVM_HAS_X` when the word that a responder took or the monitor saw has an X or Z bit (guide rule TRN-6). Not compared. |

| Member of a sequence | Default | Meaning |
|---|---|---|
| `hexk_valid_ready_random_seq::num_items` (`rand`) | 1 | Number of transfers of random data. |
| `hexk_valid_ready_data_seq::words` | empty | The words to send, the first one first; set by the starter. |
| `hexk_valid_ready_data_seq::delay_cycles` (`rand`) | -1 | The delay of every item; below 0 the driver takes the delays of the cfg. |

The agent has the members `cfg`, `sqr`, `drv`, `mon`, `cov`, `ap` and `cycle_ap`; the members
of the cfg are in section 5. The agent implements `hexk_uvm_pkg::hexk_objectable`.

Of the interface, a testbench uses the signals and the clocking block of the first table.
The tasks and functions and the other variables are for the driver and the monitor of the
agent, which drive and sample the channel through them (guide rule IFC-8); do not call or
write them from testbench code. The members `cfg` of the driver and of the monitor are
assigned by the agent. `build_phase`, `connect_phase`,
`start_of_simulation_phase` and `run_phase` are UVM callbacks, and `body` is called by UVM.

Compile `src/uvm/hexk_uvm.f` and then `src/agents/hexk_valid_ready/hexk_valid_ready.f`, or
`src/hexk_all.f` for everything. The interface is compiled outside the package; import the
classes from `hexk_valid_ready_pkg`.

## 4. Behaviour and invariants

The channel:

- A transfer happens at every rising edge of `clk` at which `valid` and `ready` are both 1
  and `rst_n` is 1. `data` of that edge is the word. `valid` and `ready` do not depend on
  each other: either may come first.
- `clk` and `rst_n` are ports of the interface. The reset is active low; connect an
  inverter for a DUT with a reset that is active high. The agent does not generate either;
  `hexk_clk_rst` does, or the testbench.
- **Connecting a DUT.** The inputs of the DUT are connected to `valid`, `data` and `ready`.
  What the DUT drives is assigned to the `ext_` inputs: its `ready` to `ext_ready` on a
  channel with an initiator agent, its `valid` and `data` to `ext_valid` and `ext_data` on a
  channel with a responder agent, all three on a channel that an agent only watches. On a
  side that no active agent drives, `valid` and `data`, or `ready`, follow the `ext_`
  inputs, one delta cycle later. The `ext_` inputs of a side that an agent drives are not
  used.
- The drivers change their signals in the time step of a rising edge, after the edge, so
  the DUT sees a change at the following edge. The monitor samples at the rising edge and
  sees what the DUT sees.
- An agent, its cfg and its interface have the same `DATA_WIDTH`. It is at least 1.

Initiator (`role` `HEXK_VALID_READY_INITIATOR`, active):

- Without an item `valid` is 0. For an item the driver waits for the delay of the item,
  counted in clock cycles from the end of the transfer before it or, when the driver was
  idle, from the first rising edge after the arrival of the item; then it drives `valid` 1
  and `data`, and keeps both until the edge at which `ready` is 1. With a delay of 0 an item
  that follows another without a pause is transferred in the next cycle: `valid` stays 1
  (back to back).
- The item is done at the edge of its transfer; `wait_cycles` then says at how many edges
  `valid` waited for `ready`.
- With `idle_data_x`, `data` is X while `valid` is 0, so that a DUT that looks at `data`
  without `valid` shows it; without, `data` keeps the last word.

Responder (`role` `HEXK_VALID_READY_RESPONDER`, active):

- For every transfer the driver keeps `ready` 0 for the delay, counted in clock cycles
  from the end of the transfer before it or from the first rising edge after the release of
  the reset, then drives `ready` 1 and keeps it until the edge of the transfer. A delay of 0
  keeps `ready` 1.
- A responder needs no sequence: without an item it takes every delay from the cfg and
  answers for ever. An item on its sequencer stands for one transfer: its `delay_cycles`
  replaces the delay of the cfg for that transfer, and when the transfer is done the item
  holds the word that was received and, in `wait_cycles`, at how many edges since the start
  of that transfer `valid` was 1 and `ready` was not. That includes the first edge after
  the release of the reset, at which `ready` is still 0, and is what the monitor counts
  for the same transfer. The driver looks for an item at the start of each transfer.

Delays:

- The delay of a transfer is `delay_cycles` of its item when that is 0 or above. Below 0,
  which is the default of the item and of the sequences, the driver draws it from a
  `hexk_delay` with `cfg.delay_cfg`: uniform 0 to 4 unless the test changes the cfg.
  `delay_cfg` is created with the cfg and randomized with it; the knob `perf_mode` makes
  every drawn delay 0 (see `hexk_delay`). The driver takes the `delay_cfg` object in its
  connect phase: a change to that object applies to the next draw, while another object
  assigned to `cfg.delay_cfg` later is not used.
- The draws come from a random stream of the driver that is seeded from the full name of
  the driver, so they do not depend on other randomization.

Reset:

- While `rst_n` is 0 an initiator drives `valid` 0 and a responder `ready` 0, in the time
  step in which the reset is asserted, also between clock edges.
- An item that has not had its transfer when the reset is asserted is ended: it is done
  with `aborted` 1. An item that arrives during a reset waits; the driver goes on when the
  reset is released. A sequence that must not go on after a reset is ended by the test.
  The sequences of the library do not look at `aborted`: they send all their items, and
  "returns at the transfer of the last one" means, after a reset, at the end of the last
  item, transferred or aborted.
- The monitor reports no transfer during a reset, forgets a transfer that was waiting, and
  marks the first edge after a reset began in its record on `cycle_ap` (`reset_began`). It looks at the channel at the rising edges of the
  clock; a reset that is asserted and released between two edges counts as well, because
  the interface counts the assertions of the reset (`get_reset_count()`) and the monitor
  compares that count at every edge.

Monitor, in every mode:

- Every transfer is one item on `ap` with `data`, `wait_cycles` and `status` (`UVM_HAS_X`
  when `data` has an X or Z bit); `delay_cycles` is not set. A `valid` or `ready` that is X
  or Z counts as 0. With `has_checks` 0, when the assertions of the interface are off, the
  monitor reports in every clock cycle out of reset what the assertion `known_a` would: the
  error `HEXK_VALID_READY_UNKNOWN` for a `valid` or `ready` without a level, or `data` with
  an X or Z bit while `valid` is 1. With `has_checks` 1 only the assertion reports it. The monitor creates a new item for
  every transfer; subscribers keep it and do not change it (`docs/integration.md`, "Items
  after they are published").
- Every rising edge of the clock, also during a reset, is one `hexk_handshake_cycle_t` on
  `cycle_ap`: `reset_began` (a reset began since the edge before, also one that came and went
  between the two), `in_reset`, `valid` and `ready`. It is a packed struct, so nothing is
  created per edge, and a port without subscribers costs one call.
- With `has_coverage` the agent has a `hexk_handshake_coverage` named `cov`, connected to
  `cycle_ap` like any other subscriber; the monitor does not know it. Other coverage or
  checkers of the handshake connect to `cycle_ap` of the agent.
- The agent is busy (`hexk_objectable`) while its driver holds an item of a sequence, from
  `get_next_item()` to `item_done()` and so also during the delay before the transfer, and
  from the edge at which `valid` is 1 without `ready` until the transfer or a reset.
  `busy_reason()` names both. A responder that answers without an item is not busy while
  it waits for traffic. Register the agent with `hexk_objection_aggregator` so that a phase
  does not end in the middle of a handshake or with an item still in the driver.

The message of `HEXK_VALID_READY_UNKNOWN` prints the values that the assertion sampled at
the edge, not the ones the signals have when the message is written.

Protocol assertions, in the interface, with `has_checks` and out of reset:

- `valid` that was 1 without `ready` is still 1 at the next edge
  (`HEXK_VALID_READY_VALID_DROPPED`).
- `data` does not change while `valid` waits for `ready`
  (`HEXK_VALID_READY_DATA_CHANGED`).
- `valid` and `ready` are not X or Z, and `data` has no X or Z bit while `valid` is 1
  (`HEXK_VALID_READY_UNKNOWN`), at every edge.
- They hold for both sides of the channel, also for a DUT that drives it, and are errors of
  the root reporter of UVM. Each message starts with the hierarchical name of the assertion
  in its interface instance (`%m`), so that it tells which channel broke the rule. Every agent on an interface sets the switch of that interface at
  the start of the simulation: give the agents of one interface the same `has_checks`.

The agent:

- `cfg`, with `cfg.vif`, is assigned by the parent before the build phase. A parent that
  cannot see the type of the agent, such as a reusable environment, sets it instead with
  `uvm_config_db#(hexk_valid_ready_agent_cfg#(W))::set(this, "<agent path>", "cfg", cfg)`;
  the agent looks there only when nothing was assigned (CFG-4). A `cfg` that is still null,
  or a null `cfg.vif`, in the build phase is the fatal `HEXK_VALID_READY_CFG`.
- `ap` and `cycle_ap` of the agent are the ports of its monitor (guide rule CMP-10): the agent
  sets them in its build phase, when it creates the monitor, so a consumer connects to them in
  its connect phase; before the build phase they are null. It builds `mon` always,
  `cov` with `has_coverage`, and `sqr` and `drv` in active mode. `get_is_active()` returns
  `cfg.is_active`. An
  active agent takes its side of the interface at the start of the simulation.
- An initiator and a responder agent may share one interface, for a channel inside the
  testbench. Two active agents with the same role on one interface are not allowed.
- Driver and monitor work in the run phase only; the sequences raise no objections. The
  members of the sequences start at their defaults, which are also soft constraints, so a
  sequence works with or without `randomize()`. A sequence sends one item per transfer; a
  failed randomization of an item is the fatal `HEXK_VALID_READY_RAND`. `hexk_valid_ready_data_seq` randomizes an item only when the
  factory gives a class derived from `hexk_valid_ready_item`, so that its own random fields
  get values; a plain item is not randomized, since the sequence assigns both its random
  fields. A randomization costs several times as much as the rest of an item. The sequence
  asks the factory once when it starts, for `<sequencer path>.req`, as `create()` does, and
  makes every item of that start of the class it gave; an override set while it runs counts
  from its next start. A failed cast of such an item is the fatal `HEXK_VALID_READY_RAND`.
  The sequence assigns `data` and `delay_cycles` after the randomization, so a constraint of a
  derived item on either of them, or one that ties another field to them (a parity bit of
  `data`), is not kept: such an item needs a sequence of its own that randomizes with the
  values as constraints.
- The sequences create their items as `<sequencer path>.req`, and the monitor as
  `<monitor path>.item`, so that a factory instance override can change the items of one
  agent: `item_t::type_id::set_inst_override(my_item_t::get_type(), "*.in_agent.sqr.req")`.

Items and cfg:

- `compare()` of two items looks at `data` only and goes through the comparer:
  a difference is noted as one of the field `data`, which the default `compare_items()` of
  `hexk_scoreboard` prints. X and Z bits must match.
- `print()` and `sprint()` show `data`, `delay_cycles`, `wait_cycles` and `aborted`.
  `pack()` writes every member in the order of the declarations and `unpack()` reads them
  back; X and Z bits of the word are packed as 0. `get_type_name()` is
  `hexk_valid_ready_item`, without the parameter; the same holds for the cfg and the
  sequences.
- `copy()` and `clone()` of the cfg give the copy a `delay_cfg` of its own: a clone of the
  original one, of its class, or none when the original has none. `convert2string()` says
  `none` then. A copy of an item or a cfg from an object of another class is the fatal
  `HEXK_COPY_TYPE` and changes nothing.

Simulators:

- One interface with an initiator and a responder agent on it, or with one agent and a DUT,
  simulates on Verilator 5.046 as on Questa. Several instances of the interface in one
  simulation do not (see `hexk_clk_rst`), which a DUT with an input and an output channel
  needs.
- Verilator cannot override a soft constraint with a constraint of the call: assign
  `num_items` or `delay_cycles` of a sequence after a plain `randomize()` there.

## 5. Configuration

| Member of `hexk_valid_ready_agent_cfg` | Default | Meaning |
|---|---|---|
| `is_active` | `UVM_ACTIVE` | `UVM_PASSIVE`: monitor and coverage only. |
| `role` | `HEXK_VALID_READY_INITIATOR` | Which side an active agent drives. |
| `vif` | null | The interface of this agent; mandatory. |
| `delay_cfg` (`rand`) | uniform 0 to 4 | The delays of the driver; a `hexk_delay_cfg`. |
| `idle_data_x` | 1 | 1: an initiator drives X on `data` while `valid` is 0. |
| `has_checks` | 1 | 0: the protocol assertions of the interface are off; the monitor then reports `HEXK_VALID_READY_UNKNOWN` itself. |
| `has_coverage` | 1 | 0: no coverage component. |

| Parameter | Default | Meaning |
|---|---|---|
| `DATA_WIDTH` | 32 | Width of `data`, at least 1. |

There are no plusargs and no compile-time switches.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | fatal |  |
| `HEXK_VALID_READY_CFG` | fatal |  |
| `HEXK_VALID_READY_DATA_CHANGED` | error |  |
| `HEXK_VALID_READY_RAND` | fatal |  |
| `HEXK_VALID_READY_UNKNOWN` | error |  |
| `HEXK_VALID_READY_VALID_DROPPED` | error |  |
<!-- HEXK_GEN:END emits -->

| ID | Meaning |
|---|---|
| `HEXK_VALID_READY_CFG` | The agent has no cfg, assigned or in `uvm_config_db`, or the cfg has no interface. |
| `HEXK_VALID_READY_DATA_CHANGED` | `data` changed while `valid` waited for `ready`. |
| `HEXK_VALID_READY_RAND` | A sequence could not randomize an item. |
| `HEXK_VALID_READY_UNKNOWN` | `valid`, `ready` or, with `valid`, `data` is X or Z. |
| `HEXK_VALID_READY_VALID_DROPPED` | `valid` went to 0 before its transfer. |
| `HEXK_COPY_TYPE` | `copy()` of an item or a cfg from an object of another class; nothing is copied. |

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_valid_ready/hexk_valid_ready_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_example.sv
//
// Minimal use of hexk_valid_ready: a DUT with a valid/ready channel at its input and one at
// its output, here one register stage. An initiator agent sends random words into the DUT
// with random gaps; a responder agent takes them from its output with random back-pressure.
// A hexk_scoreboard compares what the two monitors saw, in order. The inputs of the DUT are
// connected to the channel signals of the interfaces, its outputs to their ext_ inputs.
// The scoreboard and the agent at the output hold the phase through the aggregator until
// the last word has left the DUT, or the scoreboard reports a word that is overdue; the test
// checks that every word was compared.
// Needs UVM, src/uvm/hexk_uvm.f and src/agents/hexk_valid_ready/hexk_valid_ready.f.

`include "hexk_macros.svh"

module hexk_valid_ready_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent_cfg;
   import hexk_valid_ready_pkg::hexk_valid_ready_item;
   import hexk_valid_ready_pkg::hexk_valid_ready_random_seq;
   import hexk_valid_ready_pkg::HEXK_VALID_READY_RESPONDER;
   `include "uvm_macros.svh"

   localparam int unsigned WIDTH = 16;
   localparam int unsigned NUM_WORDS = 8;

   bit clk;
   bit rst_n;

   always #5ns clk = !clk;

   initial begin
      #22ns;
      rst_n = 1'b1;
   end

   hexk_valid_ready_if #(
       .DATA_WIDTH(WIDTH)
   ) in_if (
       .clk  (clk),
       .rst_n(rst_n)
   );
   hexk_valid_ready_if #(
       .DATA_WIDTH(WIDTH)
   ) out_if (
       .clk  (clk),
       .rst_n(rst_n)
   );

   // The DUT: one register stage. It takes a word when it is empty or its word leaves in the same cycle.
   logic             full;
   logic [WIDTH-1:0] held;

   assign in_if.ext_ready  = !full || out_if.ready;
   assign out_if.ext_valid = full;
   assign out_if.ext_data  = held;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         full <= 1'b0;
      end else if (in_if.valid && in_if.ready) begin
         held <= in_if.data;
         full <= 1'b1;
      end else if (out_if.ready) begin
         full <= 1'b0;
      end
   end

   class hexk_example_test extends uvm_test;
      typedef hexk_valid_ready_item#(WIDTH) item_t;

      hexk_valid_ready_agent_cfg #(WIDTH) in_cfg;
      hexk_valid_ready_agent_cfg #(WIDTH) out_cfg;
      hexk_valid_ready_agent #(WIDTH)     in_agent;
      hexk_valid_ready_agent #(WIDTH)     out_agent;
      hexk_scoreboard_cfg                 sb_cfg;
      hexk_scoreboard #(item_t)           sb;
      hexk_objection_aggregator           objections;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         // A run that hangs ends with a fatal of UVM after 100 us (guide OBJ-7); the words take far less.
         uvm_root::get().set_timeout(100us, 0);
         in_cfg  = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("in_cfg");
         out_cfg = hexk_valid_ready_agent_cfg#(WIDTH)::type_id::create("out_cfg");
         `hexk_vif_get_or_fatal(hexk_valid_ready_if#(WIDTH), "in_vif", in_cfg.vif)
         `hexk_vif_get_or_fatal(hexk_valid_ready_if#(WIDTH), "out_vif", out_cfg.vif)
         out_cfg.role       = HEXK_VALID_READY_RESPONDER;
         in_agent           = hexk_valid_ready_agent#(WIDTH)::type_id::create("in_agent", this);
         in_agent.cfg       = in_cfg;
         out_agent          = hexk_valid_ready_agent#(WIDTH)::type_id::create("out_agent", this);
         out_agent.cfg      = out_cfg;
         objections         = hexk_objection_aggregator::type_id::create("objections", this);
         // A word that never leaves the DUT is an error after 1 us, instead of a run phase that never ends.
         sb_cfg             = hexk_scoreboard_cfg::type_id::create("sb_cfg");
         sb_cfg.max_wait_ps = `hexk_ps(1us);
         sb                 = hexk_scoreboard#(item_t)::type_id::create("sb", this);
         sb.cfg             = sb_cfg;
         sb.aggregator      = objections;
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         in_agent.ap.connect(sb.expected_export);
         out_agent.ap.connect(sb.actual_export);
         objections.register(out_agent, out_agent.get_full_name());
      endfunction : connect_phase

      task main_phase(uvm_phase phase);
         hexk_valid_ready_random_seq #(WIDTH) seq = hexk_valid_ready_random_seq#(WIDTH)::type_id::create("seq");
         super.main_phase(phase);
         phase.raise_objection(this, "stimulus");
         `hexk_randomize_with_or_fatal(seq, "EXAMPLE", num_items == NUM_WORDS;)
         seq.start(in_agent.sqr);
         `uvm_info("EXAMPLE", $sformatf("%0d words were sent by %0t", NUM_WORDS, $realtime), UVM_NONE)
         phase.drop_objection(this, "stimulus done");
      endtask : main_phase

      // An empty scoreboard reports nothing either: the test checks that every word it sent was compared.
      function void check_phase(uvm_phase phase);
         hexk_sb_stats stats = sb.get_stats();
         super.check_phase(phase);
         `hexk_check_eq(stats.matched, NUM_WORDS, "EXAMPLE_MATCHED")
      endfunction : check_phase
   endclass : hexk_example_test

   initial begin
      `hexk_vif_set(hexk_valid_ready_if#(WIDTH), "uvm_test_top", "in_vif", in_if)
      `hexk_vif_set(hexk_valid_ready_if#(WIDTH), "uvm_test_top", "out_vif", out_if)
      run_test("hexk_example_test");
   end

endmodule : hexk_valid_ready_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Connecting an output of the DUT to `valid`, `data` or `ready`.** These are variables
  that the interface writes; a port of the DUT or an `assign` on them does not compile.
  Assign what the DUT drives to `ext_valid`, `ext_data` and `ext_ready`.
- **Leaving the `ext_` input of a DUT-driven side unconnected.** The channel then has an X
  on that side, and `HEXK_VALID_READY_UNKNOWN` says so at every clock edge.
- **Driving the channel from testbench code** next to an active agent of that side. Send
  items; to take a signal over for a test, use a passive agent and the `ext_` inputs.
- **A sequence on a responder to "make it answer".** It answers without one. Start a
  sequence there only to set the delay of single transfers or to read the received words.
- **A responder sequence that runs for ever** on a registered agent. The driver always holds
  its next item, so the agent is always busy and the phase ends only through the watchdog.
  Give such a sequence a number of items, or stop it when the stimulus is done.
- **Fixed delays in the test to wait for the end of a transfer.** Register the agent with
  `hexk_objection_aggregator`, or wait for the sequence to end.
- **Comparing items with their timing.** `compare()` looks at `data` only, on purpose: a
  scoreboard checks the words, the assertions and the coverage look at the timing.
- **Different `has_checks` for two agents of one interface.** The interface has one switch;
  the agent whose start-of-simulation phase runs last sets it.
- **Expecting a transfer in the cycle in which an item arrives.** The driver offers it at
  the next rising edge, and the DUT sees it one edge later.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests build the
agents on one interface and run their phases by hand; the side that no agent drives is
driven through the `ext_` inputs, as a DUT would. The tests of the protocol assertions and
of X on `data` run on Questa and VCS only: the assertions are not switched on in the
Verilator build of the unit tests, and Verilator has no X. The example, with a DUT between
two interfaces, runs under `run_test()` in `make examples` on Questa and VCS.
