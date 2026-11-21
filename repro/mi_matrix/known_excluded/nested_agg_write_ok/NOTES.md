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

Post-fix sibling contracts (Task 2 fix round 1):

| Sibling | Contract |
|---|---|
| `sibling_field_array_assign.zig` | build 0, run 0, stdout `21 24\n` |
| `sibling_slice_of_array.zig` | build 0, run 0, stdout `21 22 23 24\n` |
| `sibling_nested_chain.zig` | build 0, run 0, stdout `5 6\n` |
| `sibling_pointer_aggregate.zig` | build 0, run 0, stdout `7 8\n` |
| `sibling_slice_assign_array_rhs.zig` | build 0, run 0, stdout `31 34\n` |
| `sibling_slice_assign_len_mismatch.zig` | clean reject: rc 2, 0 `.c` |
| `sibling_slice_assign_elem_array.zig` | clean reject: rc 2, 0 `.c` |

Full evidence and dispositions: `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
