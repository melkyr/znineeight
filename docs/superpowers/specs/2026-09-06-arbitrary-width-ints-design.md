# Arbitrary-Width Integer Types (uN/iN) — Design Spec

**Date:** 2026-09-06 · **Branch:** zig1_start · **Type:** compiler feature (Z98 dialect, language-wins follow-on)

## 1. Purpose

Give the Z98/zig1 type system true integer **width** as a first-class semantic property: `u1..u64` / `i1..i63` become real types with full wrap/sign arithmetic semantics, unblocking PACK (packed struct fields of `u1/u3/u4/u5/u12`) and removing the current silent void-fallback false-green for `uN`/`iN` annotations (R7 class). Previously arbitrary-width names degraded to `TYPE_VOID` ("cannot declare variable of type void"); unknown-width handling already has a clean `unknown type in variable declaration` diagnostic (F-CLEANDIAG) that uN/iN will now legally satisfy.

## 2. Binding operator decisions

- **Full wrap/sign semantics now** (not in-range-minimal). ~350-500 LOC class.
- **Backend-agnostic width**: the type layer records *semantic width only*; the C89 emitter owns carrier choice, packing, and mask/sign-extend. ("backend agnostic so each one has to decide how tight it packs thats a c89 emitter part").
- **Explicit `width_bits` (+`is_signed`) fields on `Type`** (not name-derived, not a side-table).
- Width range `u1..u64` / `i1..i63` (`u64`/`i64` already builtin; `i64` covers width 64 signed).
- `u0`/`i0`/width>64 → clean `error[3000]`.
- `enum(uN)` remains PACK-B3 scope. Packed-struct sub-byte field packing remains PACK scope.
- Every change to `sf/src` moves the self-compile fixed point → operator-ruled re-baseline (never silent). 4-MD5 gates expected to hold (byte-neutral for programs not using uN/iN).

## 3. Architecture

### 3.1 Type layer (backend-agnostic)

`Type` (type_registry.zig) gains semantic width fields. Single source of truth for integer semantics:

- `width_bits` — the true bit width (1..64 unsigned, 1..63 signed).
- `is_signed` — signedness (explicit bit or field; must stay consistent for the whole int family u8/i8/u16/i16/u32/i32/u64/i64 plus the new uN/iN).

Introspection helpers used by every semantic consumer:

- `intWidthBits(ty) u8` — semantic bit width.
- `intIsSigned(ty) bool` — signedness.

These two helpers replace (a) every semantic compare that currently uses byte `size` as if it were width (coercion widening, int-peer width pick, `@intCast` width decision), and (b) every `size * 8` width derivation. `Type.size` (byte size) is retained for emission/layout only and is the emitter's domain (see §3.2) — not a semantic width proxy.

### 3.2 C89 emitter owns packing (backend decision)

- Standalone `uN`/`iN` maps to the smallest power-of-2 C carrier that fits: `u8/i8` (N≤8), `u16/i16` (9-16), `u32/i32` (17-32), `u64/i64` (33-64).
- True width is enforced by **mask** (unsigned: `value & ((1<<N)-1)` on store; loads are already within range) and **sign-extend** (signed: arithmetic shift to width on store/compare, i.e. sign-extend from bit N-1). Novel emission: any op that can exceed the width (add/sub/neg/shift/widen/intCast-truncate) emits the mask/sign-extend wrap after the operation.
- `@sizeOf(uN)` = carrier byte size; `@alignOf(uN)` = carrier alignment; `@bitSizeOf(uN)` = N (semantic).
- Packed-struct sub-byte packing is PACK scope (LIR `load_bitfield`/`store_bitfield`), not this spec.

### 3.3 Name registration

- Parser/lexer need no change (type names are identifiers; `u8`/`i32`-style names are interner-keyed — see I7 census: type_registry:605/type_resolver:705).
- `type_resolver` recognizes `u<digits>` / `i<digits>`: parse width N; validate 1≤N≤64 (u) / 1≤N≤63 (i); register a Type with the carrier-size/width fields via a factory (register uN/iN like primitives). Duplicate-width names (e.g. `u8`) resolve to the existing primitive (same width) — no new Type identity for already-existing widths.
- Bad forms (`u0`, `i0`, `u65`, `u-3`, `u`) → clean `error[3000]` at the annotation site (reuse the F-CLEANDIAG unknown-type/3000 path where applicable; the existing void-fallback must NOT fire for valid uN/iN).

### 3.4 Semantics (full wrap/sign)

