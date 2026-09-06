# Packed Struct Core (P1–P3) — Design Spec

**Date:** 2026-09-06 · **Branch:** zig1_start · **Type:** compiler feature (Z98 dialect, language-wins follow-on; plan item 7 PACK-CORE)

## 1. Purpose

Give Z98/zig1 true `packed struct` semantics — full sub-byte, LSB-first, padding-free bitfield packing with backend-agnostic layout — sufficient to turn the L0/L1/L2 packed-ladder RED fixtures GREEN. This is the first instalment of the PACK family; it covers **plain packed structs whose fields are `bool`/`uN`/`iN`** only. Packed union, nested packed-struct fields, packed arrays/globals/by-value/cross-module, and `enum(uN)` fields are PACK-AGG/PACK-B3 scope (see §7).

## 2. Binding operator decisions

- **PACK-CORE scope = P1–P3** (parse → type/layout → LIR → emitter) → L0/L1/L2 GREEN. Authored now; **executed after INTWIDTH**, which supplies the arbitrary-width integer registry (`Type.width_bits`/`is_signed` + `intWidthBits(ty) u8` + `intIsSigned(ty) bool` + uN/iN name registration/carrier rules). PACK-CORE never re-implements uN registration — it consumes INTWIDTH's model.
- **Representation: `packed struct` = existing `struct_type` + new flags bit bit4 (`0x10`, `is_packed`)** + a backend-neutral **bit-layout side table** keyed by type id. (Operator ruling m1090; lowest churn — all struct_type dispatch sites keep matching `struct_type`, only layout/emission branch on the flag.)
- **Backend-agnostic layout**: the type layer records only the *bit* layout (per-field `bit_offset`, `bit_width`, LSB-first, no padding, `bool` = 1 bit); the C89 emitter owns byte packing, shift/mask accessors, carrier, and `memcpy` of whole values. Mirrors the INTWIDTH semantic-vs-emission split.
- **`token.zig` packed-layout FIXME (24B→16B, union field) is PACK-AGG territory** (packed container containing a union(enum) field) — not PACK-CORE.
- Packed-ladder fixtures keep their **locked contracts** — no re-baseline: L0 `1 5 1`, L1 `1 155 1 5 9`, L2 `2 255 31 31 255`.
- Every `sf/src` change moves the self-compile fixed point → operator-ruled re-baseline (never silent). 4-MD5 gates must hold byte-identical (no existing source uses `packed`).

## 3. Locked semantics (from the language-wins design, 2026-09-03)

- `packed` = **true bitfields**, sub-byte, LSB-first, zero padding between fields (whole-value padding only to the byte boundary of `@sizeOf`).
- Allowed packed field types in PACK-CORE: `bool` (1 bit) and `uN`/`iN` (INTWIDTH widths; `u0/i0/>64` already rejected by INTWIDTH). **PACK-CORE rejects** (clean `error[3000]` B6): floats, pointers, arrays, slices, optionals, error unions, non-packed structs, packed unions, `enum(uN)`, `anytype`.
- `&packed.field` is a compile error (packed fields have no address). Whole-value ops are supported: load/store of a whole packed value, assignment `=`, `@sizeOf`/`@alignOf`/`@bitSizeOf`, pass/return **by value** (memcpy), array element store of a whole packed value (memcpy).
- A pointer to a whole packed value (`*Packed`) is allowed (the byte-dump fixtures cast `&f` to `[*]const u8`).
- Introspection on a packed type: `@sizeOf` = `ceil(total_bits/8)`; `@alignOf` = 1; `@bitSizeOf` = total bits; array stride = `@sizeOf`.
- LSB-first bit numbering: field N starts at the bit offset equal to the sum of the bit widths of fields 0..N-1; bit `k` of the value lives at byte `k/8`, bit `k%8` of that byte. (L1: x:u1 @0, y:u3 @1, z:u4 @4.)

## 4. Architecture

### 4.1 Parse (P1)

- `packed` becomes a keyword (`kw_packed`). Consumed in the **expression-primary grammar** (`parserParsePrimary`), threading `is_packed` into `parserParseStructType` (fixtures are `const X = packed struct {…}`, i.e. var-decl init expressions — the same hook I8 verified; the statement/pub-decl `packed struct` container path is grammar-completeness only and not fixture-blocking). The `packed` bit lands on the struct-decl AST node's flags (bit4 `0x10` on the node; same flag slot as the eventual type-level flag).

### 4.2 Type layer (P1)

- `struct_type` resolution path recognizes the packed flag → records `is_packed` on the resolved `Type`.
- A **bit-layout side table** (keyed by type id, resolved once during type resolution, after all field types are state-2) stores per field: `bit_offset`, `bit_width` (from `intWidthBits` of the field type; `bool` → 1). Total bit width = running sum. `@sizeOf`-relevant byte size = `ceil(total_bits/8)` (emission side computes the C carrier).
- The existing `FieldEntry` table stays as-is for non-packed structs; packed structs' semantic field layout lives in the side table (or `FieldEntry` gains packed bit-offset/width fields consumed only for packed — census in plan Task 1 picks the lower-churn placement).
- `@offsetOf`/`@bitOffsetOf`/`@sizeOf`/`@alignOf`/`@bitSizeOf` on packed types consult the side table (byte offsets for packed fields are meaningful for whole-value/byte-dump purposes; bit offsets are the true layout).

