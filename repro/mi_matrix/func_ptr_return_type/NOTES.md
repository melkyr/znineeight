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

## EX5 Fix-Approach Investigation (2026-07-13)

### Root cause reference (confirmed from Plan 3)

- `sf/src/c89_emit.zig:887-888` — `emitSpecialTypes` marks cname-derived dedup key in `emitted_type_set` unconditionally before `emitTypeDefinition`
- `sf/src/c89_emit.zig:589-633` — `getCTypeName` for `fn_type` derives cname from SIGNATURE (`FP_int_int_int`) ignoring `name_id`
- `sf/src/c89_emit.zig:1161` — fn_type handler only emits typedef when `(flags & 1) != 0`

Plain fn_types (`add`/`sub`, flags&1==0) and fn_ptr type (`fnt_6_6_6`, flags&1==1) share identical cname → plain fn_type consumes dedup slot, fn_ptr type blocked → `emitFnPtrType` never called.

### fn_type creation paths

| Path | Caller | name_id | flags&1 |
|------|--------|---------|---------|
| Function definitions | `semantic_analyzer.zig:299-396` | proto.name_id (e.g., "add") | 0 |
| fn_type AST resolution | `type_resolver.zig:772-774` | `fnt_<ret>_<p1>...` (e.g., "fnt_6_6_6") | 1 |
| lower operand types | `lower.zig:1772,2326,2328` | (unchanged) | 1 (MarkFnPtrUsed) |

`typeRegistryGetOrCreateFn` (`type_registry.zig:487-508`) deduplicates on `(kind==fn_type, name_id, module_id)` — so `add`, `sub`, and `fnt_6_6_6` are three DISTINCT Type entries. The cname collision is purely an artifact of `getCTypeName` ignoring `name_id`.

### Fix alternatives

**(a) cname distinction** — `getCTypeName` prefix differentiation
- **Where:** `c89_emit.zig:640-680` (fn_type branch)
- **What:** Check `ty.flags & 1`: plain fn → prefix `FN_`, fn_ptr → prefix `FP_`
- **Blast radius:** Small (~5 lines). fn_type cname used in 3 sites: emitSpecialTypes dedup (:932/981), pointer-deref (:566, always flags=1), emitFnPtrType (:1225, always flags=1). Changed prefix for plain fn ONLY affects dedup hash.
- **Byte-identical risk:** ZERO (man/gol/mud have no fn_ptr types; plain-fn cname never emitted in C)

**(b) registry/type distinction** — new TypeKind or discriminator
- **Where:** type_registry.zig, type_resolver.zig, c89_emit.zig, coercion.zig, lower.zig (~28+ files)
- **What:** Separate fn_ptr into its own TypeKind
- **Blast radius:** Very high (all TypeKind switch sites)
- **Byte-identical risk:** HIGH (fundamental type representation change)

**(c) emitter dedup guard** — skip dedup for non-emitting fn_types
- **Where:** `c89_emit.zig:938-939` and `c89_emit.zig:987-988`
- **What:** Guard dedup marking: if `ty.kind == fn_type && (ty.flags & 1) == 0`, skip (handler emits nothing)
- **Blast radius:** Minimal (2-4 lines in emitSpecialTypes)
- **Byte-identical risk:** ZERO for man/gol/mud

### Ranking

| Rank | Approach | Rationale |
|------|----------|-----------|
| **1** | **(a) cname distinction** | Clean source-level fix. Fixes root conceptual issue (identical cnames for different types). Minimal blast radius, zero byte-identical risk. Emitted C typedef names unchanged. |
| **2** | **(c) emitter dedup guard** | Most surgical. Zero risk. But emitter-level fix doesn't fix cname collision — future cname consumers could still be confused. |
| **3** | **(b) registry distinction** | Architecturally purest. Highest blast radius / byte-identical risk. Overkill for this dedup bug. |

### Recommendation

**Option (a) — cname distinction.** Clean, minimal (~5 lines in `getCTypeName`), source-level. Fixes the root conceptual issue: two distinct types should not produce identical cnames.

### Byte-identical assessment for man/gol/mud

NONE of man, gol, or mud contain function-pointer types. Source grep for `fn(` type expressions across `examples/zig0/{mandelbrot,game_of_life,mud_server}` and `examples/z98/{mandelbrot,game_of_life,mud_server}` returned zero matches. Pre-generated C output also has zero `FP_` references.

Both option (a) and (c) have ZERO byte-identical risk. Standard man/gol/mud byte-identical check + mandelbrot/gol runtime check suffice as gating.

### Status

- **Fix NOT APPLIED.** Investigation and recommendation only.
- **NO `sf/src/` files modified.**
- Report: `.superpowers/sdd/ex5-task-4-report.md`
