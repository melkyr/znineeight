# opt_extern_ptr_file — D2: Optional-wrapping of extern fn returning `?*T` (opaque ptr)

## RED status
**RED** — zig1 fails; zig0 oracle passes.

## What it does
Declares an opaque type `File = void` and an extern function `fopen` returning `?*File` (optional pointer-to-opaque). The C-level `fopen` returns a raw `FILE *`. zig1 emits C that assigns the raw C return value directly to the `Opt<File>` struct without wrapping (`has_value=1, value=raw`). gcc rejects: `incompatible types when assigning to type 'zT_733AFA29_Opt_zT_811C9DC5_' from type 'int'` (or `'FILE *'` with `@cInclude("<stdio.h>")`).

## zig1 RED evidence
- **dump rc**: 0
- **gcc error**: `incompatible types when assigning to type 'zT_733AFA29_Opt_zT_811C9DC5_' from type 'int'` (line 46)
  - With `@cInclude("<stdio.h>")` added, the error reads `from type 'FILE *'` — same class, more specific.
- **Root cause**: zig1 treats the Z98 `extern fn ... ?*File` return value as if the C function already returns an `Opt` struct. It does not emit the null-check/wrap sequence that zig0 produces.

## Oracle behavior
- **zig0 dump rc**: 0
- **oracle main.c gcc error count**: 0
- **Conclusion**: **Pure zig1 bug** — zig0 correctly emits `Optional_Ptr_void` wrapping with `if (raw != 0) { .has_value = 1; .value = raw; } else { .has_value = 0; }`.

## @cInclude dependency
The repro does **not** include `@cInclude("<stdio.h>")` because zig0 crashes on it (rc=134). Adding it to the repro (zig1-only) produces the same error class with `FILE *` instead of `int` in the gcc message. The underlying optional-wrapping failure is identical.

## Layer
sema/type-registry (optional-wrap of extern pointer return) / C89 emission (missing LIR wrap_optional for extern fn returning optional)

## Must-not-fail status
**Tracked as must-not-fail.** Per operator directive: D2 must NOT fail, even if the zig0 oracle also fails it. (Oracle does not fail it — this is a pure zig1 bug.)

## Expected post-fix output
`0` (fopen of "none.txt" returns null → else branch → `__bootstrap_print_int(0)`).
