# cdecl_def_ok — D5 bare/`"c"` extern definition

Phase 3.5 Task 0 repro (test-only; no fix here).

Both `extern fn` and `extern "c" fn` with a body must emit a cdecl definition.
Pre-fix evidence is in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.
