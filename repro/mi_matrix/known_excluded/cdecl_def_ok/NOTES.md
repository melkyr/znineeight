# cdecl_def_ok — D5 bare/`"c"` extern definition

Phase 3.5 Task 0 repro (test-only; no fix here).

Both `extern fn` and `extern "c" fn` with a body must emit a cdecl definition.
Pre-fix evidence is in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.

Sibling probe in this directory:

- `sibling_fnptr.zig` — the cdecl definition called directly and through a
  function value (the `atexit(cb)` / callback-registration shape). The value
  must reference the original symbol, not a mangled local name.
- `sibling_xmod_fnptr.zig` + `sibling_xmod_cv.zig` — the same function-value
  shape when the extern definition lives in another module; the value must
  still use the original C symbol (fix round 2).

