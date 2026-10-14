# src/uvm/report

Reporting.

| File | Content | Contract |
|---|---|---|
| `hexk_report_server.sv` | `hexk_report_server`: the layout of messages, ID triggers, the summary | `docs/api/hexk_report_server.md` |
| `hexk_report_cfg.sv` | `hexk_report_cfg`: the settings of the server | `docs/api/hexk_report_server.md` |
| `hexk_msg_listener.sv` | `hexk_msg_listener`: what a class implements to be told of messages | `docs/api/hexk_report_server.md` |
| `hexk_check_stats.sv` | `hexk_check_stats`: passed and failed checks per ID, and the expected failures | `docs/api/hexk_check_macros.md` |
| `hexk_report_catcher.sv`, `hexk_report_catcher_rule.sv` | `hexk_report_catcher`: expected and demoted messages for negative tests | `docs/api/hexk_report_catcher.md` |
