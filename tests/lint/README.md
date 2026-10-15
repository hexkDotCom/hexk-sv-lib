# tests/lint

Configuration and waivers of the Gate 1 tools. A waiver always names the rule and the reason.

| File | Tool |
|---|---|
| `.verible-format` | flags for `verible-verilog-format` |
| `.rules.verible_lint` | rule configuration for `verible-verilog-lint` |
| `verible.waiver` | waivers for `verible-verilog-lint` |
| `slang.f` | options for slang elaboration |
| `verilator.vlt` | Verilator lint waivers |
| `hexk_style_check.waiver` | waivers for `scripts/hexk_style_check.py` |
| `hexk_core_enum_lint.sv` | a lint case for Verilator `-Wall`: user code that only prints the name of an enum of the core |
