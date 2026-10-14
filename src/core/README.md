# src/core - hexk_core_pkg

Pure SystemVerilog, no UVM: nothing in this directory may reference `uvm_pkg` or a
`` `uvm_* `` macro, and everything must run on Verilator.

| File | Content |
|---|---|
| `hexk_core.f`, `hexk_core.core` | filelist and FuseSoC core |
| `hexk_version.svh` | version defines, generated from `VERSION` by `make version` |
| `hexk_sim_compat.svh` | simulator shims: `HEXK_SIM_NAME`, `HEXK_STACKTRACE` |
| `hexk_core_pkg.sv` | the package; includes the class files in dependency order |
| `hexk_<name>.sv` | one class per file, included by the package; contract in `docs/api/hexk_<name>.md` |

The classes: `hexk_str` (strings), `hexk_enum_util` (enum names and values), `hexk_math`
(integer arithmetic), `hexk_crc`, `hexk_ecc`, `hexk_lfsr`, `hexk_rand_stream` (seeded random
numbers) and `hexk_plusarg` (typed plusargs).
