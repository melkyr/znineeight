# Task 4 — Fix the type registry (R1 + R2) → STOP-GATE

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push).

Implemented the controller-selected **R1 (★ right-size)** and **R2 (★ `Type` 32→16 B)** from
`task-3-report.md`. **R3–R6 were NOT implemented**, no closed lever was re-opened
(`coercion`/`enum_value_table`/`comptime_values` stay sparse; no 16-B `AstNode` work; no hash-map
layout restructure), and the `fe_items`/`pk_items` growable-slice contract was left intact. No
subagents were dispatched.

Source edit: `sf/src/type_registry.zig` (primary), `sf/src/main.zig`, `sf/src/c89_emit.zig`,
`sf/src/lower.zig`, `sf/src/symbol_registrator.zig`, `sf/src/type_resolver.zig`, and the two test
binaries that write the narrowed `Type.payload_idx` column
(`sf/src/tests/test_semantic_bin.zig`, `sf/src/tests/test_sym_reg_bin.zig`).

---

## Step 1 — Mechanism + file:line

### R1 — right-size (hint-seeded) registry arrays and caches

Cause (Task-3 §1.5): `type_db` is a never-reset `GrowableSand`; every geometric `arrayGrow`
(`type_registry.zig:207`), `typeRegistryEnsureCapacity` (`:244`) and `u64ToU32MapGrow`
(`util/hash.zig`) allocates a **new** array and abandons the old one in place, so the previous
generation stays resident. `typeRegistryInit` started everything at cap 0/8.

- `sf/src/type_registry.zig:447-482` — new `typeRegistryInitSized(alloc, interner, type_hint,
  name_hint)`. It starts from the **unchanged** legacy `typeRegistryInit` (2-arg, hints 0 ⇒ exact
  old zero-cap behaviour, so the ~100 test callers are untouched), then:
  - re-inits the 8 id-caches with the **existing** `hash_mod.u64ToU32MapInitCap` /
    `u32ToU32MapInitCap` (`util/hash.zig:147,39`), hints proportional to `type_hint`:
    `ptr`/16, `many_ptr`/64, `slice`/128, `optional`/128, `array`/32, `eu` 8, `es` 4,
    `name_cache` = `name_hint`;
  - `typeRegistryEnsureCapacity(&reg, type_hint)` pre-sizes the `Type[]` (cap 4,096 at
    self-compile);
  - `arrayReserve(...)` (`:230-239`, new; one `sandAlloc`, no zeroing, no copy) pre-sizes every
    payload array near its Task-3 census final (`fn`/2, `fe`/2, `xt`=th, `xn`/16, `em`/16,
    `ptr`/8, `array`/16, `slice`/64, `opt`/64, `st`/16, `pk`/16, `pk_struct`/16, fixed small for
    `eu`/`es`/`en`/`un`/`tu`/`tup`/`unr`/`pk_un`).
- `sf/src/main.zig:188-207` — hints threaded from the source length (mirrors the landed interner
  pre-size): `type_hint = max(4096, source.len/32)`, `name_hint = max(2048, source.len/10)`
  (self-compile: 4,096 / 10,063 ⇒ `name_cache` cap 16,384, since `mapCapacityFromHint(10063) =
  next_pow2(ceil(10063·4/3)) = 16,384`). Call site `main.zig:207`.
- **Hints are a SOFT pre-size floor, never a hard cap.** If an input exceeds a seed,
  `arrayGrow`/`typeRegistryEnsureCapacity`/`*MapGrow` resume normal doubling; only the saving is
  lost, correctness is preserved. The seeded payload arrays are bump-allocated and **not zeroed**
  (`sandAlloc` does not zero), so an unwritten tail is carved but not resident; only the map
  `occupied` arrays are zeroed (cap bytes, ≤ the abandoned occupied they replace).

### R2 — shrink `Type` 32 B → 16 B

- `sf/src/type_registry.zig:70-85` — layout is now exactly the Task-3 §R2 plan (emitted C confirms
  it, `zig_special_types.h`): `size u32`(0), `name_id u16`(4), `payload_idx u16`(6), `kind`
  enum-u8(8), `module_id u8`(9), `flags u8`(10), `state u8`(11), `iw u8`(12, arb width),
  `alignment u8`(13) ⇒ **16 B**. Dropped the dead `is_signed` (signedness is derived from `kind` by
  `typeRegistryIntIsSigned`); removed `c_name_id` from the struct.
