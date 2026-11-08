# stdcall_def_ok — D5/D10 extern "stdcall" definition

Phase 3.5 Task 0 repro (test-only; no fix here).

The ABI evidence (objdump `ret $N`, Wine callback host) stays Task 5; this
fixture proves the definition is emitted and callable. Pre-fix evidence is in
`docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`.

Sibling probes in this directory:

- `sibling_fnptr.zig` — direct call vs call through a convention-qualified
  function pointer.
- `sibling_mismatch.zig` — prototype/definition convention mismatch.
- `sibling_variadic.zig` — variadic `stdcall` declaration.
