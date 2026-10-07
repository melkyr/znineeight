# Task 3 — Investigate the type registry (READ-ONLY)

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no rewiring**, **no
new instrumentation**, **no seed build**, **no self-compile measurement**, and **no subagents**. All
counts below come from reading source at HEAD `25809d0b` plus the **existing** frozen captures:

- `sf/src/type_registry.zig` (1,410 lines) — read end to end.
- `/tmp/task1_markers.txt` — the pre-Task-2 `-s0 --markers --track-memory` self-compile capture
  (`track-memory: perm=982K mod=1020K scr=965K pool=14924K type_db=346K total=2967K`; 48,707
  lines). It contains **2,497 `DC:k<kind>n<name_id>t<id>` records** and **215 `X:` struct
  records** — the exact per-kind type census without any new wiring.
- `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/allocation-census.md` — cumulative
  `sandAlloc` traffic per entry point (the `type_db` rows).

Binding metric: **peak RSS** (`/usr/bin/time -v` Maximum RSS), median ≥3 interleaved `-s0`
self-compile. **Carve ≠ touched RSS.** For `type_db` this distinction is unusually small: the arena
is a never-reset `GrowableSand`, and **every abandoned array generation stays live and written** in
its segment (see Step 1.5), so cumulative growth bytes are a close proxy for resident bytes. Every
"byte prize" below is stated as **resident at `-s0` (touched pages)**, with derived/estimated values
labelled.

Target reality: after Task 2 the peak RSS median is **17,096 K**; the interim target is **16,384 K**
(16 MB), i.e. a remaining gap of **≈712 K**. This task must not assume the gate is near.

---

## Step 1 — Exact layout, element sizes, counts, caps

### 1.1 `Type` — 32 B AoS (`type_registry.zig:62-74`)

```zig
pub const Type = struct {
    kind: TypeKind,   // u8    enum; 0..35 and 40 observed (36–39, 41–43 unused)
    state: u8,        // 0 or 2 only
    flags: u8,        // CONST=1, VOLATILE=2, packed=0x10, fn-ptr-used=1
    is_signed: u8,    // WRITTEN ONLY — never read (see 1.3)
    width_bits: u8,   // read only for arb_uint/arb_int (0 occurrences at self-compile)
    size: u32,
    alignment: u32,
    name_id: u32,     // interner id
    c_name_id: u32,   // sparse: error-union mangled C name memo
    module_id: u32,   // module_type + every named type
    payload_idx: u32, // index into the per-kind payload array
};                    // 5×u8 + 3 pad + 6×u32 = 32 B, align 4
```

On the **32-bit** seed target (`scripts/seed/build_from_seed.sh` compiles emitted C with `gcc
-m32`; `usize`/pointers = 4 B) this is exactly 32 B. `usize`-independent here: the struct has no
pointer/slice field, so all sizes below are ABI-stable on i386 (`u64` align 4).

### 1.2 Per-kind self-compile census (measured, `/tmp/task1_markers.txt`)

`DC:k<kind>` tally, total **2,497**. `TypeKind` enum order (`type_registry.zig:41-60`):

| kind | count | note | payload struct (size) |
|---:|---:|---|---|
| 0..16 | 1 each (17) | none_sentinel, void, bool, noreturn, i8/i16/i32/i64, u8/u16/u32/u64, isize, usize, c_char, f32, f64 | — (`payload_idx`=0) |
| 17 ptr_type | **273** | → `ptr_items` | PtrPayload (4) |
| 18 many_ptr_type | **57** | **also → `ptr_items`** | PtrPayload (4) |
| 19 array_type | **156** | → `array_items` | ArrayPayload (8) |
| 20 slice_type | **36** | → `slice_items` | SlicePayload (4) |
| 21 optional_type | **40** | → `opt_items` | OptionalPayload (4) |
| 22 error_union_type | **6** | → `eu_items` | EUPayload (8) |
| 23 error_set_type | **1** | → `es_items` | ErrorSetPayload (8) |
| 24 fn_type | **1,625** | → `fn_items` | FnPayload (20) |
| 25 struct_type | **215** | → `st_items` (+`pk_struct_items`) | StructPayload (8) |
| 26 enum_type | **18** | → `en_items` | EnumPayload (12) |
| 27 union_type | **2** | → `un_items` (+`pk_un_items`) | UnionPayload (12) |
| 28 tagged_union_type | **1** | → `tu_items` | TaggedUnionPayload (12) |
| 29 tuple_type | **0** | — | TuplePayload (8) |
| 30 unresolved_name | **0** | — | UnresolvedPayload (8) |
| 31 type_type | 1 | — | — |
| 32 module_type | **45** | — | — |
| 33 null_type | 1 | — | — |
| 34 undefined_type | 1 | — | — |
| 35 integer_literal_type | 1 | — | — |
| 36..39 anon_* | 0 | — | — |
| 40 va_list_type | 1 | — | — |
| 41 arb_uint / 42 arb_int | **0** | `width_bits`/`is_signed` only used here | — |

