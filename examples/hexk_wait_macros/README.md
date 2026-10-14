# examples/hexk_wait_macros

`hexk_wait_macros_example.sv` waits for a signal with a time limit, runs a slow task with a
time limit, and uses `hexk_wait_util` to get the outcome as a value. It needs UVM and the UVM
filelist (`src/uvm/hexk_uvm.f`).
