# examples/hexk_pins

`hexk_pins_example.sv` drives a strap, pulls an open-drain interrupt up and waits for it,
and forces a bidirectional pin against the DUT, all through a virtual interface handle of
`hexk_pins_if`. It needs UVM, the UVM filelist (`src/uvm/hexk_uvm.f`) and the filelist of
the interface (`src/agents/hexk_pins/hexk_pins.f`). It needs a simulator with a pin model,
so it does not run on Verilator.