**Named** types (`name_id != 0`) = **1,862** (fn 1,625 · struct 215 · enum 18 · union 2 · tagged 1 ·
error_set 1); zero-name = 635 (the eventual primitives get names after the `DC` marker is emitted).
**Max `name_id` observed = 13,286** (`< 65,536`).

Payload array *live* element bytes (count × size):

```
ptr_items   330×4  = 1,320     st_items   215×8  = 1,720
array_items 156×8  = 1,248     en_items    18×12 =   216
slice_items  36×4  =   144     un_items     2×12 =    24
opt_items    40×4  =   160     tu_items     1×12 =    12
eu_items      6×8  =    48     pk_struct 215×12 = 2,580
es_items      1×8  =     8     pk_un       2×12 =    24
fn_items  1,625×20 = 32,500    xt/xn/fe/em/pk = not in markers (est. below)
```

`FieldEntry`=12 B, `EnumMember`=12 B, `TypeId`/`u32` pools=4 B, `PackedBitField`=8 B,
`PackedStructInfo`=12 B. **`FnParam` (8 B, `type_registry.zig:99`) is dead** — zero references
anywhere in `sf/src`.

### 1.3 Dead / redundant `Type` columns (source-confirmed)

- **`is_signed` is never read.** All 13 sites are writes (`:325,417,439,464,495,525,566,584,650,676,
  712,815,879`). `typeRegistryIntIsSigned` (`:858-869`) and `typeRegistryIntWidthBits` (`:846-856`)
  derive signedness/width from `kind` (arb kinds excepted). `.is_signed` reads elsewhere in `sf/src`
  are `LirInst` fields, not `Type`.
- **`width_bits` is sparse.** Read only at `:853` (arb) and its two consumers: `c89_emit.zig:5932`
  and `lower.zig:1270`, both inside `arb_uint_type`/`arb_int_type` branches. **0 arb types at
  self-compile.** For every other kind the width comes from `typeWidthBitsForKind` (`:307-313`).
- **`c_name_id` is a sparse memo.** Written only at `c89_emit.zig:2403` (inside
  `emitErrorUnionType`) and read only at `c89_emit.zig:1046-1047`. Only **6** error-union types exist
  at self-compile ⇒ ~99.8 % of the column is zero.
- **`module_id` is used only for `module_type` (45) and named types** (`registerNamedType`,
  `:885`; read at `type_resolver.zig:909,920,934`, `c89_emit.zig:2832`). Max observed module id 44.
- **`state` is only 0 or 2.**
- **`payload_idx` per-kind max = 1,625** (fn) ⇒ always `< 65,536`.
- **`FnPayload.name_id` (`:647`) duplicates `Type.name_id` (`:652`)**; **`FnPayload.module_id`
  duplicates what `Type.module_id` could carry** (`:653` currently hard-codes `Type.module_id = 0`
  for fn). 1,625 fn types.
- **`pk_struct_items` / `pk_un_items` are unconditional parallel arrays**: `stAppend` (`:246-250`)
  appends a zeroed `PackedStructInfo{0,0,0}` for **every struct** (215), and `unAppend` (`:266-270`)
  for **every union** (2), even though packing is rare. `PackedStructInfo`=12 B: `pk_struct_items`
  215×12 = 2,580 B and `pk_un_items` 2×12 = 24 B live, plus growth.
- No `Type` literal is constructed anywhere outside `type_registry.zig` (grep: zero), but external
  code **does write `Type` fields via whole-struct read-modify-write**, so narrowing the fields R2/R5
  touch is **not** confined to `type_registry.zig`. Besides the plain `state` writes
  (`type_resolver.zig:474,551`), `c_name_id` (`c89_emit.zig:2403`), the `payload_idx` RMWs in
  `symbol_registrator.zig` (six sites) and `type_resolver.zig:1602,1638,1681,1691`, and the
  `alignment`/`size` RMWs in `type_resolver.zig` (many sites) all store narrowed columns, and
  `FieldEntry.name_id` / `StructPayload.fields_start` are built externally. Every such site needs a
  mechanical `@intCast` once the field narrows (see R2/R5 Sites). Reads are unaffected: Zig widens
  `u16/u8→u32` implicitly on read.

