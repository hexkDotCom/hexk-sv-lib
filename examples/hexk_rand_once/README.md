# examples/hexk_rand_once

`hexk_rand_once_example.sv` guards a cfg with `` `hexk_rand_once_guard_decl ``: the first
randomization is silent, an accidental second one is an error with a stack trace, and an
intended one is allowed with `allow_rerandomize()`. It needs UVM and the UVM filelist
(`src/uvm/hexk_uvm.f`).
