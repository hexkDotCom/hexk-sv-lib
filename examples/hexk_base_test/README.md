# examples/hexk_base_test

`hexk_base_test_example.sv` is a whole small testbench: the top module includes
`base/hexk_tb_top_inc.svh` instead of calling `run_test()` itself, a block base test extends
`hexk_base_test`, and a smoke test returns a sequence from `create_stimulus()` that checks a few
values, so the log ends with `TEST PASSED`.
Run it with `+UVM_TESTNAME=hexk_example_smoke_test`. It needs UVM and the UVM filelist
(`src/uvm/hexk_uvm.f`).
