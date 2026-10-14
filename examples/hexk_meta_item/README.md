# examples/hexk_meta_item

`hexk_meta_item_example.sv` wraps packets with the time, an ID and the name of the monitor
that saw them, compares two of them and reads the latency from the timestamps. It needs UVM
and the UVM filelist (`src/uvm/hexk_uvm.f`).
