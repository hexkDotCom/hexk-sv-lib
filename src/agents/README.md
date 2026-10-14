# src/agents

Protocol-neutral agents. The clock/reset and valid/ready agents each have their own
package, interface, filelist and FuseSoC core; `hexk_pins` is an interface with its own
filelist and core, without a package. Each depends on `hexk_uvm_pkg` and never on another
agent. The
filelist of an agent does not include `src/uvm/hexk_uvm.f`: compile that first, or use
`src/hexk_all.f`.

| Directory | Content |
|---|---|
| `hexk_clk_rst/` | clock and reset generation |
| `hexk_valid_ready/` | parameterized valid/ready agent |
| `hexk_pins/` | drive, pull, force and sample for miscellaneous pins; an interface without an agent |
