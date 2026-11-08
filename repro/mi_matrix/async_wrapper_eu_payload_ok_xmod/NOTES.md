# async_wrapper_eu_payload_ok_xmod — D14 suspending EU payload

Phase 3.5 Task 0 repro (test-only; no fix here).

Sibling probes in this directory:

- `sibling_void.zig` — wrapper returns `E!void`.
- `sibling_optional.zig` — wrapper returns `?u32`.
- `sibling_aggregate.zig` — wrapper returns `E!Pair` (aggregate payload).
- `sibling_tail.zig` — direct tail `return wait2(c);`.

Pre-fix evidence and post-fix contract are recorded in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
