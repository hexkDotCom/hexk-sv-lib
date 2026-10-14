# src/uvm/check

The scoreboard. The contract is `docs/api/hexk_scoreboard.md`.

| File | Content |
|---|---|
| `hexk_scoreboard.sv` | `hexk_scoreboard #(T, KEY)`: in-order, out-of-order and in-order-per-key matching over one or more streams |
| `hexk_scoreboard_cfg.sv` | `hexk_scoreboard_cfg` and the mode type `hexk_sb_mode_e` |
| `hexk_sb_stats.sv` | `hexk_sb_stats`: the counters of a stream or of all streams |
| `hexk_sb_stream.sv` | `hexk_sb_stream`: the waiting items of one stream; internal |

The scoreboard keeps the handles of the items written to it; a producer does not change an
item after writing it, or sets `cfg.clone_expected` (see `docs/integration.md`, "Items
after they are published").
