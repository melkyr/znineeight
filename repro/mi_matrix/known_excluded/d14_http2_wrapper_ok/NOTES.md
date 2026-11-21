# d14_http2_wrapper_ok — D14 real std_http2 wrapper shapes

Phase 3.5 Task 0.1 repro (test-only; no fix here).

`main.zig` — non-tail `std_http2.http2Wait` and `http2Get` wrappers returning
`Http2Error!u32` with a runtime id. These are compile-only for the wrapper
paths: exercising the suspension needs a live HTTP/2 peer, so the fixture
proves zig1 emission and the C build (`build_target.sh`), not runtime.

`sibling_wait_tail.zig` — the tail-return form
(`return waitId(c, id);`). This is the reproducible RED (GCC type mismatch in
the emitted step function); it stays compile-only for the same server reason.

Evidence is recorded in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
