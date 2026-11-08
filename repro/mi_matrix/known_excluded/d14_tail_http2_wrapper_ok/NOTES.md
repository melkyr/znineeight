# d14_tail_http2_wrapper_ok — D14 exact-shape tail return

Phase 3.5 Task 0.1 repro (test-only; no fix here).

The local exact `Http2Error` shape (15 members) with a runtime id, in the
plain tail form `return wait2(c, id);`. Pre-fix the emitted step function is
GCC-incompatible (RED); the post-fix contract is stdout `42 0\n0 1\n`, rc 0,
under `-ffast`/`-fsafe`.

The pre-existing `sibling_tail.zig` in
`repro/mi_matrix/async_wrapper_eu_payload_ok_xmod/` remains the `error{Boom}`
tail probe and is unchanged.

Evidence is recorded in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