### 1.4 The 8 id-caches (`type_registry.zig:131-140`, privates)

| cache | type | key | value |
|---|---|---|---|
| `ptr_cache` | `U64ToU32Map` | `base<<2 \| q` (< 2^18) | type id |
| `many_ptr_cache` | `U64ToU32Map` | `base<<2 \| q` (< 2^18) | type id |
| `slice_cache` | `U64ToU32Map` | `elem<<1 \| ic` (< 2^17) | type id |
| `array_cache` | `U64ToU32Map` | `elem<<32 \| length` (needs u64) | type id |
| `eu_cache` | `U64ToU32Map` | `payload<<32 \| error_set` (needs u64) | type id |
| `es_cache` | `U64ToU32Map` | FNV64 of tag list | type id |
| `name_cache` | `U64ToU32Map` | `module*2^32 + name`, or bare id, or `mod<<32\|node_payload` | type id |
| `optional_cache` | `U32ToU32Map` | payload TypeId | type id |

`U64ToU32Map` (`util/hash.zig:131-138`) is 3 separate arrays: keys u64 (8) + values u32 (4) +
occupied u8 (1) = **13 B/slot**; `U32ToU32Map` = **9 B/slot** (`:23-30`). `*InitCap` pre-size
helpers exist and are already used elsewhere (`u32ToU32MapInitCap` `:39`,
`u64ToU32MapInitCap` `:147`, both used in emission). `typeRegistryInit` uses the **zero-cap**
`*Init` variants (`:370-377`), so all 8 grow geometrically from 8.

**Measured cumulative grow traffic (all `type_db`)** — `allocation-census.md:72,83,88,90`:

| entry point | file:line | cumulative bytes | calls |
|---|---|---:|---:|
| `u64ToU32MapGrow` (7 u64 maps) | `util/hash.zig:174` | **450,528** (440.0 K) | 198 (all arenas) |
| `u32ToU32MapGrow` (optional) | `util/hash.zig:66` | 504 (0.5 K) | — |
| `typeRegistryEnsureCapacity` | `type_registry.zig:179` | **261,120** (255.0 K) | 8 |
| `arrayGrow` (all payload arrays) | `type_registry.zig:160` | **216,640** (211.6 K) | 77 |

The bytes column is the `type_db`-attributed traffic; the `198` call count for `u64ToU32MapGrow`
is **cross-arena** (the census row sums type_db + emission + module), not type_db-only — only the
byte figure is type_db-scoped.

Cache-cap arithmetic. For a geometric grower ending at capacity `C`, cumulative capacity =
`Σ(2Cᵢ−8) = 8+16+…+C = 2C−8`. The u64-map total is `450,528 / 13 = 34,656` cumulative slots
across the 7 maps, i.e. `Σ(2Cᵢ−8)=34,656 ⇒ ΣCᵢ ≈ 17,356`. With counts {273,57,36,156,6,1} the
small maps end at caps {512,128,64,256,8,8} = 976; `17,356 − 976 ≈ 16,380` ⇒ `name_cache` final
cap ≈ **16,384** (power of two), i.e.
**~213 KB live** and **~213 KB already-abandoned** generations. It dominates the caches.

### 1.5 Arena wiring and why abandoned generations are resident (`main.zig:198-201`)

```zig
var type_db_arena: GrowableSand = undefined;
alloc_mod.growableSandInit(&type_db_arena, alloc_mod.poolPtr(), 4096, "type_db");
var typereg = type_mod.typeRegistryInit(&type_db_arena.view, &interner);
```

`type_db` is a `GrowableSand` over the monotonic `pool`; `GrowableSand` keeps a **linked list of
segments** and **never frees an old segment on growth** (`allocator.zig:118-157`; only `sandReset`
returns segments to `seg_free_head`, and `type_db` is never reset). `typeRegistryEnsureCapacity`
(`:179-192`) and `arrayGrow` (`:160-172`) and both map `*Grow` functions allocate a **new** array,
copy the prefix, and **abandon the old array in place**. The old array's bytes remain written and
resident. Self-compile `arena type_db: grew` segments sum to **≈1.03 MB** (matches the census
`type_db 1,032,192 B`), while `--track-memory type_db=346 K` reports only the last segment's
`view.pos` and **understates residency by ~3×** (as the brief warns; Task 1 adopted the same
"carve≈resident for never-reset arenas" reasoning for `perm`).

