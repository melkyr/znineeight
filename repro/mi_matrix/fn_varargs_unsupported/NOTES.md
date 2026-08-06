# fn_varargs_unsupported — OK  [4-item compiler gaps plan, Task F3, 2026-08-06]

## What it tests
Varargs `...` in an `extern fn` parameter list. The parser previously had NO
varargs support, so `extern fn printf(fmt: [*]const u8, ...) i32;` was
rejected at the frontend with `error[2000]`.

## Origin (operator ruling P0-D)
The comptime-arithmetic plan's original draft source for the P0 repros used
`extern fn printf(fmt: [*]const u8, ...) i32;`. During P0 the implementer
discovered this does **not** compile: parser.zig had no varargs (`...`)
support → `error[2000]: expected identifier but found token` at the `...`.
The operator ruled (P0-D) to record this gap as a standalone tracking repro,
separate from the comptime-arithmetic repros (whose sources were corrected
to fixed-arity `printf` — see comptime_binop_not_folded/NOTES.md).

## Measured result — PRE-FIX (2026-08-06, /tmp/z1/zig1, fresh bootstrap)
- dump rc=2, stderr: `error[2000]: expected identifier but found token` (at `...`).
- 0 `.c` emitted (frontend parse failure).
- gcc not reached.

## Measured result — POST-FIX (2026-08-06, /tmp/f3z1/zig1, Task F3)
- dump rc=0 (varargs `...` accepted; `...` is trailing-only — mid-list
  `fn(a, ..., b)` is still `error[2000]`).
- 1 `.c` emitted; `gcc -c` clean.
- The fn type is registered (`FNPTR_*_FN_int_unsigned_cha` typedef in
  zig_special_types.h). Emission of `...` in the C fn prototype is pending
  F5 (per AMENDMENT 3 the lowerer/emitter flag-read is F5's job); the extern
  fn's C forward declaration is also not emitted — pre-existing behavior for
  all extern fns (fixed-arity externs emit call sites only, no prototype).

## Classification
- **OK** — parses and emits cleanly (dump rc=0, gcc rc=0).
- **Correction (Task F3):** this NOTES.md previously claimed zig0 (the
  oracle) accepts varargs `extern fn` — **FALSE**. zig0 rejects ALL varargs
  forms: `zig0 -o out.c main.zig` → `error: syntax error ... hint: Expected
  parameter name` at the `...` (rc=134, 0 `.c`). So this repro was never a
  green-guard; it was a real parser gap, now fixed by F3.