### 4.3 Sema (P1)

- Field-type B6 gate for packed structs (allowed set in §3); `&packed.field` rejection.
- Whole-value uses type-check as today's struct `=`/param/return paths (no special case beyond the field-type gate + no-address rule).

### 4.4 LIR (P2)

- New LIR ops `load_bitfield` and `store_bitfield` (field read/write at `bit_offset`+`bit_width` on a base address of the packed value) + their arms in the ~15 inst-switch sites (emitter walk, the 4 DCE liveness fns `dceMarkAllReads`/`dceReleaseOperands`/`dceResultPos`/`dceTempIsArray`, plus any pre-passes) so a missed arm (0xFFFFFFFF result / silent drop) can never discard a bitfield read. Whole packed-value operations reuse existing load/store/memcpy paths (packed values are `struct_type`, value-sized by the byte size).
- The store-drop rule: packed struct stays `struct_type`, so the existing `dceTempIsArray`-gated store emission must treat a packed-typed base like the array case (keep whole-value stores into global arrays live — the f014259b/C4 rule generalized by "is-array **or** is-packed").
- `lir_stream` raw-byte serialization carries the new variants (no pointers; pure layout growth — self-consistent per run).

### 4.5 C89 emitter (P3)

- A packed type emits as a C89 byte carrier `unsigned char zT_NAME[N]` (N = `@sizeOf` = `ceil(total_bits/8)`) — never C bitfields, never gcc natural layout.
- Field write at bit offset `bo`/width `w`: read-modify-write mask across the one-or-two bytes spanned (`byte = bo/8`, bit `bo%8`): clear the field's bit window, OR the masked/shifted value (value masked to width via INTWIDTH's unsigned mask rule; signed stored value sign-extended then masked into the window as its two's-complement bit pattern).
- Field read: shift right by `bo%8` from the spanned byte(s) (little-endian gather, honoring byte stride when the field crosses a byte boundary — L2 straddle), mask to width; signed fields sign-extend from bit `w-1` (INTWIDTH `intIsSigned`).
- Whole-value moves/assignment/by-value param/return/array-element store = `memcpy` of N bytes (pal/memcpy precedent). A `*Packed` pointer is emitted as a pointer to the carrier (`unsigned char *`/`[*]u8`-compatible) so `@ptrCast([*]const u8, &f)` byte-dump fixtures work.
- Local packed vars: an N-byte carrier (`unsigned char f[N]`) plus the shift/mask accessors for field reads/writes and the fixtures' byte-dump.
- Emission only branches on `is_packed` for packed types → byte-neutral for all non-packed programs.

## 5. Behavior contracts (fixtures, byte-exact)

- **L0 `packed_l0_flags_xmod`** — `Flags{a,b,c: bool}`: `@sizeOf` 1; a=true c=true b=false ⇒ byte `0b00000101` = 5; reads true ⇒ prints `1 5 1`.
- **L1 `packed_l1_mix_xmod`** — `Mix{x:u1,y:u3,z:u4}`: `@sizeOf` 1; x=1@0, y=5@1, z=9@4 ⇒ byte `0b10011011` = 155; reads 1 5 9 ⇒ prints `1 155 1 5 9`.
- **L2 `packed_l2_straddle_xmod`** — `Strad{a:u5,b:u8}`: `@sizeOf` 2; a=31@0..4, b=255@5..12 ⇒ byte0 `0xFF`, byte1 `0x1F`; reads 31 255 ⇒ prints `2 255 31 31 255`.
- Deterministic 3×; RUNRC=0; canonical green-guard/classifier recipe (task-LANGWINS-report.md Step-4) applies at GREEN time.

## 6. Success criteria

1. L0/L1/L2 run-gate byte-exact on the reference compiler (executed post-INTWIDTH).
2. 4-MD5 gate byte-identical (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`); golden 9/9, matrix 21/21, corpus zero-asymmetric on the common set (only the packed dirs move RED→GREEN).
3. No existing `sf/src` program's emission changes (self-compile hop closure; fixed point re-baselined operator-ruled, never silent).
4. Clean B6 diagnostics for the rejected field types and for `&packed.field` (no ICE).

## 7. Out of scope / dependencies

- **Depends on INTWIDTH** (uN/iN registration, `intWidthBits`/`intIsSigned`, mask/sign-extend helpers). Executes after it.
- PACK-AGG (item 8): packed union (untagged; every field at bit 0), nested packed-struct fields, packed array/global/by-value/cross-module (L3–L6), `token.zig` packed FIXME.
- PACK-B3 (item 9): `enum(uN)` backing + `enum(uN)` packed fields (L7).
- LIROPTPASS (item 10): unrelated (emission-tightening).
- The R7 `int_arbitrary_width_xmod` false-green is INTWIDTH's deliverable, not PACK-CORE's.