⇒ For `type_db`, **cutting cumulative grow bytes cuts RSS ~1:1** (minus last-segment tails, which
are never touched). This is the single most important structural fact for this task.

---

## Step 2 — Four lenses → ranked candidates

The common gate for every Fix is the Global-Constraints battery (corpus 923/58/116, goldens
gol/lisp/json/mud, `verify_stdlib` 266/0, examples 24/24, dump-MD5 8/8, semantic markers
byte-identical IN-SESSION) **plus RSS median ≥3**, the new fixed point recorded, and, for `type_db`
changes, `--track-memory type_db` and `pool` recorded (pool must stay under the enforced
`max_mem`). Because `type_db` is internal and never serialized, correct range narrowing is
output-byte-identical.

**Aliasing analysis (binding for every candidate).** `typeRegistryGetStructFields` (`:1037-1043`)
and `GetUnionFields` (`:1179-1185`) hand out **interior slices into the growable `fe_items`**;
`GetPackedBitFields` (`:1089-1102`) and `GetPackedUnionBitFields` (`:1156-1168`) hand out slices
into the growable `pk_items`. `feAppend` (`:290-293`) and `pkFieldAppend` (`:255-258`) call
`payloadEnsure`→`arrayGrow`, which allocates a **new** array and copies. Consumers
(`type_resolver.zig:1148`; `lower.zig:890,2191,2606,2701,5252,5723`; `semantic_analyzer.zig:1514`;
`comptime_eval.zig:1337`) hold `fields` across further registry calls. Today this is safe only by
the callers' discipline (none appends `fe_items`/`pk_items` while a slice is live — verified in the
`lowerPackedWholeCopy` recursion at `lower.zig:2701-2717`, which only calls non-appending
accessors). Consequences for this task:

- **Any change that reallocates `fe_items`/`pk_items` while such a slice is live dangles.** So
  inline (field entries embedded in `StructPayload`) and chunked/interleaved arrays are **rejected**
  — they change the provenance/identity of the returned slice.
- Width/column changes that keep the array pointers and element *identity* are safe; the returned
  `[]FieldEntry` still points at the same array.
- If a future Fix reallocates, it must preserve the current "no append while a slice is live"
  discipline. In-place growth (stable pointer, below) would be strictly safer — and is **rejected
  here for a different reason** (below).

### R1 ★ — Pre-size (right-size) the registry arrays and caches to eliminate abandoned generations

- **Mechanism.** `typeRegistryInit` currently starts all 8 caches and the `Type`/payload arrays at
  cap 0/8. Because old generations are never freed (§1.5), each geometric doubling leaves the
  previous generation resident forever. Allocate each array **once at (or near) its eventual
  capacity**, using the existing `u64ToU32MapInitCap(alloc,hint)` / `u32ToU32MapInitCap(alloc,hint)`
  (`util/hash.zig:147,39` — already used in emission, **not dormant**) and a right-sized
  `typeRegistryEnsureCapacity` seed / `payloadEnsure` seed. Hints derive from source-derived bounds
  (cf. the landed interner pre-size `main.zig:188-190`), e.g. `Type` cap 4,096. For `name_cache`,
  note `mapCapacityFromHint(h)` (`util/hash.zig:4-12`) rounds `h*4/3` **up** to a power of two, so
  cap 16,384 needs hint **≤ 12,288**; a hint of 12,300 already yields 32,768.
- **Sites.** `type_registry.zig:346-380` (`typeRegistryInit`, cache init `:370-377`), `:179-192`
  (`typeRegistryEnsureCapacity` initial sizing), `:160-172`/`:174-177` (`arrayGrow`/`payloadEnsure`),
  plus a hint threaded from `main.zig:198-201`.
