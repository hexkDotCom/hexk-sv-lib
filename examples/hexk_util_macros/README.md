# examples/hexk_util_macros

`hexk_util_macros_example.sv` uses the four utility macros in one small testbench: a virtual
interface handed over with `` `hexk_vif_set `` and `` `hexk_vif_get_or_fatal ``, a scoreboard
with indexed analysis imps, an address map with `` `hexk_constraint_no_overlap ``, and a
singleton. It needs UVM and the UVM filelist (`src/uvm/hexk_uvm.f`).
