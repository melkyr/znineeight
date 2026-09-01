# nested_field_store_xmod — Defect-C repro (same-module nested field-store write-back)  [Task R2, 2026-08-13]

## What it tests
A **2-level nested field-access store** — `o.inner.a = v; o.inner.b = v + 1;` —
inside a same-module struct-in-struct (`Inner` nested in `Outer`), then the values
are READ back and printed. Proves whether the store write lands on `o` at all.
Struct-in-struct (not union-specific) proves the GENERAL defect: the inner base
`o.inner` is a 2+ level field access (level 1 = `o.inner`, level 2 = `.a`).
Prints `o.inner.a` then `o.inner.b`.

## The compiler gap
`lowerFieldStore` (`sf/src/lower.zig:844`) lowers the store base with
`base_temp = lowerExpr(self, fa_node.child_0)` (`lower.zig:860`) — for a NESTED
field-access lvalue (`o.inner.a`), `fa_node.child_0` is itself a field-access
(`o.inner`) and `lowerExpr` lowers it as an **rvalue COPY**, not an lvalue
projection. The emitted C is:

```c
zT_5 = o.inner;    // rvalue copy of the inner struct into a throwaway local
zT_5.a = v;        // store mutates the COPY
zT_8 = o.inner;    // second copy (still uninitialized o.inner)
zT_8.b = zT_7;     // store mutates the COPY
return o;          // o.inner never written
```

The write-back to `o` is DROPPED — the store mutates throwaway locals. Reading
back `o.inner.a` / `o.inner.b` then prints uninitialized garbage. Same root cause
as the lisp_interpreter blocker `v.data.Cons.car = car` (F3's Defect C). The
zig0 oracle emits the direct `o.inner.a = v;` (lvalue-projected store).

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 4 modules emit (main, lib, std, std_io).
- **gcc -c rc=0**, link rc=0.
- **run rc=0** — prints `-163754450-388473816` (uninitialized garbage; expected
  pre-fix: write-back dropped). NOT `4243`.
- Emitted `lib.c`: `zT_5 = o.inner; zT_5.a = v;` / `zT_8 = o.inner; zT_8.b = zT_7;`
  — the rvalue-copy store pattern (write-back dropped).
- Corpus classifier: **FAIL** (OK-by-gate / runtime-gap-tracked — compiles and
  runs, prints wrong values; NOT counted as a raw corpus FAIL).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy (zig0 cannot parse the post-F4 `@putChar`/`@stdoutWrite`
std_io builtins, so the oracle copy uses a `__bootstrap_print_int`-based std_io —
the F4 wrappers are absent from `sf/src/include/zig_runtime.c`; the oracle emits its
own `zig_runtime.c` carrying `__bootstrap_print_int`). zig0 rc=0, gcc rc=0, run
prints **`4243`** — the store write lands correctly (oracle emits `o.inner.a = v;`).

## Expected classification
FAIL pre-fix (runtime gap: nested lvalue field-store write-back dropped) → OK
post-fix. Guards Defect C (F3 gate) — same-module variant.