- **Resident prize.** Eliminates the **abandoned half** of the never-reset growth:
  - `name_cache`: baseline touched ≈ (occupied 32,760 + keys/values ≈24,569 entries×12 ≈294,828) ≈
    **~328 KB**; right-sized to 16,384 ⇒ ~164 KB. **Prize ≈ 160 KB** — *only if the hint maps to
    cap 16,384 (hint ≤12,288); a hint that rounds to 32,768 drops the prize to ≈148 KB.*
  - `Type[]`: baseline touched ≈ (old full caps 4,064 + final 2,497) ×32 ≈ **210 KB**; right-sized
    to 4,096 ⇒ 2,497×32 ≈ 80 KB. **Prize ≈ 130 KB.**
  - other caches (`ptr/many/slice/array/eu/es/optional`): cumulative 24,752 B; abandoned ~half ⇒
    **~12 KB**.
  - payload arrays (`arrayGrow` 216,640 B cumulative; abandoned ~40–50 %) ⇒ **~80–100 KB**.
  - **Total ≈ 380–400 KB resident**, at the cost of little/no *touched* extra: `*InitCap` zeroes
    only the `occupied` array (cap bytes, ≤ the abandoned occupied it replaces) and does not zero
    keys/values; `Type`/payload arrays are bump-allocated and never zeroed, so an unwritten tail is
    **carved but not resident**. Pool may *fall* (one alloc vs sum of generations).
- **Risk.** **Med.** Hint sizing is data-dependent: if the hint undershoots, growth resumes from the
  hint (residual waste, never worse than baseline by more than the hint); if it overshoots, the
  `occupied` array of a too-large cache is zeroed (touched) but keys/values are not. Must be probed
  across the corpus/stdlib (multi-module inputs) so the hint has margin. No new syntax; seed v92
  supports it.
- **Gate.** Common + `track-memory type_db`/`pool` + RSS median ≥3; confirm the wide path still
  fires correctly when a hint is exceeded; corpus/stdlib intern counts probed before fixing the
  hint.

### R2 ★ — Shrink `Type` 32 B → 16 B (AoS field repack + tiny sparse `c_name_id` side memo)

- **Mechanism.** Drop the dead `is_signed`; keep `width_bits` in a single `iw` byte (arb-only, 0..64
  fits); narrow `name_id`→u16 (max 13,286), `payload_idx`→u16 (max 1,625), `alignment`→u8,
  `module_id`→u8 (max 44), `state`→u8; move the sparse `c_name_id` (6 live entries) to a tiny
  registry-private `U32ToU32Map` side memo. Resulting layout (align 4):

  ```zig
  size: u32       // 0
  name_id: u16    // 4
  payload_idx: u16// 6
  kind: u8        // 8
  module_id: u8   // 9
  flags: u8       // 10
  state: u8       // 11
  iw: u8          // 12  (arb width)
  alignment: u8   // 13  (+2 pad)  => 16 B
  ```
- **Sites.** `type_registry.zig:62-74` (fields), all 13 `Type{...}` literal sites, the explicit
  field writes `:197` (`types_items[...] = t`), `:662`, `:770`, `:1086`, `:1117`, `:1153`
  (unchanged-by-value), plus the internal RMWs that write `payload_idx`/`alignment`.
  **External writers (not localized to `type_registry.zig`)** — each needs an `@intCast` once the
  column narrows:
  - `payload_idx` (→u16): `symbol_registrator.zig:127,156,184,195,224,240`;
    `type_resolver.zig:1602,1638,1681,1691`.
  - `alignment` (→u8): `type_resolver.zig:298,299,306,324,325,352,359,369,375,392,393,581`.
  - `state` writes (`type_resolver.zig:474,551`) stay u8; `c_name_id` write/read
    (`c89_emit.zig:2403`, `:1046-1047`) reroute through two new accessors.
  The many external **readers** (`types_items[i].kind/size/...`) need no edit: Zig widens
  `u16/u8→u32` implicitly on read.
- **Resident prize (standalone).** Type touched bytes ≈ 6,561 slot-generations × (32−16) =
  **≈105 KB.** (With R1 applied first, R1 already removed the abandoned generations, so the
  incremental R2 prize drops to ≈40 KB; combined Type prize ≈170 KB — the candidates are
  **sub-additive**, state this in the Fix.)
- **Aliasing.** `types_items` is a value array; no function returns a slice/pointer into it, so
  narrowing is safe. It touches none of the `fe_items`/`pk_items` slice paths.
- **Risk.** **Med** (raised from Low–Med). Range guards: `name_id`/`c_name_id` are interner ids —
  13,286 and ≤34 K at self-compile, but a very large multi-module input could exceed 65,535;
  `module_id` could exceed 255 in principle. Provide a documented fallback or a hard check, and
  probe corpus/stdlib. The edit is mechanical (pure `@intCast` at each writer) but **spans ~15
  external write sites** listed above, not just `type_registry.zig`.
