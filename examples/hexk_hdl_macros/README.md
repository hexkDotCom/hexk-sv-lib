# examples/hexk_hdl_macros

`hexk_hdl_macros_example.sv` reaches a counter and a status net by their HDL paths: it checks
a path, reads, deposits, forces and releases, and reads a path with a typing error. It needs
UVM compiled with its DPI code, the UVM filelist (`src/uvm/hexk_uvm.f`), and a simulation
that gives read and write access to the signals of the module; `make examples SIM=questa`
passes `-voptargs=-access=rw+hexk_hdl_macros_example` to `vsim` for it. Without that access
the first macro ends the simulation with a fatal.
