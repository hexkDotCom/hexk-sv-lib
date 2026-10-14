# examples/hexk_knobs

`hexk_knobs_example.sv` defines three test-wide knobs in a base test, changes one in a derived
test, locks them and reads them in the run phase and in an `initial` block. It needs UVM and
the UVM filelist (`src/uvm/hexk_uvm.f`).
