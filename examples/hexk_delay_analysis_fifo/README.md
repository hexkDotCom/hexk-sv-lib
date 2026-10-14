# examples/hexk_delay_analysis_fifo

`hexk_delay_analysis_fifo_example.sv` puts a delayed FIFO between a monitor and a predictor,
so that the predictor gets every input three clock cycles after the monitor saw it. It needs
UVM and the UVM filelist (`src/uvm/hexk_uvm.f`).
