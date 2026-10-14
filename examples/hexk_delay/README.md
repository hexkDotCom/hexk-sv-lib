# examples/hexk_delay

`hexk_delay_example.sv` sends items in bursts: the gap before each item comes from a
`hexk_delay` with a bursty cfg, used once as clock cycles and once as a time. It needs UVM
and the UVM filelist (`src/uvm/hexk_uvm.f`).
