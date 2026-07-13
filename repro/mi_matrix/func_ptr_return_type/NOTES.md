# func_ptr_return_type — RED

## What it does
Function `getOp` returns a function pointer (`fn(i32,i32) i32`). `main` calls the returned pointer with `(10, 5)` and prints the result — expects `15` once fixed.

## zig1 RED evidence
- **dump rc:** 0
- **gcc error (7 errors):** `unknown type name 'zT_DDF5E411_FP_int_int_int'`
  - Lines 12, 34, 51, 54, 56, 64 of generated C reference the typedef, but it is never emitted.

## Oracle (zig0)
- **Source 1:** `examples/zig0/func_ptr_return/func_ptr_return.zig` — z0 dump rc=0, gcc `main.c` errors=0
- **Source 2:** `repro/mi_matrix/func_ptr_return_type/main.zig` — z0 dump rc=0, gcc `main.c` errors=0
- **Verdict:** oracle clean → zig1 bug.

## Layer
`c89_emit` — FP-return typedef referenced but not hoisted/emitted. The typedef for a function-returning-function-pointer type is used in forward declarations, function signatures, and local vars but never `typedef`'d at the top of the output.

## Expected post-fix
Prints `15`.

## Root Cause Investigation (2026-07-12)

### Root cause: `sf/src/c89_emit.zig:887-888`

**Mechanism:** cname-based dedup in `emitSpecialTypes` marks the dedup key unconditionally
(line 888: `hash_mod.u32ToU32MapPut(...)`) **before** `emitTypeDefinition` produces output
(line 889). A non-FP fn_type (flags & 1 == 0, e.g., `add` or `sub`) consumes the dedup slot
without ever emitting a typedef — because `emitTypeDefinition` → `emitTypeBody` for fn_type
(line 1160-1162) gates on `(ty.flags & 1) != 0` and skips `emitFnPtrType` when the flag is
unset. The actual function-pointer fn_type (flags & 1 == 1, MarkFnPtrUsed) shares the same
signature-derived cname (`zT_DDF5E411_FP_int_int_int`) and is blocked by the dedup.

**Collateral:** `sf/src/c89_emit.zig:589-633` — `getCTypeName` for fn_type builds the C type
name from return-type + param-types (prefix `FP_`), not from `name_id`. Thus `add`'s fn_type
(name_id="add"), `sub`'s fn_type (name_id="sub"), and the anonymous FP fn_type
(name_id="fnt_6_6_6") — all sharing signature `fn(i32,i32)i32` — produce identical cnames.

**GDB confirmation:**
- `typeRegistryMarkFnPtrUsed` breakpoint: HIT (1× from `resolveTypeExprFull`) — flags=1 IS set.
- `emitFnPtrType` breakpoint: **never hit** — the typedef-emitting function is unreachable due
  to dedup skip.

### Oracle contrast

zig0 emits C89-native inline function-pointer syntax — no typedef needed:
```c
static int (* zF_6e336541_4cd8364b_getOp(unsigned char))(int, int);
```
Valid C89, 0 gcc errors. zig1 uses typedefs (`zT_DDF5E411_FP_int_int_int`), which is also valid
C89 when the typedef definition exists — but the dedup bug prevents it.

### Proposed fix approach (NOT applied)

Move dedup marking AFTER `emitTypeDefinition`, and only mark when a typedef was actually emitted.
Or, before the dedup add (line 887), skip fn_types with `(ty.flags & 1) == 0`.
Or, differentiate `getCTypeName` for plain function types vs function-pointer types to avoid
cname collisions entirely.

Exact location in `c89_emit.zig`:
- **Line 887-889** (dedup gating, both sub-pass 2a and 2b analogous patterns)
- **Line 1160-1162** (fn_type emission gate checks `flags & 1`)

Confirmed: NO `sf/src/` files modified. GDB used for breakpoint verification.
