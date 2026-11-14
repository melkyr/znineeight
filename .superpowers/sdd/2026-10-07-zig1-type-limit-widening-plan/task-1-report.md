# Task 1 report — Widen the `Type` ceiling columns

Plan: `docs/superpowers/plans/2026-10-07-zig1-type-limit-widening-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-type-limit-widening-design.md`
Branch: `zig1_improvements` (NO push). `edit`/`fastedit` only. Date: 2026-10-08.

## Step 1 — Widened `Type` layout (20 B) + declaration comment

`sf/src/type_registry.zig` fields (declaration order, comment updated):

```
size u32 (0), name_id u32 (4), payload_idx u32 (8), kind u8 (12),
flags u8 (13), state u8 (14), iw u8 (15), module_id u16 (16), alignment u16 (18) = 20 B
```

- `name_id` u16→u32, `payload_idx` u16→u32, `module_id` u8→u16, `alignment` u8→u16.
- `size`/`kind`/`flags`/`state`/`iw` unchanged.

**Layout note (important).** The brief/spec expect **20 B** and say `module_id`/`alignment`
"widen into existing struct padding". Z98's struct layout (`type_resolver.layoutCompute`) and its
C emitter are **declaration order** with C padding; leaving `module_id` between `kind` and `flags`
would yield **24 B** (offset 13 pad, offset 19 pad). To reach the specified 20 B, the two u16
columns were placed **after** the u8 columns (`module_id` moved from index 5 to index 8, `alignment`
stays last). This is the only deviation from a literal in-place width change; it is a field-order
placement to satisfy the binding 20-B design, not a logic change. All accesses are by name (Zig
struct literals + emitted C), and the array is copied element-wise (`typeRegistryEnsureCapacity`),
so the reorder is layout-only.

Emitted `zig_special_types.h` (`zT_D155D06D_Type`, from the new hop1):

```
struct zT_D155D06D_Type {
    unsigned int size;
    unsigned int name_id;
    unsigned int payload_idx;
    zT_33EF6BFB_TypeKind kind;      /* unsigned char */
    unsigned char flags;
    unsigned char state;
    unsigned char iw;
    unsigned short module_id;
    unsigned short alignment;
};
```

**Size confirmed 20 B** (gcc `-m32 -std=c89` mirror of the emitted order: `sizeof=20`,
`module_id` offset 16, `alignment` offset 18).

## Step 2 — Guards removed + call-site inventory

Removed in `type_registry.zig`: `typeDbCeiling`, `typeNarrowU16`, `typeNarrowU8` (and the
"Task 4 R2 ceiling guard" comment). No references remain anywhere in `sf/src`.

Internal `type_registry.zig` writers (all updated):
- `name_id` → plain (`registerPrimitiveName` `= nid`; fn + `registerNamedType` literals `= name_id`);
  literal-zero writes → `@intCast(u32, 0)` (`registerPrimitive`, ptr, many_ptr, slice, optional,
  error_union, array, tuple, error_set, module, arb_int, `registerNamedType`).
- `payload_idx` → plain (9 sites: ptr, many_ptr, slice, optional, error_union, array, tuple, fn,
  error_set — all `@intCast(u32, self.<kind>_len - @intCast(usize, 1))`); literal-zero →
  `@intCast(u32, 0)` (registerPrimitive, module, arb_int, registerNamedType).
- `module_id` → `@intCast(u16, …)` (registerPrimitive/ptr/many_ptr/slice/optional/error_union/array/
  tuple/fn/error_set/arb_int = 0; module + `registerNamedType` = `module_id`).
- `alignment` → `@intCast(u16, …)` (registerPrimitive `alignment`; ptr/many_ptr/slice/error_set/fn
  = 4; optional `opt_align`; error_union `eu_align`; array `arr_align`; tuple = 1; module = 0;
  arb_int `carrier`; `registerNamedType` = 0; packed struct/union layout `@intCast(u16, 1)` at the
  two former `@intCast(u8,1)` sites).

