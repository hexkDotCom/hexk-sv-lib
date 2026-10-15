# hexk_clk_rst

## 1. Summary

Clock and reset agent: an interface that generates one clock and one reset, and a UVM agent
that changes them from sequences (reset, frequency, stop and start) and tells the testbench
when the reset is asserted and released.

## 2. When to use / when not to use

Use one agent per clock of the testbench, with the reset that belongs to that clock. The
test starts `hexk_clk_rst_reset_seq` in its reset phase; the env waits for the reset events
of the agent's `status`, or subscribes to `ap`, and empties its scoreboards and models (guide
rule CHK-6). Use the agent in passive mode on
a clock and a reset that the DUT generates itself, to get the same reset events and the
clock count for them. Give the agent to other components as a `hexk_clk_countable` when
they only need to count or wait for clock cycles and should not know the interface.

Do not use it to model a clock generator of the design: a PLL with lock time, a clock
divider, a clock gate. The clock here is an ideal source for the testbench. Do not use it
when two clocks need an exact ratio that is not a whole number of picoseconds per period;
see the limits in section 4. Do not generate the clock in the testbench top as well (guide
rule IFC-2 asks for one place).

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/agents/hexk_clk_rst/hexk_clk_rst_agent.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_agent_cfg.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_driver.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_if.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_item.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_monitor.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_pkg.sv`
- `src/agents/hexk_clk_rst/hexk_clk_rst_status.sv`
- `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_clock_seq.sv`
- `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_reset_seq.sv`
- `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_start_seq.sv`
- `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_stop_seq.sv`
- `src/uvm/stim/hexk_clk_countable.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/agents/hexk_clk_rst/hexk_clk_rst_agent.sv`:

```systemverilog
// Creates the agent, its port and its status; the children are created in build_phase.
function new(string name, uvm_component parent);
// UVM callback: checks the cfg and its interface, creates the monitor and, in active mode, sequencer and driver.
function void build_phase(uvm_phase phase);
// UVM callback: connects the driver to the sequencer and the port of the monitor to the port of the agent.
function void connect_phase(uvm_phase phase);
// UVM callback: tells the interface the mode, the active level of the reset and the seed of the jitter.
function void start_of_simulation_phase(uvm_phase phase);
// UVM hook: the mode of the cfg.
virtual function uvm_active_passive_enum get_is_active();
// hexk_clk_countable: number of rising edges of the clock so far.
virtual function longint unsigned get_clk_count();
// hexk_clk_countable: waits for n rising edges of the clock; returns at once when n is 0.
virtual task wait_clks(int unsigned n);
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_agent_cfg.sv`:

```systemverilog
// Creates a cfg for an active agent with a clock of 100 MHz and a reset that is active low.
function new(string name = "hexk_clk_rst_agent_cfg");
// Sets period_ps from a frequency in MHz, rounded to a whole number of picoseconds.
function void set_freq_mhz(real freq_mhz);
// The frequency in MHz that period_ps stands for; 0 for a period of 0.
function real get_freq_mhz();
// The time in picoseconds for which a clock with this period and duty cycle is high.
static function longint unsigned high_time_ps(longint unsigned clock_period_ps, int unsigned duty);
// What is wrong with a period, a duty cycle and a jitter; empty when they make a legal clock.
static function string clock_illegal_reason(longint unsigned clock_period_ps, int unsigned duty, longint unsigned clock_jitter_ps);
// What is wrong with the clock values of this cfg; empty when they are legal.
function string illegal_reason();
// The mode, the clock and the settings of the reset, on one line.
function string convert2string();
// UVM hook of copy() and clone(): copies every member; the copy shares the interface.
function void do_copy(uvm_object rhs);
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_driver.sv`:

```systemverilog
// Creates the driver.
function new(string name, uvm_component parent);
// UVM callback: takes the interface from the cfg; the agent has checked both.
function void connect_phase(uvm_phase phase);
// UVM callback: applies the cfg, then carries out the items.
task run_phase(uvm_phase phase);
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_if.sv`:

```systemverilog
// Sets the mode, the active level of the reset and the seed of the jitter; the agent calls it once, at time 0.
function automatic void configure(bit is_passive, bit active_low, int unsigned seed);
// Asks for a clock with this period, high time and jitter; it holds from the next rising edge.
function automatic void set_clock(longint unsigned new_period_ps, longint unsigned new_high_ps, longint unsigned new_jitter_ps);
// Sets the time by which the first start of the clock is delayed.
function automatic void set_start_delay(longint unsigned delay_ps);
// Starts the clock (1) or stops it after the high time that is going on (0).
function automatic void request_run(bit run);
// 1 when the clock is asked to run; the generator may still finish a high time after a stop was asked for.
function automatic bit run_requested();
// Waits until the generator has stopped; the clock is 0 then.
task automatic wait_stopped();
// The value of the pin for an asserted (1) or a released (0) reset.
function automatic logic pin_value(bit active);
// Asserts (1) or releases (0) the reset at once.
function automatic void drive_reset(bit active);
// Asserts or releases the reset in the time step of a rising edge, after the edge: the DUT sees it at the next edge. With wait_for_edge it waits for the next rising edge first; without, the caller is at an edge.
task automatic drive_reset_at_edge(bit active, bit wait_for_edge);
// 1 when the pin has a level; active then says whether the reset is asserted.
function automatic bit get_reset(output bit active);
// Waits for a change of the reset pin.
task automatic wait_reset_change();
// Waits for a time in picoseconds, through hexk_wait_util: a time after hexk_wait_util::LAST_PS never comes.
task automatic wait_ps(longint unsigned duration_ps);
// Number of rising edges of clk since the start of the simulation.
function automatic longint unsigned get_clk_count();
// Waits for n rising edges of clk; returns at once when n is 0.
task automatic wait_clks(int unsigned n);
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_item.sv`:

```systemverilog
// Creates an item that asks for a reset without a hold.
function new(string name = "hexk_clk_rst_item");
// The operation and the members it uses, on one line.
function string convert2string();
// UVM hook of copy() and clone(): copies every member.
function void do_copy(uvm_object rhs);
// UVM hook of compare(): the operation and what it asks for or reports; the clock count is not compared.
function bit do_compare(uvm_object rhs, uvm_comparer comparer);
// UVM hook of print() and sprint(): the operation and the members it uses, as convert2string() shows them.
function void do_print(uvm_printer printer);
// UVM hook of pack(): every member, in the order of the declarations, whatever the operation uses.
function void do_pack(uvm_packer packer);
// UVM hook of unpack(): the members in the order in which do_pack() wrote them.
function void do_unpack(uvm_packer packer);
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_monitor.sv`:

```systemverilog
// Creates the monitor and its port.
function new(string name, uvm_component parent);
// UVM callback: takes the interface from the cfg; the agent has checked both.
function void connect_phase(uvm_phase phase);
// UVM callback: reports every change of the reset between asserted and released. A reset that is asserted at the start is reported; a pin without a level is neither and changes nothing.
task run_phase(uvm_phase phase);
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_pkg.sv`:

```systemverilog
// What an item asks the driver to do; an item of the monitor is always HEXK_CLK_RST_RESET.
typedef enum bit [1:0] { HEXK_CLK_RST_RESET, HEXK_CLK_RST_CLOCK, HEXK_CLK_RST_STOP, HEXK_CLK_RST_START } hexk_clk_rst_op_e;
```

From `src/agents/hexk_clk_rst/hexk_clk_rst_status.sv`:

```systemverilog
// Creates a status with the two events, out of reset, with the default clock of a cfg.
function new(string name = "hexk_clk_rst_status");
// Notes the clock that is driven from now on; called by the agent and its driver.
function void set_clock(longint unsigned new_period_ps, int unsigned duty, longint unsigned new_jitter_ps);
// The frequency in MHz of the clock that is driven; 0 for a period of 0.
function real get_freq_mhz();
// The reset and the clock, on one line.
function string convert2string();
```

From `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_clock_seq.sv`:

```systemverilog
// Creates the sequence.
function new(string name = "hexk_clk_rst_clock_seq");
// Sends one clock item; returns at the rising edge from which the new clock holds.
task body();
```

From `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_reset_seq.sv`:

```systemverilog
// Creates the sequence.
function new(string name = "hexk_clk_rst_reset_seq");
// Sends one reset item; returns when the reset is released.
task body();
```

From `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_start_seq.sv`:

```systemverilog
// Creates the sequence.
function new(string name = "hexk_clk_rst_start_seq");
// Sends one start item; returns at the first rising edge of the clock.
task body();
```

From `src/agents/hexk_clk_rst/sequences/hexk_clk_rst_stop_seq.sv`:

```systemverilog
// Creates the sequence.
function new(string name = "hexk_clk_rst_stop_seq");
// Sends one stop item; returns when the clock is 0, or runs again after stop_ps.
task body();
```

From `src/uvm/stim/hexk_clk_countable.sv`:

```systemverilog
// Number of clock cycles so far.
pure virtual function longint unsigned get_clk_count();
// Waits for n clock cycles; returns at once when n is 0.
pure virtual task wait_clks(int unsigned n);
```
<!-- HEXK_GEN:END api -->

Types, signals and members that the listing above does not show:

| Interface `hexk_clk_rst_if` | |
|---|---|
| `logic clk`, `logic rst` | The clock and the reset pin: connect both to the DUT. |
| `logic ext_clk`, `logic ext_rst` | Passive mode: the testbench assigns the clock and the reset of the DUT to them. |
| `clocking mon_cb @(posedge clk)` | Samples `rst`; `@(vif.mon_cb)` is "the next clock edge" for testbench code. |

| `hexk_clk_rst_op_e` | An item asks the driver to |
|---|---|
| `HEXK_CLK_RST_RESET` | assert the reset, hold it, release it; every item of the monitor has this value |
| `HEXK_CLK_RST_CLOCK` | give the clock a new period, duty cycle and jitter |
| `HEXK_CLK_RST_STOP` | stop the clock, and start it again after `hold_ps` if that is above 0 |
| `HEXK_CLK_RST_START` | start the clock |

| Member of `hexk_clk_rst_item` | Used by | Meaning |
|---|---|---|
| `rand hexk_clk_rst_op_e op` | all | What the driver does. |
| `rand int unsigned hold_cycles` | reset | Rising edges for which the reset is held. |
| `rand longint unsigned hold_ps` | reset, stop | Time for which the reset is held after the edges; time after which a stopped clock starts again. |
| `rand bit sync_assert` | reset | 1: asserted at the next rising edge; 0: at once. |
| `rand bit sync_release` | reset | 1: released at a rising edge; 0: when the hold is over. |
| `rand longint unsigned period_ps` | clock | Period. |
| `rand int unsigned duty_percent` | clock | Share of the period in which the clock is high. |
| `rand longint unsigned jitter_ps` | clock | Largest distance of a rising edge from its ideal time. |
| `bit reset_active` | monitor | 1 in the item of an assertion, 0 in the item of a release. |
| `longint unsigned clk_count` | monitor | The clock count at the change of the reset. |

The agent has the members `cfg`, `status`, `sqr`, `drv`, `mon` and `ap`; the members of the
cfg and of the sequences are in section 5. The agent implements
`hexk_uvm_pkg::hexk_clk_countable`.

`hexk_clk_rst_status`, the member `status` of the agent, holds what changes during the run:

| Member | Meaning |
|---|---|
| `uvm_event reset_asserted`, `reset_released` | Triggered by the monitor, with the item as data, when the reset is asserted and when it is released. |
| `bit in_reset` | 1 from the moment the monitor saw the reset asserted until it saw it released. |
| `period_ps`, `duty_percent`, `jitter_ps` | The clock that is being driven. |
| `get_freq_mhz()` | The frequency of that clock. |
| `convert2string()` | The reset and the clock on one line. |
| `set_clock(new_period_ps, duty, new_jitter_ps)` | Called by the agent and its driver; not by the testbench. |

Of the interface, a testbench uses the signals `clk` and `rst` (and `ext_clk` and `ext_rst`
in passive mode), the clocking block `mon_cb`, `get_clk_count()` and `wait_clks()`. The other
tasks and functions and the variables of the interface are for the driver and the monitor
of the agent, which generate the clock and drive the reset through them (guide rule IFC-8);
do not call or write them from testbench code. The members `cfg` and `status` of the driver
and of the monitor are assigned by the agent. `build_phase`, `connect_phase`,
`start_of_simulation_phase` and `run_phase` are UVM callbacks, and `body` is called by UVM.

Compile `src/uvm/hexk_uvm.f` and then `src/agents/hexk_clk_rst/hexk_clk_rst.f`, or
`src/hexk_all.f` for everything. The interface is compiled outside the package; import the
classes from `hexk_clk_rst_pkg`.

## 4. Behaviour and invariants

Times:

- Every time of this module is a whole number of picoseconds in a member whose name ends in
  `_ps`. The interface declares its own time unit and turns the numbers into delays itself,
  so they mean the same whatever the time unit of the testbench or of the packages is, as
  every time of the library does (`docs/integration.md`, "Times").
- A period is therefore exact only when it is a whole number of picoseconds: 100 MHz is
  10000 ps, 3 GHz becomes 333 ps (3.003 GHz). `set_freq_mhz()` rounds to the nearest.
- The interface has a time precision of 1 ps; the simulation gets at least that precision.

The clock, in active mode:

- At the start of the run phase the driver applies the cfg. With `start_clock` the clock
  starts then: a start begins with the low time of the period, so the first rising edge
  comes `phase_ps` plus one low time after the start of the run phase, and from then on one
  every `period_ps`. The clock is high for `duty_percent` percent of the period, rounded
  down to a whole picosecond. Before the first rising edge, and whenever it is stopped, the
  clock is 0. There is no rising edge at time 0.
- **Jitter.** With `jitter_ps` above 0 every rising edge is moved from its ideal time by a
  random amount of at most `jitter_ps` either way. The ideal times stay on the grid of the
  period, so the jitter does not add up. The falling edge keeps its distance to the rising
  edge. The numbers come from a `hexk_rand_stream` with the seed `jitter_seed`: the same
  seed gives the same clock.
- **A new period, duty cycle or jitter** (`HEXK_CLK_RST_CLOCK`) holds from the next rising
  edge: the cycle that is going on ends with the old values, and no edge is cut short. The
  item is done at that rising edge, at once when the clock is stopped. All three values are
  applied; to change one, give the other two again. The new clock counts from the rising
  edge at which it takes over: the jitter of that edge under the old clock is not carried
  into the first low time of the new one, so a fast clock after a slow jittered one has
  high and low times above 0 from its first cycle.
- **Stop** (`HEXK_CLK_RST_STOP`): the clock finishes the high time that is going on and
  then stays 0; a stop during the low time takes effect at the end of that low time, without
  a rising edge. The item is done when the clock has stopped. With `hold_ps` above 0 the
  driver starts the clock again after that time, and the item is done at the first rising
  edge. A stop of a stopped clock does nothing.
- **Start** (`HEXK_CLK_RST_START`): the next rising edge comes one low time of the period
  after the start. The item is done at that edge. A start of a running clock does nothing.
- The driver notes the values it applied in `status.period_ps`, `status.duty_percent` and
  `status.jitter_ps`, so the status always tells the clock that is running (guide rule
  CFG-9): a new clock of a running clock at the rising edge from which it holds, that of a
  stopped clock at once. The cfg is the setup: the library reads it and never changes it.
- Legal values: `period_ps` from 2 to 2**48 - 1; `duty_percent` 1 to 99, and both the high
  and the low time at least 1 ps; `jitter_ps` at most a quarter of the shorter of the two.
  The high time is `period_ps * duty_percent / 100` rounded down and the low time is the
  rest of the period; the constraints of the cfg and `illegal_reason()` use these two
  rounded times and allow exactly the same clocks (2 ps with 99 percent is 1 ps high and
  1 ps low, and legal).
  `illegal_reason()` says what is wrong. An illegal clock in the cfg at the start is the
  error `HEXK_CLK_RST_ILLEGAL`; the driver then uses the default clock (100 MHz, 50 percent,
  no jitter) and notes it in the status; the cfg keeps its values. An illegal clock in an
  item is the same error, and the clock is not changed. An item whose operation is no value
  of `hexk_clk_rst_op_e` is the same error too, and is ignored.

The reset, in active mode:

- `rst` is the pin of the DUT. With `rst_active_low` the reset is asserted when the pin is
  0, otherwise when it is 1. The pin is driven from the start of the run phase: asserted
  with `reset_at_start`, released without it.
- **A reset item** (`HEXK_CLK_RST_RESET`) runs in three steps. Assert: at once, or with
  `sync_assert` at the next rising edge of the clock. Hold: for `hold_cycles` rising edges
  and then for `hold_ps`. Release: when the hold is over, or with `sync_release` at a rising
  edge: the last edge of the hold when `hold_ps` is 0, otherwise the next edge after the
  hold. The item is done when the reset is released.
- "At a rising edge" means in the time step of the edge, after it: the DUT sees the old
  value at that edge and the new one at the following edge. So a reset with `hold_cycles`
  5, `hold_ps` 0 and `sync_release`, which is what a plain `randomize()` of
  `hexk_clk_rst_reset_seq` gives, is seen asserted by the DUT at exactly 5 rising edges.
- A reset that is already asserted, as after `reset_at_start`, stays asserted through the
  first step; the hold counts from the start of the item.
- A reset item with `sync_assert`, no hold at all (`hold_cycles` 0 and `hold_ps` 0) and
  without `sync_release` asserts and releases the reset in the time step of one rising edge,
  in that order: the reset is released when the item is done. Such a pulse has no width;
  whether a DUT sees it depends on the simulator. Give a reset a hold.
- When the clock is stopped, a step that needs a rising edge cannot end. The driver does
  not wait: a reset item with `hold_cycles` above 0, `sync_assert` or `sync_release` while
  the clock is stopped is the error `HEXK_CLK_RST_STOPPED`, and those parts are left out
  (assert at once, hold for `hold_ps`, release at once).
- Items are carried out one after the other. A reset item holds the driver until the
  release; a clock, stop or start item waits behind it.

The monitor, in both modes:

- It watches the pin `rst`, not the clocking block, because a reset may change away from a
  clock edge and while the clock is stopped. Every change between asserted and released is
  one item on `ap`: `op` is `HEXK_CLK_RST_RESET`, `reset_active` tells which, `clk_count` is
  the clock count at the change. Before the item it sets `status.in_reset`; after the item
  it triggers `status.reset_asserted` or `status.reset_released` with the item as data.
- A reset that is already asserted when the run phase starts is reported as an assertion at
  that time. A pin that is X or Z is neither: nothing is reported until it has a level, and
  the same level after an X is not a change.
- Each change is also the info `HEXK_CLK_RST_RESET` with verbosity `UVM_MEDIUM`.

Passive mode:

- The agent builds only the monitor, and the interface generates nothing. The testbench
  assigns the clock and the reset of the DUT to `ext_clk` and `ext_rst` of the interface;
  `clk` and `rst` follow them, one delta cycle later. The clock count, `mon_cb` and the
  reset events work as in active mode.
- In active mode `ext_clk` and `ext_rst` are not used.

Clock count:

- `get_clk_count()` is the number of rising edges of `clk` since the start of the
  simulation, in both modes. `wait_clks(n)` returns at the n-th rising edge after the call,
  at once for 0. With a stopped clock it waits until the clock runs again.
- The agent implements `hexk_clk_countable` by calling the interface. A component that
  takes a `hexk_clk_countable` needs neither the package of the agent nor the interface.

The agent:

- `cfg`, with `cfg.vif`, is assigned by the parent before the build phase (guide rule
  CFG-2). A parent that cannot see the type of the agent, such as a reusable environment,
  sets it instead with `uvm_config_db#(hexk_clk_rst_agent_cfg)::set(this, "<agent path>",
  "cfg", cfg)`; the agent looks there only when nothing was assigned (CFG-4). A `cfg` that is
  still null, or a null `cfg.vif`, in the build phase is the fatal `HEXK_CLK_RST_CFG`.
- The agent creates `ap` and `status` in its constructor, so both exist before the build
  phase; a consumer can connect to `ap` or keep `status` at any time. The monitor writes
  through `ap`, which the agent connects to the port of the monitor.
- The agent builds `mon` always and `sqr` and `drv` in active mode, and notes the clock of
  the cfg in `status`; in passive mode the status keeps that clock, which the agent does not
  drive. `get_is_active()` returns `cfg.is_active`.
- A status belongs to its agent and is not meant to be copied. A copy of the cfg shares the
  interface and nothing else. A copy of an item or a cfg from an object of another class is
  the error `HEXK_COPY_TYPE` and changes nothing.
- `compare()` of two items compares the operation and the members that it uses, each
  through the comparer, so that the default `compare_items()` of `hexk_scoreboard` names the
  members that differ; `clk_count` is not compared. `print()` and `sprint()` show the
  operation and the members it uses. `pack()` writes every member, whatever the operation
  uses, in the order of the declarations, and `unpack()` reads them back.
- The driver and the monitor work in the run phase only. The sequences do not raise
  objections and work from any phase.
- The defaults of the members of the sequences are soft constraints:
  `randomize() with { hold_cycles == 20; }` overrides one. A sequence sends one item; a
  failed randomization of that item is the fatal `HEXK_CLK_RST_RAND`.

Simulators:

- Verilator 5.046 simulates one instance of `hexk_clk_rst_if` correctly. With several
  instances it wakes the tasks of one instance on events of another, so a testbench with
  more than one clock and reset agent does not work there. It also cannot override a soft
  constraint with a constraint of the call: assign the members of a sequence instead.

## 5. Configuration

| Member of `hexk_clk_rst_agent_cfg` | Default | Meaning |
|---|---|---|
| `is_active` | `UVM_ACTIVE` | `UVM_PASSIVE`: monitor only, the interface generates nothing. |
| `vif` | null | The interface of this agent; mandatory. |
| `period_ps` | 10000 | Period of the clock; 10000 is 100 MHz. |
| `duty_percent` | 50 | Share of the period in which the clock is high, 1 to 99. |
| `jitter_ps` | 0 | Largest distance of a rising edge from its ideal time. |
| `phase_ps` | 0 | Time by which the first start of the clock is delayed. |
| `rst_active_low` | 1 | 1: the reset is asserted when the pin is 0. |
| `start_clock` | 1 | 0: the clock is stopped until a start sequence. |
| `reset_at_start` | 1 | 0: the reset is released from the start of the run phase. |
| `jitter_seed` | 0 | Seed of the jitter; 0 derives it from the name of the agent. |

`period_ps`, `duty_percent`, `jitter_ps` and `phase_ps` are `rand`. A plain `randomize()`
keeps the defaults (soft constraints) and the legal values of section 4.

| Member of a sequence | Default | Meaning |
|---|---|---|
| `hexk_clk_rst_reset_seq::hold_cycles` | 5 | Rising edges for which the reset is held. |
| `hexk_clk_rst_reset_seq::hold_ps` | 0 | Time for which the reset is held after the edges. |
| `hexk_clk_rst_reset_seq::sync_assert` | 0 | 1: asserted at the next rising edge. |
| `hexk_clk_rst_reset_seq::sync_release` | 1 | 1: released at a rising edge. |
| `hexk_clk_rst_clock_seq::period_ps` | 10000 | New period. |
| `hexk_clk_rst_clock_seq::duty_percent` | 50 | New duty cycle. |
| `hexk_clk_rst_clock_seq::jitter_ps` | 0 | New jitter. |
| `hexk_clk_rst_stop_seq::stop_ps` | 0 | Time after which the clock starts again; 0 leaves it stopped. |

There are no plusargs and no compile-time switches.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_CLK_RST_CFG` | fatal |  |
| `HEXK_CLK_RST_CLOCK` | info |  |
| `HEXK_CLK_RST_ILLEGAL` | error |  |
| `HEXK_CLK_RST_RAND` | fatal |  |
| `HEXK_CLK_RST_RESET` | info |  |
| `HEXK_CLK_RST_STOPPED` | error |  |
| `HEXK_COPY_TYPE` | error |  |
<!-- HEXK_GEN:END emits -->

