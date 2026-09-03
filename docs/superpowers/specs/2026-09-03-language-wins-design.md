# Z98 zig1 "Language Wins" — Cheap Builtins + Packed Struct/Union Design

> Supersession milestone: a set of compiler features that make zig1 strictly more capable than
> zig0, giving us a clean departure point for "bye bye zig0". NOT a bootstrap-boundary plan in the
> old sense — every feature here is something zig0 does NOT provide, implemented so zig1's own
> source can eventually use them once self-hosting is unconditional.
>
> Date: 2026-09-03. Branch: `zig1_start`. Plan mode deliverable = spec + R/I plan; F work is a
> follow-on decision (see Decision Gate).

## Goal

Extend zig1 (self-hosted; its own source remains zig0-compilable) with two tiers of features:

- **Tier A (cheap wins):** `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@intFromPtr`, `@ptrFromInt`,
  `@fieldParentPtr`, `@bitCast`, `export fn`/`export var`, cross-module `pub var` extern emission,
  and `switch` case-range lowering.
- **Tier B (packed + true bitfields):** arbitrary-width integers (`u1..u65535`, `i1..i65535`),
  `packed struct`, `packed union`, and `enum(uN)` backing — with full sub-byte bitfield semantics.

The compiler's own internal layout targets (the 16-byte `Token`, the guaranteed 24-byte `AstNode`)
are the original motivation (see `sf/src/token.zig:129-131` FIXME — "restore packed struct once zig1
can self-host") but remain OFF in zig1's own source until departure from zig0.

## Out of scope (explicit)

- `extern struct` / `extern union`, `opaque`, `vector`, generics/`anytype`/`@Type`/`@typeInfo`,
  comptime function evaluation, method syntax. These are deliberately excluded so this plan ships a
  bounded, verifiable feature set. Revisit after departure from zig0.
- No F (implementation) work happens inside this plan. This plan is **R (repro) + I (investigation)**
  and ends at a Decision Gate (below). Rationale (operator): author all repros and investigations
  first so feasibility per category is known before committing to any implementation; hardest items
  (packed) are ordered last so no "middle-ground stopper" blocks earlier wins.

## Semantics (locked decisions)

1. **`packed` = true bitfields** (full sub-byte packing), matching Zig.
2. **Bit order: LSB-first** — the first declared field occupies the least-significant bits. This
   matches Zig and gcc's i386 bitfield convention.
3. **Layout rule (backend-neutral):** fields are placed at consecutive bit offsets in declaration
   order, no padding. Field `N` starts at `bit_offset = sum(bit_size of fields 0..N-1)`.
   Container `bit_size` = sum of field bit sizes. `size (bytes) = (bit_size + 7) / 8`. `align = 1`.
   Array stride = `size` (no padding between elements).
4. **`packed union`:** every field starts at bit 0; `bit_size` = max over members of their bit
   sizes (fields overlap). `size = (bit_size+7)/8`, `align = 1`.
5. **Field types allowed in `packed struct`:** `bool` (1 bit), integers of any width, enums with
   integer backing (`enum(uN)`), and other packed containers. **Rejected:** floats, pointers,
   arrays, slices, optionals, error unions, non-packed structs, `anytype`. (B6 enforcement.)
6. **Packed fields have no address** — `&packed_field` is a compile error (matches Zig). Whole-value
   load/store, by-value params/returns, and `=` on a whole packed value ARE supported.
7. **Arbitrary-width integers:** `uN`/`iN` for N in 1..65535. Signedness + width carried in the
   type. All existing integer ops (arith, bit, shift, compare, `@intCast`) apply; overflow/truncation
   semantics per width. No `comptime_int` type is introduced.
8. **`enum(uN)`:** explicit integer backing of width N; a packed struct field of type `enum(uN)`
   occupies exactly N bits. `@enumToInt`/`@intToEnum` already exist and operate on the backing.

## Architecture (backend-agnostic core, backend-specific materialization)

The operator directive: keep the language/type/LIR layers free of C assumptions; push all
materialization into the C89 emitter.

1. **Type layer** (`type_registry.zig` / type resolution):
   - New `TypeKind`: width-parameterized integer (`int(u32 width, u8 signed)`); `packed_struct`;
     `packed_union`.
   - Packed layout resolved ONCE during type resolution into a **backend-neutral bit-layout side
     table**: per-field `bit_offset: u32`, `bit_size: u16`; container `bit_size`, `size`, `align`.
     Nothing here knows about C structs.
2. **LIR** (`lir.zig`): new ops `load_bitfield { base, bit_offset, bit_size, signed }` and
   `store_bitfield { ... }` (whole packed value ops reuse existing load/store). Because access is
   at bit granularity, a packed field can never be taken by address — enforced at sema/lowering.
3. **c89_emit.zig** (backend-specific):
   - A packed container type emits as `unsigned char zT_NAME[N];` where `N = size bytes` — never a C
     struct with named fields, never C bitfields (implementation-defined packing unit / straddle
     rules would diverge from Zig).
   - `load_bitfield` → load 1–2 bytes at `byte = bit_offset/8`, shift by `bit_offset % 8`, mask to
     `bit_size`, sign-extend when signed. `store_bitfield` → read-modify-write with the same
     arithmetic. All bit math emitted in plain C89.
   - An arbitrary-width int value `uN`/`iN` is carried in the smallest enclosing C type
     (`unsigned char`/`unsigned short`/`unsigned int`/`unsigned long long` for uN; signed for iN)
     with a mask/truncate applied on every store and explicit sign-extension on loads of signed
     values narrower than their carrier.
   - Whole packed-value moves (assignment, param pass, return, array element store) = `memcpy` of
     `size` bytes — already the shape the emitter uses for aggregate copies.
4. **Future backends** consume the same bit-level LIR and bit-layout side table; nothing in the
   type layer changes.

## C89 / gcc -m32 padding accounting (binding)

The emitter must never rely on gcc's natural struct layout for packed types. Rules that repros
assert byte-exactly under `gcc -m32 -std=c89`:

- `size` is exactly `(bit_size + 7) / 8` — internal natural-alignment padding never appears.
- Array stride of a packed type is exactly `size`.
- Straddling fields (a field whose bit range crosses a byte boundary) are emitted via
  load/store_bitfield, not by giving the field its own byte.
- `bool` is 1 bit; a packed struct of 3 bools is 1 byte.
- Signed sub-byte fields sign-extend on read and truncate on write.

## Repro contract (R phase)

- Every feature gets **its own RED fixture** under `repro/mi_matrix/<feature>_xmod/` (existing
  corpus conventions), committed with a header comment stating: the feature, the hand-computed
  expected GREEN output (byte-exact where a layout is asserted), and today's RED classification.
- **Packed ladder** (nested "normal use cases", each its own fixture dir):
  L0 bool flags → 1 byte · L1 `u1+u3+u4` → 1 byte · L2 straddling `u5`+`u8` → 2 bytes ·
  L3 nested packed struct field · L4 packed union overlap · L5 `[N]Packed` array (stride=size) ·
  L6 packed global / by-value / cross-module · L7 `enum(u3)` field.
- **RED classification** (per corpus buckets): a missing-feature fixture must be a **clean FAIL**
  (deterministic, correct missing-feature diagnostic) or a documented **runtime-wrong** (program
  compiles but misbehaves — e.g. case-ranges falling to `else`). **ICE / CRASH on a missing-feature
  fixture is a compiler defect** and is flagged as a finding, not papered over.
- **Oracle:** where zig0 already supports the construct (e.g. it likely supports cross-module `pub
  var` and old-named `@ptrToInt`/`@intToPtr`), zig0 emission/runtime is the expected-GREEN oracle.
  Where zig0 also lacks it (packed, `@bitCast`, `export`, `@offsetOf`, arbitrary widths), GREEN is
  defined by Zig semantics + the hand-computed layout above.
- Fixtures use the established idiom: `const std = @import("std");`, `pub fn main() void`,
  `std.io.write/writeByte/printInt`, `@intCast`, explicit `else` prongs, no method syntax.

## Feasibility methodology (I phase)

For each category, an investigation task traces the exact implementation path and returns a
**verdict**: `IMPLEMENT-NOW` (fits the established I/F cycle), `SEPARATE-PLAN` (correct but too
large to bundle), `DEFER` (needs a prerequisite first), or `DROP-ZIG0-INCOMPATIBLE` (cannot be
added while zig1's source must still compile under zig0, or requires an unsupported prerequisite).
No I task may modify `sf/src`.

## Decision Gate (end of this plan)

One consolidation task aggregates all I verdicts into a per-feature table, reconciles the corpus
baseline and `repro/mi_matrix/EXPECTED_FAIL.md` against the committed R fixtures, and
STOP-presents the operator with a recommended execution order for the follow-on F plan(s). Nothing
is implemented before that ruling.

## Regression discipline (applies when F eventually lands)

- gol/lisp/json/mud gate programs use none of the new features ⇒ their 4-MD5 emissions must stay
  byte-identical (`302df36b` / `3591bad9` / `76056b97` / `53405b3b`). Any move is a bug.
- The self-compile fixed point md5 WILL move (compiler source grows) ⇒ new re-baseline,
  operator-ruled, never silent.
- Golden 9/9, matrix 21/21, corpus sweep, self-compile round-trip: full battery on any F commit.

## Key source anchors (verified, current HEAD 5b620e3a)

- Missing-feature gap evidence: `sf/src/token.zig:129-131` (packed FIXME);
  `sf/src/ast.zig:116-126` (AstNode plain struct, 24B, payload moved to side tables).
- Fixed-width-only TypeKind: `docs/sf/TYPE_SYSTEM_p2.md:47-55`; primitive registration in
  `type_registry.zig`; widths already tracked in `comptime_eval.zig` (`width_bits` ~:16,25-28).
- Builtin/cast lowering: `lower.zig:430-446` (casts incl. `@ptrToInt`/`@intToPtr` :438-440).
- `export` half-wired: `kw_export` token (token.zig:156, keyword table init :144+); AstNode flags
  bit3 `is_export` (ast.zig:120); parser handles `kw_extern` (parser.zig:1357,1489) but no
  `kw_export` handler.
- switch case-range: parsed as range nodes (parser.zig:977-981) but NOT lowered —
  `lower.zig` switch paths drop them to `else` (expr site :4010-4219, stmt site :4913-5064; case
  value mapping :4055-4133; `SwitchCase{value:u64,target_bb}` in `lir.zig`); emitted as plain C
  switch/goto (c89_emit.zig:6370-6411, case value `@intCast(u32, c.value)` :6385).
- Cross-module `pub var`: upstream P1-2 note "cross-module globals need c89_emit header extern
  decls" — gap to verify in I phase (c89_emit header/hoist emission for module-scope storage
  globals; `temp_global_map` :5172-5181 area is function-local aliases, not cross-module extern).
- std: `sf/src/std_io.zig` (writeByte :1, write :5, printInt :19), `std.zig` re-exports io+arena.
- Corpus: fixtures under `repro/mi_matrix/` (332 dirs today) + top `repro/*` (53) + examples; RED
  ledger `repro/mi_matrix/EXPECTED_FAIL.md`.

## Zig official reference consulted

https://ziglang.org/documentation/master/ — packed struct/union semantics (LSB-first, bit
accounting), `@offsetOf`, `@bitSizeOf`/`@bitOffsetOf`, `@intFromPtr`/`@ptrFromInt`,
`@fieldParentPtr`, `@bitCast`, `export`, `enum(uN)`.
