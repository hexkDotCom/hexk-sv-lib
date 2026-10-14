# hexk_pins

`hexk_pins_if`: drive, pull, force and sample for miscellaneous pins
such as GPIO, straps and interrupts. An interface only, no agent. The contract is
`docs/api/hexk_pins.md`.

| File | Content |
|---|---|
| `hexk_pins.f` | filelist; compile it after `src/uvm/hexk_uvm.f` |
| `hexk_pins.core` | FuseSoC core `hexkdotcom:hexk:pins` |
| `hexk_pins_if.sv` | the interface |

Usage in short: instantiate `hexk_pins_if #(.WIDTH(n))`, connect the bits of `pins` to the
pins of the DUT, hand the interface to the test as a virtual interface, and call `drive`,
`pull_up`, `force_pins`, `sample`, `wait_value` and the others from the test or a sequence.

Known limits: it needs a simulator with nets that have several drivers, drive strengths and
`force`. Verilator 5.046 is not one: there the interface changes no pin and says so once
(`HEXK_PINS_UNSUPPORTED`).
