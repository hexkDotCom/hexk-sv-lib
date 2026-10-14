# examples/hexk_objection_aggregator

`hexk_objection_aggregator_example.sv` runs a small test whose scoreboard still waits for
responses when the stimulus is done. The aggregator holds the run phase until the scoreboard
is empty and prints who is busy. It needs UVM and the UVM filelist (`src/uvm/hexk_uvm.f`).