- **Gate.** Common + markers byte-identical (ids/order untouched) + `track-memory type_db` +
  RSS median ≥3.

### R3 — Narrow cache slots: values `u32`→`u16` (all 8); keys `u64`→`u32` for ptr/many/slice

- **Mechanism.** Cache values are `TypeId`s < 2,497 (< 65,536) ⇒ value column 4→2 B. `ptr_cache`,
  `many_ptr_cache`, `slice_cache` keys are < 2^18 ⇒ key column 8→4 B. Add registry-private
  `U64ToU16Map`/`U32ToU16Map`/`U32ToU32Map` variants (or a small generic in `util/hash.zig`), used
  only by the registry (the 8 caches are private — grep confirms no external user).
- **Sites.** `type_registry.zig:131-140` (field types), `:382-402` (`nameCacheGet/Put` wrapper
  casts), every cache `Get/Put` at `:412,422,434,444,451,469,480,500,506,530,546,576,672,681`, and
  `util/hash.zig` (new narrow map type).
- **Resident prize.** u64 maps: 34,656 cumulative slots × 2 B = **≈68 KB**; u32 map: negligible;
  ptr/many/slice keys: 1,384 slots × 4 B = **≈5 KB**. **Total ≈70 KB.**
- **Aliasing.** None — maps are never sliced/returned.
- **Risk.** **Low–Med.** New map code + u16 ceilings (fallback needed for type ids >65,535 on huge
  inputs; key narrowing is exact for the three pointer/slice caches because the composed key is
  `< 2^18`). Do **not** narrow `array_cache`/`eu_cache`/`es_cache`/`name_cache` keys (they legitimately
  use the high 32 bits). Medium edit surface.
- **Gate.** Common + markers byte-identical + `track-memory type_db`.

### R4 — Deduplicate `FnPayload` (drop `name_id`; fold `module_id` into `Type.module_id`; narrow)

- **Mechanism.** `FnPayload.name_id` (`:88`) is a byte-for-byte duplicate of `Type.name_id`;
  `FnPayload.module_id` duplicates a column `Type` already has and which is currently forced to 0
  for fns. Drop `name_id` and set `Type.module_id` for fn types, then read module via `Type`.
  Narrow `params_start`/`return_type`→u16 and `is_extern`/`flags_packed`→u8 ⇒ FnPayload 20→12
  (8→12 if only one column dropped). 1,625 fn types.
- **Sites.** `type_registry.zig:88` (struct), `:631-658` (`GetOrCreateFn` build), and the ~20
  `fn_items[...]` consumers (`async_state_machine.zig:125`; `c89_emit.zig:1068,2201,2441,2473,5992,
  8029,8735`; `lower.zig:1335,5315,5421,8940`; `semantic_analyzer.zig:3312,3397,5174-5175,5233`).
- **Resident prize.** fn payoff touched ≈ 3,665 slot-generations × 8 B (drop 2×u32) = **≈29 KB**
  (narrowing adds a little more; with R1/R2 pre-sized the absolute shrinks).
- **Aliasing.** None (payload array values).
- **Risk.** **Med.** ~20 consumer sites must switch `fp.name_id`→`ty.name_id`,
  `fp.module_id`→`ty.module_id`; must keep a `Type` id in scope at each. Mechanical but broad.
- **Gate.** Common + markers byte-identical + `track-memory type_db`.

### R5 — Narrow payload columns: `FieldEntry` 12→8 and `xt_items` u32→u16; `StructPayload`/`TuplePayload` 8→4

- **Mechanism.** `FieldEntry{name_id,type_id,offset}` (`:95`): `name_id`≤13,286, `type_id`<2,497 ⇒
  `{u16,u16,u32}=8`. `xt_items` (`:124`) holds `TypeId`s ⇒ u16. `StructPayload{fields_start u32,
  fields_count u16}` (`:89`): `fields_start`<65,536 ⇒ `{u16,u16}=4`; same for `TuplePayload`.
- **Sites.** `type_registry.zig:89,93,95,124` and their append/read sites (`:246-305`, `:595-603`,
  `:1037-1043`, `:1179-1185`, `:1310-1367`). **External writers** (need casts once narrowed):
  `FieldEntry.name_id` at `symbol_registrator.zig:141,167`; `StructPayload.fields_start` at
  `symbol_registrator.zig:150` and `type_resolver.zig:1632`. The `feAppend`/`stAppend`/`tupAppend`
  call sites in those files also pass the narrowed values.
