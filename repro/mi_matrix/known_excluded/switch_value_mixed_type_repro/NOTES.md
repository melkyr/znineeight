# switch_value_mixed_type_repro — D15 reject contract

Phase 3.5 D15 fixture. Value-switch prongs have non-unifiable types:
`int_literal` (1) and `bool` (`true`). After the D15 fix this is a clean
level-0 type-mismatch reject.

Expected for every source file below, under both `-ffast` and `-fsafe`:

- `--check` rc=2 and `--dump-c89` rc=2;
- exactly one `error[3000]` with message
  `type mismatch in switch expression -- prong type may not be compatible with
  the switch expression type` at the mismatching prong;
- 0 `.c` emitted.

Cases:

| File | Shape |
|---|---|
| `main.zig` | direct: `return switch (n) { 0 => 1, else => true }` in an `i32` return |
| `infer.zig` | inferred: `var x = switch (...)` with no declared/expected type |
| `use.zig` | inferred then used as an integer (`return x + 1`) |
| `reverse.zig` | reverse prong order (`0 => true, else => 1`) |

Before the fix (HEAD `32473a03` / investigation base `3cec507a`) all four were
accepted rc=0, the switch was typed as the first prong, and a `.c` was emitted.
See
`.superpowers/sdd/2026-10-29-phase35-defects-plan/task-d15-investigation-report.md`.

Do NOT add this directory to the live corpus; it stays under `known_excluded/`
(never enumerated by `scripts/corpus/list_corpus_dirs.sh`).
