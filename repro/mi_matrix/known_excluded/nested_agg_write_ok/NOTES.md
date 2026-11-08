# nested_agg_write_ok — D7.3 nested aggregate write

Phase 3.5 Task 0 repro (test-only; no fix here).

Main shape: `fill(peers[i].field[0..])` (the wireguard demo shape). The callee
writes through a slice that points into a by-value temporary of `peers[i]`, so
the store is lost.

Measured at BASE (`zig1_5_clean` md5 `cd8d283b…`):

```text
dump rc=0, build rc=0, run rc=0
stdout:  0 0 0 0        (expected post-fix: 77 88 77 88)
```

Same result under `-ffast` and `-fsafe`. `sibling_pointer_aggregate.zig`
(the explicit-pointer workaround) prints `7 8` and is the control.
`sibling_nested_chain.zig` loses the write (`0 0`).
`sibling_field_array_assign.zig` emits an illegal C array assignment;
`sibling_slice_of_array.zig` hard-fails with
`error[3043]: internal: unsupported assignment l-value`.

Full evidence and dispositions: `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