- `sf/src/type_registry.zig:176-205` — documented ceiling guard `typeDbCeiling` +
  `typeNarrowU16`/`typeNarrowU8`. `Type.name_id` (interner id) and `Type.module_id` are written
  through these where the column narrows (`registerPrimitiveName`:827, `GetOrCreateFn`:707,
  `GetOrCreateModule`:775, `RegisterNamedType`:938-940, `registerPrimitive`:385-386); a value above
  65,535 / 255 reports `error: type_registry <field> exceeds <limit> (value <v>)` and exits rather
  than silently truncating. (`c_name_id` needs no guard — it now lives in a `U32ToU32Map` and
  carries a full `u32`.)
- `sf/src/type_registry.zig:148,433,507-513` — sparse `c_name_id` moved to the registry-private
  `c_name_map: hash_mod.U32ToU32Map` side memo with `typeRegistryCNameIdGet`/`typeRegistryCNameIdSet`.
  `c89_emit.zig:1046` (read) and `c89_emit.zig:2404` (write) rerouted through them; `iw` read at
  `c89_emit.zig:5933` and `lower.zig:1270`.
- **External writers** of narrowed columns now `@intCast` (report Sites, all touched):
  - `payload_idx`→u16: `symbol_registrator.zig:127,156,184,195,224,240`;
    `type_resolver.zig:1602,1638,1681,1691`; tests (`test_semantic_bin.zig:240,347`,
    `test_sym_reg_bin.zig` 9 sites).
  - `alignment`→u8: `type_resolver.zig:298,299,306,324,325,352,359,369,375,392,393,581`.
  - `state` writes stay u8; `c_name_id` rerouted (above). External **readers** were not edited
    (Zig widens `u16`/`u8`→`u32` implicitly), except three mixed-width `if`-expression ternaries
    that the seed could not peer-resolve (`type_registry.zig:597,626`, `type_resolver.zig:347,357,365`)
    and one locally-typed capture (`c89_emit.zig:1125`), which now explicitly `@intCast(u32, …)`.

### Aliasing

`Type` is a value array with no handed-out slice; narrowing is safe. R1 only changed capacities and
left every array's element identity/pointer-return contract unchanged; `fe_items`/`pk_items` are
still growable slices with the same "no append while a slice is live" discipline.

---

## Step 2 — Build, equivalence battery, markers

