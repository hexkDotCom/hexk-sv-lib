# examples/hexk_valid_ready

`hexk_valid_ready_example.sv` puts a DUT with one register stage between an initiator agent
and a responder agent and compares what goes in with what comes out in a `hexk_scoreboard`.
It needs UVM, the UVM filelist (`src/uvm/hexk_uvm.f`) and the filelist of the agent
(`src/agents/hexk_valid_ready/hexk_valid_ready.f`). It uses two instances of the interface,
so it does not simulate correctly on Verilator 5.046 (see the contract, section 4); it runs
on Questa and VCS.
