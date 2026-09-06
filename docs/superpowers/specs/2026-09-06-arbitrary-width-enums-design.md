# enum(uN) Arbitrary-Width Enums (P5/PACK-B3) — Design Spec

**Date:** 2026-09-06 · **Branch:** zig1_start · **Type:** compiler feature (Z98 dialect, language-wins follow-on; plan item 9 PACK-B3)

## 1. Purpose

Add **`enum(uN)`** — an enum with an explicit arbitrary-width integer backing (`u3`, `u12`, … from the INTWIDTH `uN` registry) — as a general type feature usable standalone (`@enumToInt`, `@intToEnum`, `@sizeOf`/`@bitSizeOf`/`@alignOf`) AND as a `packed struct` field (bit width N). Turns the committed L7 RED fixture `packed_enum_field_xmod` GREEN with contract `1 3 1 1`. Plain `enum` (no backing) keeps its current behavior byte-identical.

## 2. Binding decisions

- **General `enum(uN)` + packed-field use** (operator ruling). Executes AFTER INTWIDTH (uN registry: `Type.width_bits`/`is_signed` + `intWidthBits(ty) u8` + `intIsSigned(ty) bool` + uN/iN name registration + carrier rules) and AFTER PACK-CORE (packed bit-layout + LIR `load_bitfield`/`store_bitfield` + single-member-struct carrier).
- Backing width N ∈ {1..64}; `bool` is not an enum backing; `enum(u0)`/`>64` clean error[3000]. Backing is unsigned (`enum(uN)`); `enum(iN)` signed backing is out of scope (rejected cleanly if authored).
- Default tags consecutive 0..count-1; explicit tag values allowed with a fit check (value must fit the N-bit unsigned range). `count > 2^N` (or an explicit value out of range) → clean error[3000], never silent truncation.
- `@sizeOf(Color)` = the carrier of the backing `uN` (via INTWIDTH's carrier rule: smallest pow-2 byte size or the emitter-owned encoding — C89: 1 byte for u3); `@bitSizeOf` = N; `@alignOf` = backing align.
- As a packed-struct field: field `bit_width` = N (LSB-first), exactly like an `uN` field. `@enumToInt`/`@intToEnum` work on the backing width; a packed-union member or nested packed container holding an `enum(uN)` uses N bits.
- `enum(uN)` runtime semantics for `@intToEnum` out-of-range values follow the existing enum conversion behavior (check the existing enum runtime/checked-cast precedent in the census; do not invent new trap semantics silently).
- Plain `enum` (e.g. `enum { a, b }` and any existing backing form) is UNCHANGED — byte-identical emission, no re-baseline of anything but the fixed point (source grows).

## 3. Locked semantics

- `const Color = enum(u3) { red, green, blue };` — tags red=0, green=1, blue=2 (default consecutive), fit in u3 (max 2).
- `@enumToInt(Color.blue)` = 2 (type u3 backing). `@sizeOf(Color)` = 1. `@bitSizeOf(Color)` = 3. `@alignOf(Color)` = 1.
- `Pixel = packed struct { on: bool, color: Color }` — on@0 (1 bit), color@1 (3 bits) → byte 0b00000011 = 3 when on=true, color=green. sizeOf(Pixel) = 1.
- L7 contract `1 3 1 1`: sizeOf(Pixel)=1; byte = 3; @enumToInt(Color.blue)==2 → prints 1; sizeOf(Color)=1.
- Enum-typed switch/case, `.tag` literals, equality — all operate on the uN-backed value like any enum (width N semantics; comparisons on the N-bit carrier).

## 4. Architecture

### 4.1 Parse
- `enum(uN)` accepted where enum containers are parsed (today `enum(...)` or bare `enum`); the backing `uN` name is validated against the INTWIDTH registry.

### 4.2 Type layer
- The enum type gains an explicit backing width field (via INTWIDTH's width model). Layout: member values assigned 0..count-1 (or explicit) into the N-bit backing; `@bitSizeOf` = N; `@sizeOf`/`@alignOf` from the INTWIDTH carrier/align rules. State-2 resolution unchanged.
- Fit validation: count and explicit values checked against `2^N - 1`.

### 4.3 Sema
- `@enumToInt(x)` → the backing uN; `@intToEnum(T, v)` → enum(uN); implicit compares/field-position typed as the backing.
- PACK-CORE's packed-field gate accepts `enum(uN)` fields (bit width N).

### 4.4 LIR/emitter
- No new LIR op: enum(uN) values ride the backing-int representation (INTWIDTH's `int` handling) with the enum type tagging; packed-field storage reuses `load_bitfield`/`store_bitfield` at width N; the single-member-struct carrier path covers any whole-value enum(uN) move. Enum member read/write/lookup paths that assumed the old fixed-width backing are generalized via the census.

## 5. Behavior contracts (fixtures, byte-exact)

- **L7 `packed_enum_field_xmod`** → `1 3 1 1` (Pixel size 1; byte 3 with on+green; enumToInt(blue)==2 → 1; sizeOf(Color)=1). Deterministic 3×, RUNRC=0.

## 6. Success criteria

1. L7 run-gate byte-exact; standalone enum(uN) probes (sizeOf/bitSizeOf/enumToInt/intToEnum) correct.
2. 4-MD5 byte-identical (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`); golden 9/9; matrix 21/21; corpus zero-asymmetric on the common set.
3. Plain enums byte-identical (no regression); clean error[3000] for out-of-range backing/values.
4. Self-compile hop closure; fixed point re-baselined operator-ruled at the battery STOP.

## 7. Out of scope / dependencies

- Depends on INTWIDTH + PACK-CORE executed first. `enum(iN)` signed backing out of scope. token.zig tagged-union-in-packed FIXME out of scope (separate follow-on). LIROPTPASS unrelated.