External writers:
- `sf/src/symbol_registrator.zig` — 6 `payload_idx` sites (`typeNarrowU16` → plain): `tup_idx`,
  `st_idx`, `tu_idx`, `un_idx`, `en_idx`, `es_idx`.
- `sf/src/type_resolver.zig` — 4 `payload_idx` sites (`typeNarrowU16` → plain): `tup_tidx`,
  `sd_st_idx`, `un_tu_idx`, `un_un_idx`; 12 `alignment` sites (`typeNarrowU8` → `@intCast(u16,…)`):
  `layoutCompute` (struct/enum/union/tagged-union/optional/error-union/array/tuple + the three
  zero-size→1 fallbacks) and the circular-type fallback.
- Test binaries: `sf/src/tests/test_sym_reg_bin.zig` (8 `payload_idx` sites, lines 251/276/301/
  374/397/986/1055/1059) — the source expressions (`*_len - 1`, `a_sp_idx`/`b_sp_idx`) are
  **`usize`**, so the cast was updated to `@intCast(u32, …)`, NOT dropped; `sf/src/tests/
  test_semantic_bin.zig` (2 `payload_idx` sites, `pidx` already u32) — `@intCast(u16, …)` → plain.
  **Note:** these two test binaries **already fail to build at base** on a pre-existing unrelated
  `error[3061] semanticAnalyzerInit expected 17 args, found 8`, so they are **not gate-verified** by
  this plan's battery; the `test_sym_reg_bin.zig` fix removes the `warning[3000]` this task
  introduced (no base-fixed-point movement — see Step 4).

No `@intCast(u16,…)`/`@intCast(u8,…)` targeting these four fields remains (`grep` clean).

## Step 3 — Stale docs updated

