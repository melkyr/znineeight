# fn_varargs_unsupported — FAIL  [comptime arithmetic folding plan, Task P0, operator ruling P0-D, 2026-08-06]

## What it tests
Varargs `...` in an `extern fn` parameter list — the parser has NO varargs
support, so `extern fn printf(fmt: [*]const u8, ...) i32;` is rejected at
the frontend with `error[2000]`.

## Origin (operator ruling P0-D)
The plan's original draft source for the P0 comptime-arithmetic repros used
`extern fn printf(fmt: [*]const u8, ...) i32;`. During P0 the implementer
discovered this does **not** compile: parser.zig has no varargs (`...`)
support → `error[2000]: expected identifier but found token` at the `...`.
The operator ruled (P0-D) to record this gap as a standalone tracking repro,
separate from the comptime-arithmetic repros (whose sources were corrected
to fixed-arity `printf` — see comptime_binop_not_folded/NOTES.md).

## Measured result (2026-08-06, /tmp/z1/zig1, fresh bootstrap)
- dump rc=2, stderr: `error[2000]: expected identifier but found token` (at `...`).
- 0 `.c` emitted (frontend parse failure).
- gcc not reached.

## Classification
- **FAIL** — a real frontend parse gap (0 `.c` with `error[2000]` ⇒ FAIL per
  the QUICK_REF classifier: "A repro that fails the frontend (dump emits 0
  `.c` files with a `error[NNNN]` diagnostic) is a FAILURE").
- Out of comptime-arithmetic scope; tracked as a known gap (like the
  std-lib-deferred import-gap repros) until the parser gains varargs support.
- Not a green-guard: zig0 (the oracle) accepts varargs `extern fn`, so this
  is not a correct rejection.
