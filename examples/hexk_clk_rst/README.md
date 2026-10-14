# examples/hexk_clk_rst

`hexk_clk_rst_example.sv` is a testbench whose clock and reset come from the agent: it
resets a counter for three clock cycles, lets it count and halves the clock frequency. It
needs UVM, the UVM filelist (`src/uvm/hexk_uvm.f`) and the filelist of the agent
(`src/agents/hexk_clk_rst/hexk_clk_rst.f`).