- **Resident prize.** **≈15–25 KB estimated** — `fe_len`/`xt_len` are not in the captured markers,
  so this is derived from struct/field/fn-parameter counts, not measured. Label as estimate.
- **Aliasing.** `fe_items`/`xt_items` narrowing does not reallocate and does not change element
  identity; the `GetStructFields` slice keeps pointing at the same array. Safe under the existing
  discipline.
- **Risk.** **Med** (edit surface extends outside `type_registry.zig` per Sites). TypeId ceilings
  again; `offset` stays u32; every external `FieldEntry`/`StructPayload` construction needs a cast.
- **Gate.** Common + markers byte-identical + `track-memory type_db`.

### R6 — Make `pk_struct_items`/`pk_un_items` sparse (small)

- **Mechanism.** Stop appending a zeroed `PackedStructInfo` per struct/union in `stAppend`/
  `unAppend`; keep a registry-private `U32ToU32Map`-keyed side entry only for packed types
  (`pkSetFields`/`pkUnSetFields`/`pkSetFields` callers).
- **Sites.** `type_registry.zig:249,251-254,269,271-277`; readers `:1096,:1111,:1162,:1176`.
- **Resident prize.** ~**(215−packed)×12 ≈ 2.5 KB** live (plus 2×12 for `pk_un_items`), plus
  growth. Small.
- **Aliasing.** None extra.
- **Risk.** **Low.**
- **Gate.** Common + markers byte-identical.

### Rejected / not actionable (with reasons)

- **In-place realloc growth (`sandTryReallocInPlace`, `allocator.zig:219-232`, already wired in 20+
  modules).** `typeRegistryEnsureCapacity`, `arrayGrow`, and the map `*Grow` all interleave
  allocations (a payload append sits between consecutive `Type` appends; other structures' appends
  sit between cache puts), so the growing array is essentially **never at the arena tail**
  (`old_end == sand.start+sand.pos`) and the in-place branch would ~never fire. The prior census's
  row-1/row-5 `1,495 K / 233 K` in-place prizes assume the tail condition holds; **static analysis
  says it does not for the registry**. Do not fund this without a measured hit rate. R1 (right-size)
  captures the same abandoned-generation waste without depending on the tail.