- Arithmetic (`+ - *`, negation, shifts, division) on `uN`/`iN` wraps/truncates to width (mask uN; sign-extend iN). `iN` min-int negation wraps (same class as today's i64 handling, generalized to width).
- Comparisons on `iN` are sign-correct at width (sign-extend both sides before compare, or compare as signed at the carrier after sign-extension).
- `@intCast(Dst, src)`: widen (uN zero-extend, iN sign-extend), narrow (truncate then mask/sign-extend to Dst width). Checked vs unchecked per existing `@intCast`/`@as` semantics: checked cast overflow checks against the *width*, not the carrier.
- Literals: an integer literal materialized into a `uN`/`iN` context adopts that width (mask/sign-extend on storage). Literal materialization default elsewhere unchanged (I7 note: sema has no i32 default; materialization default is c89_emit `intConstTypeForValue`).
- `@intCast` checked-cast decision table (lower.zig ~:1280 fixed 8/16/32/64) generalizes to width.
- `comptime_eval`: width-aware folds; `@bitSizeOf(uN)` = N.

## 4. Components touched (census-derived, I7)

- `type_registry.zig` — `Type` width fields; `registerPrimitive` family; uN/iN factory; width/signed helpers (or in a small shared helper file).
- `type_resolver.zig` — uN/iN name recognition + validation + registration path (~:705 branch).
- `coercion.zig` — width-based int-widen (was byte-size compare).
- `semantic_analyzer.zig` — int-peer width pick (was byte-size); `@intCast` width/signed decisions; literal-to-uN materialization; diagnostics for bad widths; the annotation-resolution path so valid uN/iN no longer hit void-fallback and invalid widths get clean 3000.
- `comptime_eval.zig` — `@bitSizeOf`, width-aware const folds (was `size*8`).
- `lower.zig` — `@intCast` width decision + checked-cast table (~:1280) generalized; any int-op width propagation needed for emission.
- `c89_emit.zig` — carrier map (`getCTypeName`, `intTypeByteWidth`, globvar/int-literal suffix tables ~:158-172/:3621-3630/:3679-3688); mask/sign-extend wrap emission for uN/iN ops (novel); sat/checked-cast helpers (~:3823-3849/:4220-4293); `@intCast` runtime helpers where width-checked.

## 5. Semantics/behavior contracts

- `@bitSizeOf(u3)` = 3; `@bitSizeOf(i7)` = 7.
- `@sizeOf(u3)` = 1; `@sizeOf(u12)` = 2; `@sizeOf(u20)` = 4; `@sizeOf(u33)` = 8 (carrier bytes).
- `u3 7 + 1` wraps to 0; `i7 63 + 1` wraps to -64 (sign-extend); `i7 -1` sign-extends to 127-bit pattern at width.
- `@intCast(u3, 255)` → 7 (truncate/mask); `@intCast(i7, 128)` → checked overflow error if checked.
- Comparisons: `i7 -1 < 0` true (sign-correct).
- Existing `u8/i8/u16/i16/u32/i32/u64/i64` behavior unchanged (width == size*8 for power-of-2; helpers return the same values).

## 6. RED → GREEN fixtures (tests)

- **R7 `int_arbitrary_width_xmod`** (committed repro/mi_matrix, currently FALSE-green via void-fallback; contract `7 -3 3000 4`, annotations `u3/u3/i7/u12`). INTWIDTH makes it a genuine GREEN.
- New RED fixtures (each added during the plan; contracts byte-exact, deterministic 3×):
  - `intwidth_wrap_xmod` — uN arithmetic wrap (`u3 7+1→0`, `u12 4095+1→0`), `iN` sign wrap.
  - `intwidth_sign_extend_xmod` — `i7 -1 < 0`, `@intCast(i16, i7 -1)` sign-extends.
  - `intwidth_cast_xmod` — `@intCast(u3, 255)`, narrow/truncate, widen zero/sign.
  - `intwidth_introspect_xmod` — `@bitSizeOf/@sizeOf/@alignOf` on u3/u12/u20/u33/i7.
  - `intwidth_full_xmod` — 64-bit-carrier boundary wrap + sign-extend (`u63 2^63-1 + 1 → 0` via 64-bit carrier; `i63 -1` sign-extends through `@intCast(i64)` → `-1`).
- All fixtures under `repro/mi_matrix/<name>_xmod/main.zig`, dialect-correct, run-gate `RUNRC=0` byte-exact stdout; classifier per the authoritative recipe (.superpowers/sdd/task-LANGWINS-report.md Step-4; fresh-dir requirement).

## 7. Gates / verification

- Full battery: 4-MD5 (gol `302df36b`/lisp `3591bad9`/json `76056b97`/mud `846106ac` — expected UNCHANGED, byte-neutral), golden 9/9, matrix 21/21, corpus 428/426-class, all INTWIDTH fixtures GREEN, run-gates byte-exact.
- Self-compile fixed point **moves** (Type grew + emission change): operator-ruled re-baseline; never silent.
- Regression: no uN/iN user → emitted C byte-identical (proves the refactor's size-compare→width-compare replacements are semantics-preserving for power-of-2 widths).

## 8. Out of scope

- `enum(uN)`/`enum(iN)` (PACK-B3). Packed struct sub-byte layout (PACK). Method syntax / generics / pointer captures (unchanged dialect). Cross-compiler/win9x changes. `u128`/arbitrary >64 (u64 cell ceiling).
