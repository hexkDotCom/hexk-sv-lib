# examples/hexk_watchdog

`hexk_watchdog_example.sv` runs a test that stops making progress after five items. The
watchdog ends it 200 ns after the last heartbeat with a fatal that names the busy scoreboard
and the last heartbeat. It needs UVM and the UVM filelist (`src/uvm/hexk_uvm.f`).
