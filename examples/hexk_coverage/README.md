# examples/hexk_coverage

`hexk_coverage_example.sv` covers a valid/ready stream: a monitor writes one
`hexk_handshake_cycle_t` per clock cycle to one port, where the test connects a
`hexk_handshake_coverage`, and every transferred byte to another, where the test connects a
`uvm_subscriber` with a covergroup of its own, created with `` `hexk_cg_new ``; the test prints
both coverage numbers at the end.
The test defines the knob `coverage`; run the example with `+coverage=0` to see that no
covergroup is created then. It needs UVM and the UVM filelist (`src/uvm/hexk_uvm.f`), and a
simulator that builds covergroups for the numbers to mean something.