### Seed build (no `FIXED_POINT_MD5` pin)

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/struct_seed4`

- archive md5 `3cacdd44df75c0ce96abfd51af93f928` (v92, unchanged).
- `[seed] two-hop closure OK: hop1 == hop2 == ` **NEW fixed point / binary md5
  `078ed10fc3477c0cfd07140b2dfb4ece`** (moved from Task-2 `9cdcc97bb8dc0a0b94e29b9e981e5376`;
  recorded, not silent). Measurement binary: `/tmp/struct_seed4/zig1_5_clean`.

### Self-compile (`-s0 --markers --track-memory`, repo root, RELATIVE path)

- rc 0, **0 `error[` / 0 `PANIC`**, **48 `.c` / 48 `.h`**, no `warning[3000]` type mismatch.
- `track-memory: perm=760K mod=1020K scr=1020K pool=14064K type_db=249K total=2800K`
  (Task-2 baseline: `type_db=346K pool=14362K` ⇒ **type_db −97 K** on the last segment; the
  never-reset `type_db` carve from `arena type_db: grew` sums moved 1,036,288 → 946,176 B, **−90,112 B**).

### Dump-MD5 8/8 (stdout stream) — delta 0

| program | `-fsafe` | pin | `-ffast` | pin |
|---|---|---|---|---|
| game_of_life | `6df1e4d2e9afa0f4163a7053f67384be` | ✅ | `98e934f3e15be355d47e26ded595dc8a` | ✅ |
| lisp_interpreter_curr | `e27b7c35678974deb130cfc77cb08686` | ✅ | `2514f8b5ddceacba67203af37a7346c3` | ✅ |
| json_parser | `d51f17aebdabcd009e453adb2e286d4e` | ✅ | `e1cc386e9d09e322a068731cb2061621` | ✅ |
| mud_server | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | ✅ | `66d547d4a076fc2ce44d6d3aa3092c1d` | ✅ |

**dump-MD5 delta = 0 → byte-identical output** (as predicted: only widths/capacities changed, never
ids or insertion order).

### corpus — `scripts/corpus/classify`

`1097` dirs = **923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** — exact match.

### stdlib — `scripts/stdlib/verify_stdlib.sh`

`run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → `STDLIB GATE OK`.

### examples matrix — 24/24

`MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0` (20 `main.zig` dirs + 4 single-file
entries `func_ptr_return`, `mandelbrot`, `quicksort`, `sort_strings`; dump + gcc + link). Entries
set matches `/tmp/struct_examples` (Task-2 canonical set).

### Runtime goldens

| golden | observed | pinned |
|---|---|---|
| gol stdout | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | ✅ |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | ✅ |
| json stdout (`test.json` from its dir) | `8bda3d5a1ec07d14a301bc343df32bf8` | ✅ |
| mud server / client | `66c8f0abb926cca7baf9a0d1692ab318` / `93147d0f0bbd983a9d844fea8b7a6fa7` | ✅ |

### Semantic markers — byte-identical IN-SESSION

Same input (`sf/src/main.zig`, the new source) compiled by the **Task-2 baseline** binary
(`/tmp/struct_seed/zig1_5_clean`, md5 `9cdcc97b…`) and the **new** binary (`078ed10f…`), both
`-s0 --markers --track-memory`; filtered `arena .*: grew` and `track-memory:` (legitimately shift):

```
filtered lines: base 48788 / new 48788
diff markers.filt → rc 0, 0 diff lines
```

No residual diff. (`type_db`'s `arena: grew` ladder does change, as expected, and is filtered.)

---

## Step 3 — Peak RSS (median of ≥3, interleaved)

`/usr/bin/time -v` Maximum RSS, `-s0` self-compile, alternating baseline/new, fresh `-o` dir:

5-pair batch (primary):

| run | baseline (`9cdcc97b…`) | new (`078ed10f…`) | delta |
|---|---:|---:|---:|
| 1 | 17,012 K | 16,720 K | −292 |
| 2 | 16,996 K | 17,116 K | +120 |
| 3 | 17,096 K | 16,880 K | −216 |
| 4 | 17,272 K | 16,832 K | −440 |
| 5 | 17,100 K | 16,980 K | −120 |
| **median** | **17,096 K** | **16,880 K** | **−216 K** |

An earlier 3-pair interleaved batch gave base median 16,804 K / new 16,732 K (**−72 K**). Pooled
across all 8 interleaved pairs the per-pair median delta is ≈ **−168 K** (host noise ±~150 K).

- **new RSS median = 16,880 K** (5-pair), **delta ≈ −216 K** vs the interleaved Task-2 binary.
- Consistent in sign with the type_db carve reduction, but **materially smaller than the Task-3
  R1+R2 projection** (~350–420 K): `GrowableSandGrow` doubles the whole segment regardless of the
  per-array abandoned generations, so the never-reset arena's segment ladder masks part of the
  per-array saving (see Concerns).

---

## STOP-GATE verdict

**Peak RSS ≤ 16,384 K? NO — 16,880 K > 16,384 K.** The stop-gate is **NOT** triggered. Per the
plan, the type-registry package is complete and the plan proceeds to **Task 5 (comptime fold
table)** — do not stop at Task 7 yet.

---

## Scope / commit

- Source edits: `sf/src/{type_registry,main,c89_emit,lower,symbol_registrator,type_resolver}.zig`
  + the two test binaries' narrowed-column casts. Commit
  `refactor(type-registry): structural reduction`; branch `zig1_improvements`, **no push**.
- Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`,
  `for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) left untouched.

## Concerns

1. **R1 under-delivers vs projection.** Measured type_db carve −90 K, RSS ≈ −150…−220 K, vs the
   Task-3 ~380–400 K estimate. Root cause is structural: `GrowableSandGrow` allocates a whole new
   segment at 2× the previous segment size (exact-fit only when one request exceeds that), so the
   arena's segment ladder — not the per-array abandoned generation — dominates the carve. The
   right-size still removed the early small generations and is strictly positive, but the
   "abandoned ≈ live per array" model in §1.5 overstates the recoverable resident bytes.
2. **Gate not met** (expected). Remaining gap after Task 4 ≈ 496 K; Task 5 must not assume the
   16 MB target is near.
3. **Range guards unexercised.** `typeNarrowU16`/`typeNarrowU8` ceilings (65,535 / 255) never fire
   on the self-compile, corpus or stdlib; correctness for a >65K-name or >255-module input is by
   the documented hard check only.
4. **Test binaries** compile-fixed (narrow casts) but were not built/run — the binding battery is
   corpus/stdlib/examples/goldens, and no test build path is in this plan's gates.
5. **`c_name_id` side memo** adds one `U32ToU32Map`; it is sparse (6 live entries) and never
   pre-sized. Dump/goldens prove the memo path is byte-identical to the old column.
