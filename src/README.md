# src

Library sources, in three layers. Each layer has its own filelist and FuseSoC core;
`hexk_all.f` compiles everything.

| Directory | Package | Needs UVM |
|---|---|---|
| `core/` | `hexk_core_pkg` | no |
| `uvm/` | `hexk_uvm_pkg` | yes |
| `agents/` | a package per agent; `hexk_pins` is an interface only | yes |

Every filelist uses `$HEXK_SV_LIB_HOME`, which points at the repository root.