`sf/docs/tech_docs/03_type_resolution.md` (directly stale): added a leading `[updated: 2026-10-08 …]`
bracket; Summary Table `Type fields` row (u32/u32/u16/u16, 20 bytes) and Data Structures `Type`
row (`size(u32,0)`, `name_id(u32,4)`, `payload_idx(u32,8)`, `kind`(12), `flags`(13), `state`(14),
`iw`(15), `module_id(u16,16), `alignment(u16,18)`, **20 bytes total**).

## Step 4 — Build, battery, markers, RSS

### Seed build (no `FIXED_POINT_MD5`)

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/widen_seed`

- `[seed] two-hop closure OK: hop1 == hop2 == ` **NEW fixed point / binary md5
  `296c48f676deec290387b57132e4e2bd`** (moved from `639902d5146233091f6b2f98508ce3eb`; recorded,
  not silent). `/tmp/widen_seed/zig1_5_clean` md5 = `296c48f676deec290387b57132e4e2bd`.

### Self-compile (`-s0 --markers --track-memory`, repo root, RELATIVE path)

- rc 0, **0 `error[` / 0 `PANIC`**, **48 `.c` / 48 `.h`**. (97 pre-existing non-blocking
  `warning[18]`/`warning[3037]`; no `warning[3000]` type mismatch, no narrowing/truncation note.)
- `track-memory: perm=761K mod=1023K scr=1020K pool=11958K type_db=243K total=2804K`
  (baseline seed: `pool=11965K type_db=249K`).

### Dump-MD5 8/8 (stdout stream) — delta 0

| program | `-fsafe` | pin | `-ffast` | pin |
|---|---|---|---|---|
| game_of_life | `6df1e4d2e9afa0f4163a7053f67384be` | ✅ | `98e934f3e15be355d47e26ded595dc8a` | ✅ |
| lisp_interpreter_curr | `e27b7c35678974deb130cfc77cb08686` | ✅ | `2514f8b5ddceacba67203af37a7346c3` | ✅ |
| json_parser | `d51f17aebdabcd009e453adb2e286d4e` | ✅ | `e1cc386e9d09e322a068731cb2061621` | ✅ |
| mud_server | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | ✅ | `66d547d4a076fc2ce44d6d3aa3092c1d` | ✅ |

**dump-MD5 delta = 0** (as predicted: widths/layout changed, ids/insertion order did not).

### corpus — `scripts/corpus/classify`

`1097` dirs = **923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH** — exact match.

### stdlib — `scripts/stdlib/verify_stdlib.sh`

`run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → `STDLIB GATE OK`.

### examples matrix — 24/24

`MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0` (20 `main.zig` dirs + 4 `<name>.zig`
entries `func_ptr_return`, `mandelbrot`, `quicksort`, `sort_strings`; dump + gcc `-m32 -std=c89
-O0 … -I . -c *.c` + `gcc -m32 -O0 *.o`).

### Runtime goldens

| golden | observed | pinned |
|---|---|---|
| gol stdout | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | ✅ |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | ✅ |
| json stdout | `8bda3d5a1ec07d14a301bc343df32bf8` | ✅ |
| mud server / client | `66c8f0abb926cca7baf9a0d1692ab318` / `93147d0f0bbd983a9d844fea8b7a6fa7` | ✅ |

### Semantic markers — byte-identical IN-SESSION

Same input (`sf/src/main.zig`, the new source) compiled by the baseline seed binary
(`639902d5146233091f6b2f98508ce3eb`) and the new binary (`296c48f6…`), both
`-s0 --markers --track-memory`; filtered `arena .*: grew` + `track-memory:` (legitimately shift):

```
filtered lines: base 48819 / new 48819
diff → rc 0, 0 diff lines
```

No residual diff. (`type_db` carve ladder changes, as expected, and is filtered.)

### Peak RSS (median of interleaved `-s0` runs)

`/usr/bin/time -v` Maximum RSS, `-s0` self-compile, fresh `-o` dir each run. Two 5-pair
interleaved batches (batch 1 base→new, batch 2 new→base):

| batch | baseline median | new median |
|---|---:|---:|
| 1 (5 pairs) | 16,108 K | 15,512 K |
| 2 (5 pairs) | 15,944 K | 15,536 K |
| **pooled (10 each)** | **16,030 K** | **15,516 K** |

- **New RSS median ≈ 15,516 K; target ≤16,384 K MET** (margin ≈868 K).
- **Delta ≈ −514 K** (new *lower*) vs the adopted ≈16,150 K baseline. This is **opposite in sign**
  to the spec's expected `+10–16 KB`. The +4 B/type widening cost (~+16 KB at cap 4,096) is far
  below the inter-batch host variance (±~150–250 K) and the per-binary arena/LIR-pool carve
  differences already exceed it, so the absolute delta is not attributable to the widening alone.
  The only directional effect attributable to the change (`track-memory` `type_db` grew-sum
  159,744 → 421,888 B) is the expected carve increase; the final resident `type_db` (249K→243K)
  and pool (11965K→11958K) moved within noise. See Concerns.

## Scope / commit

- Source edits: `sf/src/{type_registry,symbol_registrator,type_resolver}.zig` + the two test
  binaries' `payload_idx` casts; doc: `sf/docs/tech_docs/03_type_resolution.md`.
- `sf/src/string_interner.zig` and `sf/src/comptime_eval.zig` **untouched** (per constraint).
- Pre-existing untracked root strays and the structural plan's `progress.md` left untouched.

## Concerns

1. **20-B layout required a field reorder.** The brief said "widen the fields"; declaration-order
   widening yields 24 B, not the binding 20 B. I moved `module_id`/`alignment` after the u8 columns
   to satisfy the spec's stated 20-B layout ("absorbed by padding"). If the intended answer was
   literal declaration order (24 B), this is the one place to revisit; RSS/target would still pass.
2. **RSS delta sign.** Measured delta is ≈ −514 K (new lower), not the predicted +10–16 K. The
   ≤16,384 K target is met with ~868 K margin. Cause is host/arena variance dominating the ~16 KB
   widening cost; no correctness or battery impact.
3. `warning[18]` (return >64 B) / `warning[3037]` (potential null deref) are pre-existing, not
   introduced here.
