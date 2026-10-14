# src/uvm/base

The test base and the include for the testbench top.

| File | Content | Contract |
|---|---|---|
| `hexk_base_test.sv` | `hexk_base_test`: report server, knobs, objection aggregator and watchdog set up in one place; the PASSED/FAILED verdict | `docs/api/hexk_base_test.md` |
| `hexk_tb_top_inc.svh` | included inside the testbench top module: installs the report server at time 0 and calls `run_test()` | `docs/api/hexk_base_test.md` |

A test extends `hexk_base_test`, defines its knobs in `define_knobs()` and changes cfgs in
`modify_cfg()`; the base test locks the knobs in its `build_phase` between the two.
