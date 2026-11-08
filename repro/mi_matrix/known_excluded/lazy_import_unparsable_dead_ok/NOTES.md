# lazy_import_unparsable_dead_ok — D3 unparsable dead-arm import

Phase 3.5 Task 0 repro (test-only; no fix here).

The dead arm imports `unparsable.zig`, which exists but is syntactically
invalid. Post-fix the dead arm is never opened, so the compile succeeds.

Pre-fix evidence and post-fix contract are recorded in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
