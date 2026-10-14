# tests/smoke

Smoke testbench: one small UVM testbench that uses the library the way a
project does, with everything together. The DUT is a FIFO with a valid/ready channel at its
input and one at its output and two control pins.

| File | Content |
|---|---|
| `hexk_smoke.f` | filelist; compile it after UVM and `src/hexk_all.f`; the top module is `hexk_smoke_tb` |
| `hexk_smoke_dut.sv` | the FIFO; the pin `corrupt` inverts bit 0 of its output, the pin `stall` stops its input |
| `hexk_smoke_tb.sv` | the top: DUT, interfaces, and `hexk_tb_top_inc.svh`, which calls `run_test()` |
| `hexk_smoke_pkg.sv` | the package with the classes below |
| `hexk_smoke_env_cfg.sv`, `hexk_smoke_env.sv` | cfg and environment: `hexk_clk_rst_agent`, two `hexk_valid_ready_agent`, `hexk_scoreboard` |
| `hexk_smoke_heartbeat.sv` | subscriber that gives the watchdog a heartbeat per word |
| `hexk_smoke_base_test.sv` | base test on `hexk_base_test`: reset, traffic, the knob `num_items`, the final check |
| `hexk_smoke_pass_test.sv`, `hexk_smoke_error_test.sv`, `hexk_smoke_hang_test.sv` | the three tests |

What it exercises: the three agents (`hexk_clk_rst`, `hexk_valid_ready` as initiator and as
responder, `hexk_pins_if`), `hexk_scoreboard` with `hexk_objection_aggregator` holding the
phase until the last word is out, `hexk_watchdog` with a heartbeat per word, `hexk_knobs`,
`hexk_base_test` with the report server and the `TEST PASSED`/`TEST FAILED` line, the check
macros, `hexk_delay` in both channel agents, and the reset events of the clock and reset
agent, on which the environment empties the scoreboard.

The three tests, and how each must end:

| Test | What it does | Must end with |
|---|---|---|
| `hexk_smoke_pass_test` | sends 20 random words through the FIFO | `TEST PASSED`, 20 words matched |
| `hexk_smoke_error_test` | drives the pin `corrupt` first | `TEST FAILED` after `HEXK_SB_MISMATCH` errors |
| `hexk_smoke_hang_test` | drives the pin `stall` first | the fatal `HEXK_WATCHDOG`, "no heartbeat for", with the busy agent named |

`make smoke SIM=questa UVM=1.2|2020` compiles the testbench once, runs the three tests with
`+UVM_TESTNAME` and checks these endings in the logs (`$SMOKE_OUT/<test>.log`). A test that
is still running after `SMOKE_RUN_TIME` fails. `+num_items=<n>` changes the number of words.

The testbench has two instances of `hexk_valid_ready_if` and uses `hexk_pins_if`, so it does
not simulate on Verilator 5.046 (see the contracts of the agents). Gate 1 elaborates it with
slang against both UVM versions and lints it with Verible and Verilator.