| ID | Meaning |
|---|---|
| `HEXK_CLK_RST_CFG` | The agent has no cfg, assigned or in `uvm_config_db`, or the cfg has no interface. |
| `HEXK_CLK_RST_CLOCK` | The clock was set, stopped or started (`UVM_MEDIUM`). |
| `HEXK_CLK_RST_ILLEGAL` | The clock of the cfg or of an item is not legal. |
| `HEXK_CLK_RST_RAND` | A sequence could not randomize its item. |
| `HEXK_CLK_RST_RESET` | The reset was asserted or released (`UVM_MEDIUM`). |
| `HEXK_CLK_RST_STOPPED` | A reset item needs clock edges, but the clock is stopped. |
| `HEXK_COPY_TYPE` | `copy()` of an item or a cfg from an object of another class; nothing is copied. |

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_clk_rst/hexk_clk_rst_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_example.sv
//
// Minimal use of hexk_clk_rst: a testbench whose clock and reset come from the agent. The
// DUT is a counter with a reset that is active low. The test gives the clock 200 MHz in the
// cfg, resets the DUT for three clock cycles in its reset phase, lets the counter run and
// halves the clock frequency in its main phase. A thread waits for the reset event of the
// status of the agent, as an env would to empty its scoreboards; the status also tells the
// clock that is being driven.
// Needs UVM, src/uvm/hexk_uvm.f and src/agents/hexk_clk_rst/hexk_clk_rst.f.

