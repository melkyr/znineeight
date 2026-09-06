# Packed Struct Aggregates (P4) — Design Spec

**Date:** 2026-09-06 · **Branch:** zig1_start · **Type:** compiler feature (Z98 dialect, language-wins follow-on; plan item 8 PACK-AGG)

## 1. Purpose

Extend PACK-CORE's `packed struct` support to the aggregate/container cases of the packed ladder: **L3** nested packed-struct field (leaf access), **L4** `packed union` (untagged overlap), **L5** `[N]Packed` arrays and packed storage globals, and **L6** packed by-value + cross-module layout identity — turning the committed L3/L4/L5/L6 RED fixtures GREEN with their locked contracts. The `token.zig` packed-layout FIXME (a TAGGED union(enum) field inside a packed struct) is **deferred** to a separate follow-on: packing a tagged union's tag+payload into bit layout is a distinct feature from the plain packed-container field model and is out of this plan.

## 2. Binding operator decisions

- **PACK-AGG scope = P4 → L3/L4/L5/L6 GREEN.** Executes AFTER PACK-CORE (packed `struct_type` flag, bit-layout side table, LIR `load_bitfield`/`store_bitfield`, single-member-struct carrier) which itself executes after INTWIDTH.
- **`packed union` = a distinct new `packed_union` TypeKind** — untagged, every field at bit 0, `@bitSizeOf` = max member bit width. The existing `union(enum)` is TAGGED; packed union is Z98's first untagged union, so it is NOT a flag on `union_type` (which means tagged union everywhere today). (Operator ruling.)
- **`token.zig` tagged-union-in-packed FIXME deferred** (a separate follow-on; not PACK-AGG). (Operator ruling.)
- **Carrier stays emitter-owned** (PACK-CORE spec §4.5 AMENDMENT 1): single-member struct `typedef struct { unsigned char _[N]; } zT_NAME;` — native C struct-by-value for param/return/assign/array/global, byte-dump via first-member address; LIROPTPASS-revisitable; never leaks into the agnostic type/LIR layers.
- Packed-ladder contracts locked, no re-baseline: L3 `2 5 6 3 3`, L4 `2 8`, L5 `1 33 3 4`, L6 `1 21 186` (0xBA = hi<<4|lo, 186 — the fixture header's stale `187` slip is recorded-history only).
- Every `sf/src` change moves the self-compile fixed point → operator-ruled re-baseline at the plan's battery STOP (never silent). 4-MD5 gates hold byte-identical (no existing source uses `packed`).

## 3. Locked semantics

- **L3 nested packed-struct field**: a packed struct field whose type is another `packed struct` is allowed. The field's `bit_width` = the inner type's total bit width; `bit_offset` accumulates through nesting (LSB-first). **Leaf access only**: `o.inner.a` reads/writes the bitfield at `(inner_bit_offset + a_bit_offset)`; whole-sub-container value moves (`o.inner` as a value, e.g. assignment of the inner struct) are OUT of scope (rejected cleanly or unimplemented-not-reached — plan decides per the DCE/emitter census, never silent).
- **L4 `packed union`**: fields declared without a tag; every member starts at bit 0; `@bitSizeOf` = max member `bit_width`; `@sizeOf` = `ceil(max_bits/8)`; `@alignOf` = 1. Member access = `load_bitfield`/`store_bitfield` at offset 0 with that member's width. Whole-value ops on the union = carrier ops of `@sizeOf` bytes (members share the same carrier bytes). Field set allowed = the PACK-CORE set (bool/uN/iN + packed structs); reject pointers/arrays/tagged unions/floats/etc.
- **L5 arrays + globals**: `[N]Packed` has stride exactly `@sizeOf` (no padding); a packed storage global `var grid: [4]Cell` is a carrier-array global (or array-of-carrier-struct) with correct extern/def split across modules; whole-element store `grid[i] = Cell{…}` = native struct-by-value (re-exercises the store-drop/C4 generalization — packed `struct_type` base treated like the array case so the store stays live); `&grid[0]` byte-dump works.
- **L6 by-value + cross-module**: packed by-value param/return/assignment and a packed type defined in one module used by another must produce identical layout in both (single side-table identity: same type id → same bit layout; the emitter's carrier typedef is shared). By-value uses native C struct-by-value on the carrier (no hidden-pointer/memcpy wrapper).
- LSB-first numbering, `bool` = 1 bit, no field padding (whole-value padding only to the byte boundary of `@sizeOf`) — unchanged from PACK-CORE.

## 4. Architecture

### 4.1 Parse/sema
- `packed union { … }` (no `(enum)` tag) parsed in the expression-primary path → a packed-union AST node (new kind or the union-decl path with an untagged flag — census picks the lower-churn placement); resolved to the `packed_union` TypeKind.
- `packed struct` field-type gate extends to accept nested `packed struct` and (for unions) packed-union fields; packed unions additionally gate member types.
- `&packed.field` remains a compile error (both struct and union).

### 4.2 Type layer
- New `packed_union` TypeKind + its layout resolution (max member width; members at bit 0) into the same backend-neutral bit-layout side table (or a union variant row keyed by type id).
- Nested packed-struct field layout: bit width of the inner type recorded on the field; leaf bit offsets are the accumulated chain (computed on demand during lowering from the side table, or pre-materialized for the leaf path — census picks).
- Introspect: `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf` for packed union + nested-typed values.

### 4.3 LIR
- Reuse `load_bitfield`/`store_bitfield`. Leaf access through nesting carries the accumulated `bit_offset`. Union member access = offset 0. Whole-value paths unchanged (struct-by-value on the carrier).
- Any new inst-armed sites from PACK-CORE's arm list must also cover the union variant.

### 4.4 C89 emitter
- Carrier = PACK-CORE's single-member struct; `packed_union` shares the same carrier shape (its own typedef).
- Field access bodies unchanged (shift/mask); nested/union access uses the accumulated/zero bit offsets.
- Arrays: `[N]Packed` emits as `zT_NAME grid[N]` (struct-array, stride = size). Global packed array extern/def across modules.
- By-value param/return: native struct-by-value.

## 5. Behavior contracts (fixtures, byte-exact)

- **L3 `packed_l3_nested_xmod`** — `Inner{a:u3,b:u3}`, `Outer{head:u2, inner:Inner, tail:u2}` (2+6+2 = 10 bits → size 2): head=3@0..1, inner.a=5@2..4, inner.b=6@5..7, tail=3@8..9 → prints `2 5 6 3 3`.
- **L4 `packed_union_xmod`** — `U{ a:u4, b:u12 }`: size 2 (12 bits → 2 bytes); b=3000 → a = low 4 bits of 3000 = 8 → prints `2 8`.
- **L5 `packed_array_global_xmod`** — `Cell{x:u4,y:u4}` (8 bits, size 1, stride 1); `grid[1]` byte = x=1,y=2 → `0x21` = 33; `grid[3].x=3 .y=4` → prints `1 33 3 4`.
- **L6 `packed_byvalue_module_xmod`** — `Pair{lo:u4,hi:u4}` (size 1) in module `types`; `sum(build(10,11))` = 21; byte = hi<<4|lo = `0xBA` = 186 → prints `1 21 186`.
- Deterministic 3×; RUNRC=0; authoritative classify/run recipe (task-LANGWINS-report.md Step-4) applies at GREEN time.

## 6. Success criteria

1. L3/L4/L5/L6 run-gate byte-exact on the reference compiler (executed post-PACK-CORE).
2. 4-MD5 gate byte-identical (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`); golden 9/9, matrix 21/21, corpus zero-asymmetric on the common set (only the 4 packed dirs move RED→GREEN).
3. No existing `sf/src` program's emission changes (self-compile hop closure; fixed point re-baselined operator-ruled, never silent).
4. Clean B6 diagnostics for rejected packed-union/field types and `&packed.field` (no ICE).

## 7. Out of scope / dependencies

- Depends on INTWIDTH → PACK-CORE executed first.
- PACK-B3 (item 9): `enum(uN)` backing + `enum(uN)` packed fields (L7).
- `token.zig` packed FIXME (tagged union(enum) inside packed struct) → separate future follow-on (not PACK-AGG, not PACK-B3).
- LIROPTPASS (item 10): unrelated (emission-tightening).
