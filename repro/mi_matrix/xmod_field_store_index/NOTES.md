# Symptom A: unsupported field-store base (error[48])

## Status: RED

## Discovered Minimal Trigger

The ICE requires **two factors across a cross-module boundary** (verified on VALID Z98
with a proper `pub fn main`):

1. **Imported module** (`types.zig`): a struct containing a **const-sized array**
   (`[N]T` where `N` is a *named constant*, NOT a literal) whose element is itself a
   struct, AND a `pub fn` performing an **array-element field store**
   (`t.arr[0].x = 1`).
2. **Main module** (`main.zig`): a real `@import` of that module, used from `main`
   (`var d: t.T = undefined; t.init(&d);`).

Neither factor alone triggers the ICE (controller-verified, all dump rc=0 = clean):
- **Single-file** (everything inlined into one file, no `@import`) → CLEAN. So the
  **cross-module `@import` is load-bearing.**
- **`[1]` literal** array size instead of `[N]` named-const → CLEAN. So the
  **named-const array size `[N]` is load-bearing.**
- Removing the `init` field-store fn → CLEAN. So the **array-element field store
  `t.arr[0].x = 1` is load-bearing.**

**Load-bearing combination:** cross-module `@import` + named-const-sized
array-of-struct (`[N]struct{...}`) + array-element field store on the imported type.
The cross-module boundary shifts node indices during lowering into a state where the
field store hits `iceFieldStoreUnsupported`.

## Error Name is Misleading

Despite the text "unsupported field-store base", the original failing `io.zig`
(`examples/z98/lzw/`) triggered on `buf[i] = @intCast(u8, ...)` — an array-element
store, not a literal struct field store. The ICE fires from array-element/field stores
whose base resolution goes wrong after cross-module lowering, not only on classic
`s.field = x`.

## History / Correction

The plan's original Symptom-A assumption (a simple `arr[i].field = x` triggers it) was
WRONG — that compiles clean at HEAD b206a3f3. An intermediate reduction attempt used a
top-level `_ = @import(...)` + `var x` form; that is **invalid Z98** (file-scope `_ =`
and bare `var` are syntax errors — zig0 aborts on it), so it was NOT a faithful repro.
This repro uses the correct `pub fn main`-wrapped form: zig1 ICEs, zig0 compiles clean.

## Layer

Lowerer — `iceFieldStoreUnsupported` path at `lower.zig:733`/`758`.

## zig1 RED Evidence

- `sf/build/out_release/zig1 --dump-c89 repro/mi_matrix/xmod_field_store_index/main.zig`
- dump rc=3
- stderr: `error[48]: internal: unsupported field-store base (node 37)`

## zig0 Oracle Result

- `zig0 --header-priority-include -o /tmp/.../o.c main.zig` → dump rc=0
- `gcc -m32 -std=c89 -c` of the emitted `main.c` → 0 errors
- Oracle OK → zig1 bug confirmed (pure zig1 bug).

## Expected Post-Fix Behavior

zig1 should compile this repro cleanly (dump rc=0, no error[48]), matching the zig0
oracle.