`include "hexk_macros.svh"

module hexk_clk_rst_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent;
   import hexk_clk_rst_pkg::hexk_clk_rst_agent_cfg;
   import hexk_clk_rst_pkg::hexk_clk_rst_reset_seq;
   import hexk_clk_rst_pkg::hexk_clk_rst_clock_seq;
   `include "uvm_macros.svh"

   localparam int unsigned RESET_CYCLES = 3;
   localparam int unsigned RUN_CYCLES = 10;
   localparam longint unsigned SLOW_PERIOD_PS = 10_000;

   hexk_clk_rst_if clk_rst_if ();

   // The DUT: counts clock cycles while it is not in reset.
   logic [7:0] count;

   always_ff @(posedge clk_rst_if.clk or negedge clk_rst_if.rst) begin
      if (!clk_rst_if.rst) begin
         count <= '0;
      end else begin
         count <= count + 8'd1;
      end
   end

   class hexk_example_test extends uvm_test;
      hexk_clk_rst_agent_cfg clk_rst_cfg;
      hexk_clk_rst_agent     clk_rst_agent;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         clk_rst_cfg = hexk_clk_rst_agent_cfg::type_id::create("clk_rst_cfg");
         `hexk_vif_get_or_fatal(hexk_clk_rst_if, "clk_rst_vif", clk_rst_cfg.vif)
         clk_rst_cfg.set_freq_mhz(200.0);
         clk_rst_agent     = hexk_clk_rst_agent::type_id::create("clk_rst_agent", this);
         clk_rst_agent.cfg = clk_rst_cfg;
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         forever begin
            clk_rst_agent.status.reset_asserted.wait_trigger();
            `uvm_info("EXAMPLE", "the reset is asserted: a scoreboard drops its items here", UVM_NONE)
         end
      endtask : run_phase

      task reset_phase(uvm_phase phase);
         hexk_clk_rst_reset_seq reset_seq = hexk_clk_rst_reset_seq::type_id::create("reset_seq");
         super.reset_phase(phase);
         phase.raise_objection(this, "reset");
         `hexk_randomize_with_or_fatal(reset_seq, "EXAMPLE", hold_cycles == RESET_CYCLES;)
         reset_seq.start(clk_rst_agent.sqr);
         `uvm_info("EXAMPLE", $sformatf("reset released at %0t, after %0d clock cycles", $realtime,
                                        clk_rst_agent.get_clk_count()), UVM_NONE)
         phase.drop_objection(this, "reset done");
      endtask : reset_phase

      task main_phase(uvm_phase phase);
         hexk_clk_rst_clock_seq clock_seq = hexk_clk_rst_clock_seq::type_id::create("clock_seq");
         super.main_phase(phase);
         phase.raise_objection(this, "stimulus");
         clk_rst_agent.wait_clks(RUN_CYCLES);
         `uvm_info("EXAMPLE", $sformatf("at %0t the counter is %0d", $realtime, count), UVM_NONE)
         `hexk_randomize_with_or_fatal(clock_seq, "EXAMPLE", period_ps == SLOW_PERIOD_PS;)
         clock_seq.start(clk_rst_agent.sqr);
         clk_rst_agent.wait_clks(RUN_CYCLES);
         `uvm_info("EXAMPLE", $sformatf("at %0t, with %0.0f MHz, the counter is %0d", $realtime,
                                        clk_rst_agent.status.get_freq_mhz(), count), UVM_NONE)
         phase.drop_objection(this, "stimulus done");
      endtask : main_phase
   endclass : hexk_example_test

   initial begin
      `hexk_vif_set(hexk_clk_rst_if, "uvm_test_top", "clk_rst_vif", clk_rst_if)
      run_test("hexk_example_test");
   end

