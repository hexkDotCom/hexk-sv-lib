# src/uvm/data

Data helpers.

| File | Content | Contract |
|---|---|---|
| `hexk_regex.sv` | `hexk_regex`: regular expressions through the DPI of UVM; without that DPI, globs only | `docs/api/hexk_regex.md` |
| `hexk_uid.sv`, `hexk_uid_pool.sv` | `hexk_uid` and `hexk_uid_pool`: unique IDs for items, per prefix | `docs/api/hexk_uid.md` |
| `hexk_value_wrapper.sv` | `hexk_value_wrapper #(T)`: a packed value as a `uvm_object`, compared with a tolerance | `docs/api/hexk_value_wrapper.md` |
| `hexk_meta_item.sv` | `hexk_meta_item #(T)`: an item with its time, ID and source | `docs/api/hexk_meta_item.md` |
