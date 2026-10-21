# hexk-sv-lib

A vendor-neutral SystemVerilog/UVM utility library: the things every UVM testbench rewrites
from scratch (checks, reporting, end-of-test logic, delays, scoreboards, memory models, string
helpers, clock/reset), done once, documented for humans and AI assistants, and written to
follow the [HEXK SystemVerilog/UVM Style Guide](https://github.com/hexkDotCom/sv-uvm-style-guide).

It is built to work wherever you simulate. Every module is written to lint, compile and
simulate with free tools ([Verilator](https://www.veripool.org/verilator/),
[Verible](https://github.com/chipsalliance/verible) and
[slang](https://github.com/MikePopoloski/slang)), and is tested on commercial simulators with
both UVM 1.2 and UVM 2020. The code that runs most often in a simulation, such as checks,
reporting, the scoreboard and delays, has been measured with a benchmark and tuned for
speed.

## At a glance

A few lines from the core package, which needs no UVM and runs on Verilator too:

```systemverilog
import hexk_core_pkg::*;

hexk_str::split("top.env.agent", parts, ".");            // '{"top", "env", "agent"}
hexk_str::natural_sort(names);                           // agent_1, agent_2, agent_10
mode = hexk_enum_util#(mode_e)::from_name("MODE_FAST");  // a wrong name lists the legal ones
num_items = hexk_plusarg::get_int("num_items", 100);     // 500 with +num_items=500, else 100
crc = hexk_crc::compute(hexk_crc::crc32(), payload);     // 'hcbf43926 for "123456789"
status = ecc.decode(ecc.flip(code, 5), data, syndrome);  // HEXK_ECC_CORRECTED, data repaired
gap = stream.uniform(0, 15);                             // same values on Verilator, Questa, VCS
```

The UVM layer and the agents build on it: checks, reporting, end of test, delays, a
scoreboard, a memory model, clock/reset and valid/ready agents. Each module has a minimal
example in `examples/` and a contract in [docs/api/](docs/api/).

## Layers

| Layer | Package | Needs UVM | Directory |
|---|---|---|---|
| Core | `hexk_core_pkg` | no, runs on Verilator | `src/core/` |
| UVM utilities | `hexk_uvm_pkg` | UVM 1.2 or IEEE 1800.2-2017/2020 | `src/uvm/` |
| Agents | a package per agent; `hexk_pins` is an interface only | yes | `src/agents/` |

- **Core:** strings, enums, bit and integer math, CRC, LFSR, ECC (SECDED), seed-stable random
  streams, plusargs.
- **UVM utilities:** check macros, report server and catcher, waits with a time limit, regex
  filters, end-of-test registry, objection aggregator, watchdog, knobs, delays, an optional
  base test, unique IDs, value wrappers, a delayed analysis FIFO, a scoreboard, a sparse
  memory model, register accesses and checks for any register model, HDL access by path,
  coverage helpers.
- **Agents:** clock and reset, valid/ready, a pins interface.

Every global symbol starts with `hexk_`, every define and message ID with `HEXK_`, and every
plusarg of the library with `+hexk_`, which keeps its names apart from yours. The two
exceptions are knobs that the optional base test defines for the whole testbench:
`+perf_mode` and `+coverage`.

If your naming policy needs another prefix, `scripts/hexk_rebrand.py` writes a copy with it
(see "Another prefix" in [docs/integration.md](docs/integration.md)).

## Quick start

```bash
export HEXK_SV_LIB_HOME=/path/to/hexk-sv-lib
```

Add one line to your compile flow, after UVM:

```text
-f $HEXK_SV_LIB_HOME/src/hexk_all.f
```

For code without UVM use `-f $HEXK_SV_LIB_HOME/src/core/hexk_core.f` instead.

FuseSoC users depend on `hexkdotcom:hexk:sv_lib`, `hexkdotcom:hexk:uvm` or
`hexkdotcom:hexk:core`.

Command lines for Questa, VCS and Verilator, and the compile-time switches, are in
[docs/integration.md](docs/integration.md).

Then pick a module in [docs/api/](docs/api/) and start from its minimal example in
`examples/<module>/`.

## Documentation

- [docs/api/](docs/api/): one contract document per module, with a fixed layout: summary, when
  to use, API, behaviour and invariants, configuration, messages emitted, minimal example,
  anti-patterns, status.
- [docs/integration.md](docs/integration.md): filelists, command lines, FuseSoC, compile-time
  switches, another prefix, and "What works where": which feature works how on which
  simulator, UVM version and DPI setting.
- [docs/regression.md](docs/regression.md): checking how each run of a regression ended, against
  what it must end with (`scripts/hexk_check_run.py`).
- [examples/](examples/): a minimal, compiled and run example per module.
- [llms.txt](llms.txt): index of the contracts for AI assistants;
  [docs/USING_WITH_AI.md](docs/USING_WITH_AI.md): a snippet for the instruction file of a
  project that uses the library.
- [CHANGELOG.md](CHANGELOG.md).

## Where it has been tested

The library comes with its own tests: unit tests per module, every example, and a smoke
testbench (a small UVM testbench that uses the library the way a project does). Results for
version 0.11.0:

| Simulator | UVM | Unit tests | Examples | Smoke testbench |
|---|---|---|---|---|
| Verilator 5.046 | none (core) and 2020.3.1 | 776 of 776 | elaborated with slang | elaborated with slang |
| Questa 2024.1 | 1.2 and 2020.3.1 | 840 of 840 with each | 36 of 36 run with each | 3 of 3 tests with each |
| VCS X-2025.06 | 1.2 and 2020.3.1 | 840 of 840 with each | 36 of 36 run with each | 3 of 3 tests with each |
| Xcelium | | not run | not run | not run |

Everything is written to lint, compile and simulate on Verilator. Where Verilator 5.046
cannot simulate a part, the part is kept for the other simulators and its contract says so:
Verilator cannot compile UVM 1.2, has two-state variables (no X), simulates one instance of
an agent interface and not several, and cannot compile the pin model of `hexk_pins_if`. Those
tests, the pins interface and the smoke testbench run on Questa and VCS only.

The library has branches for Xcelium (`HEXK_SIM_NAME`, `HEXK_STACKTRACE`), written from its
documentation; nothing has been compiled or run there. A report from an Xcelium user is
welcome.

A reference testbench ([tests/reference](tests/reference/README.md)) checks the library from the
outside: a complete UVM testbench of a small DUT, built from the library the way a project
builds one, whose results are compared with the library models and with fixed vectors computed
without the library. It runs on Questa and VCS: 17 of 17 runs end as expected with each UVM
version.

To run the tests yourself, see [tests/README.md](tests/README.md). Running the unit tests of the
modules you use on your own simulator is a good first check, and a good attachment to a bug
report.

## Feedback

- **Issues:** bugs you have reproduced, and concrete requests for a module or an API change.
  For a bug, give the library version (`VERSION`, or `HEXK_VERSION_STR` from your log), the
  simulator and UVM version, the smallest code that shows the problem, what you expected and
  what you saw.
- **Discussions:** questions, opinions, general ideas, and suspected bugs you have not
  reproduced yet.

External pull requests are not accepted (see [CONTRIBUTING.md](CONTRIBUTING.md)). The library
is written clean-room; the projects whose ideas it builds on are credited in
[ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).

## License

Apache-2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). Copyright (c) 2026 HEXK.
