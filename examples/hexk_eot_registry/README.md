# examples/hexk_eot_registry

`hexk_eot_registry_example.sv` has a reference model that is a plain object. It registers
with the end-of-test registry and reports a prediction that was never consumed when the
registry calls it in `check_phase`. It needs UVM and the UVM filelist (`src/uvm/hexk_uvm.f`).