- **Free/caches-reset before emission (lens 2).** The 8 caches are provably **not read during
  emission** (grep: `nameCacheGet/Put`/`.ptr_cache` never appear in `c89_emit.zig`; the registry's
  own caches are private), so a sub-arena reset after lowering is *logically* safe. But RSS is a
  **high-water mark** and the allocator never returns pages to the OS (`sandReset` only splices
  segments into `seg_free_head` for reuse). Freed-but-not-reused pages stay resident; reused pages
  are re-touched. **Resident prize ≈ 0.** Rejected (same conclusion as Task 1's one-use lens).
- **SoA split / pointer-vs-inline.** Rejected: (a) `Type` is read via thousands of
  `types_items[i].field` sites across `c89_emit`/`lower`/`semantic_analyzer`; a hot/cold split
  rewrites the entire access surface (huge risk, no clear byte win over the 16-B AoS); (b) inlining
  field entries or interleaving arrays breaks the `fe_items`/`pk_items` slice contract (§Step-2
  aliasing). No further win on 32-bit (pointer == offset == 4 B).
- **Merge `ptr_cache`+`many_ptr_cache`** (same `base<<2|q` key, kind bit in a spare bit): saves one
  small map (~248 cumulative slots ≈ 3 KB). Correct but trivial; fold into R1/R3 if convenient.
- **Drop the `occupied` byte / hash-map restructure** = the explicitly **deferred hash-map layout**
  (plan "Deferred"): out of scope here.

### Four-lens verdicts

1. **Integer reuse / interning + redundant derivable columns.** `FnPayload.name_id`≡`Type.name_id`
   and `FnPayload.module_id`≡`Type.module_id` (R4); dead `is_signed`; sparse `width_bits`/
   `c_name_id`/`module_id`; `pk_struct/pk_un` parallel arrays (R6); `state` 1-bit. R2/R4/R6.
2. **One-use / retention.** Caches die before emission but **RSS high-water makes freeing
   worthless** (no free-to-OS); no actionable retention lever. Not funded.
3. **Representation.** `Type` 32→16 (R2); cache/payload column narrowing within observed ranges
   (R3/R5); right-size to kill abandoned generations (R1, the biggest); sparse `c_name_id`/packed
   side tables.
4. **Pointer vs inline, mutation safety.** Inline/SoA **rejected** on the growable-`fe_items`/
   `pk_items` slice hazard and access-surface cost; right-sizing is pointer-stable and safe.

### Ranking and honest total

| rank | candidate | resident prize | confidence | risk |
|---:|---|---:|---|---|
| 1 | R1 right-size registry arrays + caches | **≈380–400 KB** | Med (hint/data-dependent) | Med |
| 2 | R2 `Type` 32→16 | **≈105 KB** standalone (≈40 KB after R1) | High | Med |
| 3 | R3 cache value/key narrowing | **≈70 KB** | High | Low–Med |
| 4 | R4 `FnPayload` dedup | **≈29 KB** | Med | Med |
| 5 | R5 `FieldEntry`/`xt`/`StructPayload` narrowing | **≈15–25 KB** (est) | Med | Med |
| 6 | R6 `pk_struct`/`pk_un` sparse | ≈2.5 KB | High | Low |

R1+R2+R3 (the high-confidence set, R2/R1 non-additive) ≈ **350–420 KB resident**; adding R4–R6
≈ **400–470 KB**. The remaining gap after Task 2 is **≈712 KB**, so **the type-registry package
alone is unlikely to trigger the stop-gate** — expect the plan to proceed to Task 5 (comptime fold
table) unless R1 lands larger than projected. The stop-gate is **not** met by this task (read-only).

### Closed levers — explicitly NOT re-opened

- **Sparse→dense** for `coercion` / `enum_value_table` / `comptime_values` — **CLOSED**
  (sparse-wins; dense adds ~4.7 MB). Nothing in this report proposes densifying them.
- **16-B `AstNode` (I-COMPACT)** — **CLOSED** (byte-neutral/net-worse). This report's "16" is the
  `Type` registry struct, a different structure; no AST node work.
- F-1/I-F1 free-list, M5, prior S-INTERNER scope — untouched/unmentioned by any candidate here.

---

## Step 3 — Scope / commit

No `sf/src` edit, no rewiring, no instrumentation, no seed build, no measurement, no subagents.
Only this report (and the pre-existing `progress.md` ledger change) are committed with
`git add -f` (`docs: structural live-set plan — Task 3 type-registry analysis`). Branch
`zig1_improvements`, **no push**. Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`,
`for_closed.z98`, `for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`)
left untouched.

## Concerns

1. **Gate not reachable from this package alone.** Best realizable ≈0.4–0.47 MB vs a ≈0.712 MB gap;
   do not expect Task 4's stop-gate to fire. Task 5 should be planned.
2. **R1's hint is the crux and is data-dependent.** Probe the corpus/stdlib for max type and
   `name_cache` counts before fixing a hint; an undershoot grows from the hint (bounded residual),
   an overshoot only touches the `occupied` array (cheap). `pool` must remain under the enforced
   `max_mem` (`checkCombinedPeak`, `allocator.zig:288-302`).
3. **Range guards for u16/u8 narrowing.** `name_id`/`c_name_id` are interner ids (13,286 / ≤34 K at
   self-compile) and `module_id`≤44, but huge multi-module inputs could exceed 65,535 / 255; the Fix
   must add a documented fallback or hard check and probe corpus + `verify_stdlib`. The narrowing
   edit surface also **extends outside `type_registry.zig`** — external whole-struct RMW writers of
   `payload_idx`/`alignment` and external `FieldEntry`/`StructPayload` builders (see R2/R5 Sites)
   each need a cast; risk for R2/R5 is **Med**, not Low–Med.
4. **Counts are HEAD-dependent.** The 2,497 per-kind census is from the **pre-Task-2** capture
   (`perm=982K`); Task 2 added ~19 interned names, so counts shift by a few. Task 4 must re-derive
   from the new `DC:`/`track-memory` stream.
5. **`fe_len`/`xt_len` are not in the captured markers**, so R5's prize is estimated (struct/field/
   fn-parameter arithmetic), not measured.
6. **In-place growth is a trap here.** The census's in-place prizes assume an arena-tail condition
   that registry interleaving defeats by construction; do not implement it on faith.
