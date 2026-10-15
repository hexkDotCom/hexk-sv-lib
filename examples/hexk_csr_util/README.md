# examples/hexk_csr_util

`hexk_csr_util_example.sv` uses a register model with two registers whose frontdoor reaches a
register file of the module, in place of a bus agent: it excludes a counter field from the
reset check, checks the reset values, starts the "DUT" by writing a register, waits for its
done bit with a spin-wait, and checks a register under a mask and a field. It needs UVM and
the UVM filelist (`src/uvm/hexk_uvm.f`).
