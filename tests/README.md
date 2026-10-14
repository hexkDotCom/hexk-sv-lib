# tests

Self-tests of the library. They are not part of the library packages; you need them only to
check the library itself, for example on your own simulator before you use it, or to attach
a result to a bug report.

| Directory | Content |
|---|---|
| `unit/` | SVUnit unit tests, one directory per module |
| `smoke/` | one small UVM testbench that uses everything together |
| `lint/` | tool configuration and waivers for Verible, slang, Verilator and the style check |

The tests run at two levels:

- **Gate 1** runs with free tools (`make pre_sim`): Verible format and lint, Verilator
  lint, elaboration with slang against UVM 1.2 and UVM 2020, the unit tests on Verilator, a
  style and documentation check, and a check that the library still works under another
  prefix. CI runs its static part on every push to `main` (`make ci`: everything except the
  Verilator lint, the unit tests and the rebranded copy, which need more memory than a
  small runner has); the whole of Gate 1 runs before every release.
- **Gate 2** runs the unit tests, every example and the smoke testbench on a commercial
  simulator.

The results for the current version are in "Where it has been tested" in the top-level
`README.md`.

## Gate 1

Gate 1 runs on Linux, including WSL, with free tools: GNU make, Python 3.8 or newer,
[Verible](https://github.com/chipsalliance/verible), [slang](https://github.com/MikePopoloski/slang)
through the `pyslang` package, [Verilator](https://www.veripool.org/verilator/),
[SVUnit](https://github.com/svunit/svunit), [FuseSoC](https://github.com/olofk/fusesoc) and
the [z3](https://github.com/Z3Prover/z3) solver, which Verilator calls for constrained
randomization.

Verilator must be **v5.046**, built from source. Older and newer releases were tried and
fail: 5.020 (Ubuntu 24.04) cannot call enum methods through a class type parameter, and
5.052 cannot compile SVUnit 3.38.1 ("Duplicate declaration of VARSCOPE"). On Ubuntu 24.04:

```bash
sudo apt install -y make python3-venv unzip g++ git help2man perl autoconf flex bison ccache libfl2 libfl-dev zlib1g-dev z3
python3 -m venv ~/.venvs/hexk-sv-lib && ~/.venvs/hexk-sv-lib/bin/pip install pyslang==12.0.0 fusesoc==2.4.7
mkdir -p ~/.local/opt/verible
curl -sSfL https://github.com/chipsalliance/verible/releases/download/v0.0-4296-g0f262651/verible-v0.0-4296-g0f262651-linux-static-x86_64.tar.gz \
   | tar -xz -C ~/.local/opt/verible --strip-components=1
git clone --depth 1 --branch v3.38.1 https://github.com/svunit/svunit.git ~/.local/opt/svunit
git clone --depth 1 --branch v5.046 https://github.com/verilator/verilator.git ~/src/verilator
(cd ~/src/verilator && autoconf && ./configure --prefix="$HOME/.local/opt/verilator-5.046" && make -j"$(nproc)" && make install)
export SVUNIT_INSTALL="$HOME/.local/opt/svunit"
export PATH="$HOME/.venvs/hexk-sv-lib/bin:$HOME/.local/opt/verible/bin:$HOME/.local/opt/verilator-5.046/bin:$SVUNIT_INSTALL/bin:$PATH"
```

Then, from the root of the repository:

```bash
make uvm_fetch      # once: UVM 1.2 and 2020 sources into build/uvm (not vendored)
make pre_sim        # Gate 1
make help           # the single targets
```

## Gate 2

Gate 2 needs SVUnit, the UVM sources from `make uvm_fetch` and a simulator on the `PATH`:

```bash
make test     SIM=questa UVM=1.2      # unit tests; SIM=questa|vcs, UVM=1.2|2020
make test     SIM=vcs UVM=2020 TEST=hexk_scoreboard   # the unit tests of one module
make examples SIM=questa UVM=1.2      # compiles and runs every example
make smoke    SIM=questa UVM=1.2      # the smoke testbench, three tests
```

VCS runs on Linux with its license set up. Questa has been run on Windows only, from Git Bash
with a native GNU make and MinGW-w64 GCC (for the DPI code of UVM); see
[unit/README.md](unit/README.md).
