# lazy_import_fold_ok — D3 evaluator-foldable dead import

Phase 3.5 Task 0 repro (test-only; no fix here).

`missing.zig` deliberately does not exist. `exists.zig` is the live arm.

Sibling entries (same directory; not corpus entries):

- `sibling_switch.zig` — `switch (1 == 1)`.
- `sibling_and_or.zig` — `(1 == 1) and true`.
- `sibling_nested.zig` — nested conditional `@import`.
- `sibling_live_arm.zig` — condition false so the `else` arm is live.

Pre-fix evidence and post-fix contract are recorded in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
