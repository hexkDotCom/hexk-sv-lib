# hexk_valid_ready

Valid/ready agent: one side of a data channel with a valid/ready
handshake, or a passive observer of it, with the width of the data as parameter
`DATA_WIDTH`. The contract is `docs/api/hexk_valid_ready.md`.

| File | Content |
|---|---|
| `hexk_valid_ready.f` | filelist; compile it after `src/uvm/hexk_uvm.f` |
| `hexk_valid_ready.core` | FuseSoC core `hexkdotcom:hexk:valid_ready` |
| `hexk_valid_ready_if.sv` | the interface: the channel, the inputs for what a DUT drives, the protocol assertions |
| `hexk_valid_ready_pkg.sv` | the package, with the type `hexk_valid_ready_role_e` |
| `hexk_valid_ready_item.sv` | the item of the drivers and of the monitor: one transfer |
| `hexk_valid_ready_agent_cfg.sv` | the cfg: interface, mode, role, delays, checks and coverage switches |
| `hexk_valid_ready_driver.sv`, `hexk_valid_ready_monitor.sv`, `hexk_valid_ready_agent.sv` | the agent |
| `sequences/` | random words, and the words of a queue |

Usage in short: instantiate `hexk_valid_ready_if` per channel with its clock and reset;
connect the inputs of the DUT to `valid`, `data` and `ready` and assign what the DUT drives
to `ext_valid`, `ext_data` or `ext_ready`; create a `hexk_valid_ready_agent_cfg`, assign
`vif` and the `role`, and hand it to a `hexk_valid_ready_agent` before its build phase:
assign it, or, from a parent that cannot see the type of the agent, set it in
`uvm_config_db`; start `hexk_valid_ready_random_seq` on the sequencer
of an initiator. A responder answers without a sequence.

Known limits: the reset is active low; Verilator 5.046 simulates one instance of the
interface correctly and not several (see the contract, section 4).
