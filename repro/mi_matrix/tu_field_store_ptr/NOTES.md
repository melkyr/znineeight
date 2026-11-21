# A1: Hand-rolled Tagged Union — Field Store Through @ptrCast Pointer

**Pattern:** Field-store to a struct through a `@ptrCast`-derived pointer.

**RED (main.zig):** Stores to union data field via @ptrCast pointer. ICEs with error[3043].
**GREEN (main_green.zig):** Same pattern but only stores to scalar fields (no union member). Regression guard.

**Category:** A1 — union field-store through pointer

## RED Result (2026-07-30)
- Dump rc: 3
- gcc rc: 0
- Classification: ICE
- Stderr: error[3043]: internal: unsupported field-store base (node 43)
