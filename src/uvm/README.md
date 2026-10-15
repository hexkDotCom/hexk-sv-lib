# src/uvm - hexk_uvm_pkg

UVM utility layer. Depends on `hexk_core_pkg` and on UVM 1.2 or IEEE 1800.2-2017/2020.

| File | Content |
|---|---|
| `hexk_uvm.f`, `hexk_uvm.core` | filelist (includes the core filelist) and FuseSoC core |
| `hexk_uvm_compat.svh` | UVM version detection |
| `hexk_macros.svh` | umbrella header for all macro files; the one header users include |
| `hexk_uvm_pkg.sv` | the package; includes the class files in dependency order |

The macro files (`hexk_*_macros.svh`) are in this directory; class files live in the
subdirectories, each with a README that names the contracts.

| Directory | Content |
|---|---|
| `report/` | report server and its cfg, check statistics, report catcher, message listener |
| `data/` | regex, unique IDs, value wrapper, meta item |
| `eot/` | objection aggregator, end-of-test registry, watchdog |
| `config/` | knobs |
| `stim/` | waits, delays, rand-once guard |
| `base/` | base test, testbench-top include |
| `tlm/` | delayed analysis FIFO |
| `check/` | scoreboard |
| `mem/` | memory model |
| `cov/` | coverage helpers |
| `csr/` | register accesses and checks for any `uvm_reg_block` |
