# nested_field_store_xmod2 — Defect-C repro (cross-module nested field-store write-back)  [Task R2, 2026-08-13]

## What it tests
A **2-level nested field-access store** across a module boundary: `lib.zig`
defines `Inner`/`Outer` (struct-in-struct), `main.zig` declares
`var o: lib_mod.Outer = undefined;` and stores `o.inner.a = 7; o.inner.b = 8;`
directly, then prints `o.inner.a` then `o.inner.b`. Cross-module variant of
`nested_field_store_xmod`: the `Outer` type comes from the type-registry-driven
cross-module path (imported struct type), proving the defect is identical there.

## The compiler gap
Identical root cause to the same-module variant: `lowerFieldStore`
(`sf/src/lower.zig:844`) lowers the store base with
`base_temp = lowerExpr(self, fa_node.child_0)` (`lower.zig:860`) — for the nested
field-access lvalue (`o.inner.a`), `fa_node.child_0` is itself a field-access
(`o.inner`) and `lowerExpr` lowers it as an **rvalue COPY**, not an lvalue
projection. The emitted `main.c` is:

```c
zT_5 = o.inner;    // rvalue copy of the inner struct
zT_5.a = zT_4;     // store mutates the COPY (zT_4 = 7)
zT_7 = o.inner;    // second copy
zT_7.b = zT_6;     // store mutates the COPY (zT_6 = 8)
zT_9 = o.inner;    // read-back copy (o.inner never written)
zT_10 = zT_9.a;    // garbage
zT_12 = o.inner;
zT_13 = zT_12.b;   // garbage
```

The write-back to `o` is DROPPED — stores and reads both go through rvalue copies
of the never-written `o.inner`. The type-registry-driven cross-module path fails
identically to the same-module case. The zig0 oracle emits the direct
`o.inner.a = 7;` / `o.inner.b = 8;` (lvalue-projected store).

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 4 modules emit (main, lib, std, std_io).
- **gcc -c rc=0**, link rc=0.
- **run rc=0** — prints `-6299663-170851872` (uninitialized garbage; expected
  pre-fix: write-back dropped). NOT `78`.
- Emitted `main.c`: `zT_5 = o.inner; zT_5.a = zT_4;` / `zT_7 = o.inner;
  zT_7.b = zT_6;` — the rvalue-copy store pattern (write-back dropped).
- Corpus classifier: **FAIL** (OK-by-gate / runtime-gap-tracked — compiles and
  runs, prints wrong values; NOT counted as a raw corpus FAIL).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy (zig0 cannot parse the post-F4 `@putChar`/`@stdoutWrite`
std_io builtins, so the oracle copy uses a `__bootstrap_print_int`-based std_io —
the F4 wrappers are absent from `sf/src/include/zig_runtime.c`; the oracle emits its
own `zig_runtime.c` carrying `__bootstrap_print_int`). zig0 rc=0, gcc rc=0, run
prints **`78`** — the store write lands correctly (oracle emits `o.inner.a = 7;`).

## Expected classification
FAIL pre-fix (runtime gap: nested lvalue field-store write-back dropped) → OK
post-fix. Guards Defect C (F3 gate) — cross-module variant.
