# src/uvm/eot

End of test and liveness.

| File | Content | Contract |
|---|---|---|
| `hexk_objectable.sv` | `hexk_objectable`: what a component that can be busy implements | `docs/api/hexk_objection_aggregator.md` |
| `hexk_objection_aggregator.sv`, `hexk_objection_member.sv` | `hexk_objection_aggregator`: holds the phase while a member is busy | `docs/api/hexk_objection_aggregator.md` |
| `hexk_checkable.sv` | `hexk_checkable`: what a component with an end-of-test check implements | `docs/api/hexk_eot_registry.md` |
| `hexk_eot_registry.sv` | `hexk_eot_registry`: runs the end-of-test checks | `docs/api/hexk_eot_registry.md` |
| `hexk_watchdog.sv` | `hexk_watchdog`: ends a test that runs too long and names what is busy | `docs/api/hexk_watchdog.md` |