endmodule : hexk_clk_rst_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Driving `clk` or `rst` from the testbench**, or calling the other tasks of the
  interface. In active mode the agent owns both; change them with a sequence. In passive
  mode assign `ext_clk` and `ext_rst`, not `clk` and `rst`.
- **A reset by clock cycles while the clock is stopped.** It cannot count edges and is the
  error `HEXK_CLK_RST_STOPPED`. Start the clock first, or hold the reset by time
  (`hold_cycles == 0; hold_ps == ...; sync_release == 0;`).
- **Sampling `rst` in the testbench at the edge at which it is released** and expecting the
  new value. A change at a rising edge is seen at the following edge, as by the DUT; wait
  for `status.reset_released` or use `mon_cb`.
- **Changing only the period of a clock with jitter or an uneven duty cycle** and expecting
  the other two to stay. `hexk_clk_rst_clock_seq` applies all three; constrain all three.
- **Changing `cfg.period_ps` during the run to change the clock.** The cfg is applied at the
  start of the run phase and not read again. Use `hexk_clk_rst_clock_seq`.
- **Reading the clock that runs from the cfg.** The cfg holds the clock of the start; the
  status holds the clock that is driven now.
- **A frequency that is not a whole number of picoseconds per period** where two clocks must
  keep an exact ratio. Choose periods that are whole picoseconds and have that ratio.
- **Two agents on one interface**, or an active agent on an interface whose `clk` the
  testbench also drives.
- **Waiting with `wait_clks()` for a clock that nobody starts** (`start_clock` 0 and no
  start sequence). The wait does not end; a watchdog names it.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests build the
agent on one interface and run its phases by hand; the test of the passive mode needs a
second interface and runs on Questa and VCS only, like the test that overrides a default
of a sequence with a constraint (see "Simulators" in section 4). The example runs the agent
under `run_test()` with the real phases, in `make examples` on Questa and VCS.
