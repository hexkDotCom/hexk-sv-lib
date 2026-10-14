# src/uvm/config

Test-wide knobs: named values with a default, a help text and a plusarg, final after
`hexk_knobs::lock()`. The contract is `docs/api/hexk_knobs.md`.

| File | Content |
|---|---|
| `hexk_knobs.sv` | `hexk_knobs`: the registry, a singleton |
| `hexk_knob.sv` | `hexk_knob`: one knob; internal |
| `hexk_enum_knob.sv` | `hexk_enum_knob #(E)`: knobs of an enumerated type |

Knobs are defined before `lock()` and read after it; `hexk_base_test` locks them in its
`build_phase`.
