# RED repro: array-value local copy `const temp = a[i]` — Symptom B1

**Status:** RED (known-failing corpus repro). zig1 emits direct array-type assignments; gcc rejects with `assignment to expression with array type`.

## What it does

`swap(a: *[10]i32, i, j)` copies an array element by value into a `const temp`, then
writes elements back. The emitted C declares `temp` as an array type (`zT_*_Arr_int_10`)
and uses direct assignment (`temp = zT_5;` / `a[i] = zT_7;` / `a[j] = temp;`), which is
illegal C89 — arrays are not assignable. A per-element copy loop is required instead.

## zig1 symptom (RED)

- **dump:** `sf/build/out_release/zig1 --dump-c89 ...` → rc=0 (no crash)
- **gcc -c:** FAIL (`error: assignment to expression with array type`) on 5 lines:
  - `/tmp/B1.c:25:10: error: assignment to expression with array type`
  - `/tmp/B1.c:26:10: error: assignment to expression with array type`
  - `/tmp/B1.c:44:10: error: assignment to expression with array type`
  - `/tmp/B1.c:47:10: error: assignment to expression with array type`
  - `/tmp/B1.c:50:10: error: assignment to expression with array type`

## zig0 oracle cross-check

- **dump:** `./sf/build/zig0 --header-priority-include -o /tmp/B1or/o.c ...` → rc=0
- **gcc -c:** 0 errors — zig0 produces valid C89 with element-copy loops → proves zig1 bug.

## Layer

`c89_emit` — array l-value assignment must emit an element-copy loop. `temp` is declared
as an array type (`zT_*_Arr_int_10`) and then assigned directly instead of via the
array-copy marker pattern.

## Expected post-fix output

Program prints `11` (= `arr[0]` after swapping indices 0 and 1 in `{12, 11, 13, ...}`).

## Root Cause Investigation (2026-07-12)

### Root cause

**`sf/src/lower.zig:1444-1445`** — In `lowerExpr` for `AstKind.index_access`, when the
base is a pointer type (`ptr_type` or `many_ptr_type`), the element type is set to
`reg.ptr_items[...].base`, which is the pointer's pointee type. For `a: *[10]i32`,
this gives `[10]i32` instead of the correct element type `i32`. Zig semantics require
that indexing into a `*[N]T` pointer auto-dereferences through to the array element T.
The code should chain: if the pointer's base is itself an array type, then the indexing
element type is the array's element type (i.e., `reg.array_items[...].elem`), not the
pointer's base. This wrong element type propagates downstream: `a[i]` produces a temp
of type `[10]i32`, which then feeds into `.load_index`, `.assign`, `.store_local`, and
`.assign_index` instructions, all operating on array-typed values.

### Secondary emission defects

Three emitter handlers in `sf/src/c89_emit.zig` lack array-type guarding and would emit
illegal C89 direct assignments for array-typed operands:

- **`sf/src/c89_emit.zig:2699-2712`** (`.load_index`): Emits `result = base[idx];` — no array check.
- **`sf/src/c89_emit.zig:2416-2444`** (`.store_local`): Emits `name = val;` — no array check.
- **`sf/src/c89_emit.zig:2286-2317`** (`.assign_index`): Emits `base[idx] = src;` — no array check.

The `.assign` handler (`c89_emit.zig:2200-2272`) does have an array-copy loop (lines
2229-2263), but it relies on finding the destination temp in `hoisted_temps`; if the
lookup fails silently, it falls through to the direct-assignment path. In the emitted
`/tmp/x.c`, the `.assign` handler correctly emits element-copy loops (lines 27–42), but
the `.store_local` and `.load_index` handlers emit direct assignments first (lines 25–26),
which gcc rejects before reaching the loops.

### Oracle contrast

zig0 oracle output for the `swap` function:
```c
static void zF_0f70258b_c791e764_swap(int (* a)[10], usize i, usize j) {
    int temp;
    temp = (*a)[i];
    (*a)[i] = (*a)[j];
    (*a)[j] = temp;
}
```
zig0 explicitly dereferences the pointer (`*a`) before indexing, yielding `int`, so all
variables are scalar and direct assignment is valid C89. zig0 never creates an
array-typed temp — it correctly lowers `a[i]` to `i32`.

zig1 output:
```c
typedef int zT_E0229AA2_Arr_int_10[10];
void zF_64ED874E_swap(zT_E0229AA2_Arr_int_10* a, unsigned int i, unsigned int j) {
    zT_E0229AA2_Arr_int_10 zT_5;
    zT_E0229AA2_Arr_int_10 temp;
    zT_5 = a[i];   /* .load_index — ILLEGAL: zT_5 is array type */
    temp = zT_5;   /* .store_local — ILLEGAL: temp is array type */
    ...
}
```
The array types leak because `a[i]` on `*[10]i32` is lowered with element type `[10]i32`.

### Proposed fix approach

**Primary fix in `sf/src/lower.zig:1444-1445`:** When the base type is `ptr_type` and
the pointer's `.base` is an array type, set `elem_type` to the array's `.elem` instead
of the pointer's `.base`. Pseudocode:
```zig
} else if (bty.kind == type_mod.TypeKind.ptr_type) {
    var base_ty = reg.ptr_items[...].base;
    var base_info = reg.types_items[base_ty];
    if (base_info.kind == type_mod.TypeKind.array_type) {
        elem_type[0] = reg.array_items[base_info.payload_idx].elem;
    } else {
        elem_type[0] = base_ty;
    }
} else if (bty.kind == type_mod.TypeKind.many_ptr_type) {
    elem_type[0] = reg.ptr_items[...].base; // unchanged for many pointers
}
```

**Secondary fix in `sf/src/c89_emit.zig`:** Add array-type guards to `.load_index`
(line 2699), `.store_local` (line 2416), and `.assign_index` (line 2286) to emit
element-copy loops when operand types are arrays — matching the pattern already
present in `.assign` (lines 2229–2263). This is defensive; the primary fix alone
should resolve this repro.

**Fix belongs primarily in `lower.zig`.** The core bug is a semantic error in the
lowering of `*[N]T` pointer indexing — the element type is computed incorrectly.
Fixing this makes `a[i]` return `i32`, and no array-typed values ever reach the
emitter, so no array-copy loops are needed for this case.

**Fix is NOT applied — investigation only.**
