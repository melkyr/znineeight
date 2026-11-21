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

## Root Cause Investigation (2026-07-12)

### Root Cause

The ICE fires at **`sf/src/lower.zig:777`** inside `lowerFieldStore`. At this point the
resolved-type lookup for the index-access node (node 34, `t.arr[0]`) returns
type_id=1 (TYPE_VOID, kind=void_type, enum value 1). TYPE_VOID does not match
struct/slice/tagged_union, so control falls to the `else` branch:
```zig
} else {
    iceFieldStoreUnsupported(self, diag_node_idx);  // line 777
}
```

**Propagation chain:**

1. `semanticAnalyzerResolveFnBody` (`sf/src/semantic_analyzer.zig:1245`) looks up the
   resolved type for the parameter type-expression `*T` (child_0 of the param `t`).
   It calls `resolvedTypeTableGet(self.type_table, pnode.child_0)` — this returns **null**
   because `resolveAllFnTypes` (`sf/src/main.zig:419-422`) ran `resolveTypeExpr` on
   `*T` but `resolveTypeExprFull` returned TYPE_UNDEFINED (the named-const `[N]` array
   size inside the imported struct type prevents full type resolution during that pass).
   The parameter `t` therefore gets local-decl type `TYPE_UNDEFINED` (kind 34).

2. When `semanticAnalyzerResolveFieldAccess` resolves the field-access `t.arr` at
   **`sf/src/semantic_analyzer.zig:329`**, it resolves `t` via
   `semanticAnalyzerResolveExpr`. The ident-expr `t` returns `TYPE_UNDEFINED`
   from its local-decl entry. Since `TYPE_UNDEFINED`'s kind (34) is not ptr, struct,
   union, tagged_union, module, or slice, control reaches the `else` branch at
   **`sf/src/semantic_analyzer.zig:424-426`**, which sets the field-access resolved
   type to TYPE_VOID and returns TYPE_VOID.

3. `semanticAnalyzerResolveIndexAccess` (`sf/src/semantic_analyzer.zig:1560`) sees
   the base (`t.arr`) resolved to TYPE_VOID, sets the index-access node's resolved
   type to TYPE_VOID, and returns TYPE_VOID.

4. `lowerFieldStore` (`sf/src/lower.zig:737`) calls `resolvedTypeTableGet` for the
   index-access node and gets TYPE_VOID. TYPE_VOID's kind (void_type) does not match
   struct/slice/tagged_union → **line 777 ICE**.

**Why cross-module + `[N]` is load-bearing:** The named const `N` inside the imported
`types.zig` causes `resolveTypeExprFull` inside `resolveAllFnTypes` to fail to fully
resolve the parameter type `*T` for `init(t: *T)`. This is because `T` itself is
defined as `struct { arr: [N]struct { x: i32, }, }` and `[N]` depends on const `N`
which, while defined in the same imported module, is not fully evaluated during the
type-resolution pass. When everything is in one file (inline), or when `[1]` replaces
`[N]`, the type resolver succeeds, `*T` resolves correctly, and the parameter gets its
proper `ptr_type` instead of TYPE_UNDEFINED. The chain then resolves correctly:
`t`→ptr, `t.arr`→ptr-to-elem, `t.arr[0]`→struct_type, `.x`→i32, store→emit.

### Oracle Contrast (verified)

zig0 emits `t->arr[0].x = 1;` in the generated C (file `/tmp/or/types.c`):
```c
void zF_10be8ab8_705ae666_init(struct zS_10be8ab8_e022be49_T* t) {
    t->arr[0].x = 1;
}
```
The zig0 compiler correctly resolves `t.arr[0].x` as a store to a struct field through
a pointer-deref + array-index + field-access chain. zig0's type resolver fully
resolves `[N]` into the literal `1` before lowering, so the parameter type `*T` is
known, and the store dispatch finds the struct type and emits the correct `store_field`
LIR instruction. gcc -c of the oracle output = 0 errors, confirming the program is
valid Z98.

### Proposed Fix Approach (NOT APPLIED — investigation only)

Two possible fix strategies (neither applied):

**Strategy A — Robustness in `lowerFieldStore` (`sf/src/lower.zig:733-781`):**
When the resolved type for the base expression is TYPE_VOID or another unrecognized
kind, fall back to deriving the base type from `base_temp`'s hoisted-temp metadata
(`self.hoisted_temps[base_temp].type_id`). Since `lowerExpr(fa_node.child_0)` on line
736 already correctly lowers and loads the base expression, its temp type is known
and can be used to determine the struct/slice/tagged_union kind. This is the minimal
defensive fix that would handle the degraded case without fixing the semantic analysis.

**Strategy B — Fix `resolveAllFnTypes` cross-module const resolution:**
Ensure that `resolveAllFnTypes` (`sf/src/main.zig:383-448`) fully resolves parameter
types that depend on const-sized types from the same module. This would prevent the
TYPE_UNDEFINED from entering the local-decl table in the first place, making the
existing `lowerFieldStore` dispatch work correctly.
