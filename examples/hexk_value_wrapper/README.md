# examples/hexk_value_wrapper

`hexk_value_wrapper_example.sv` wraps 12-bit ADC samples into objects and compares a
predicted sample with a measured one with a tolerance of two counts. It needs UVM and the UVM
filelist (`src/uvm/hexk_uvm.f`).
