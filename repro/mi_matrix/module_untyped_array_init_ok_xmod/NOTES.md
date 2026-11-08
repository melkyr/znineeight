# module_untyped_array_init_ok_xmod — D12 module-scope untyped array literal

Phase 3.5 Task 0 repro (test-only; no fix here).

## Shape

```zig
pub var arr: [3]u32 = .{ 1, 2, 3 };
```

plus a mutation and print. The typed control `[3]u32{ 1, 2, 3 }` already lowers
element-wise (`repro/mi_matrix/multiarray_literal_init_xmod`).

## RED (pre-fix evidence)

See the Phase 3.5 repro inventory
(`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`) for the exact
command, rc, emitted-C excerpt and gcc diagnostic captured at Task 0.

## GREEN contract

dump rc=0, gcc `-m32 -std=c89` clean, link+run rc=0, stdout `1 42 3\n`.

## Sibling probes (same directory, not corpus entries)

- `sibling_struct_array_untyped.zig` — `[2]Pair = .{ Pair{...}, Pair{...} }`.
- `sibling_2d_untyped.zig` — `[2][3]u8 = .{ .{...}, .{...} }`.
