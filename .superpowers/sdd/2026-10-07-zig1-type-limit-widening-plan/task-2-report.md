# Task 2 report — Closeout (re-verify, limits note, seed v94)

Plan: `docs/superpowers/plans/2026-10-07-zig1-type-limit-widening-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-type-limit-widening-design.md`
Branch: `zig1_improvements` (NO push). `edit`/`fastedit` only. Date: 2026-10-08.
HEAD at start of task: `78dd4593` (`refactor(type-registry): widen Type ceiling columns`).

## Step 1 — Re-verification at HEAD (`78dd4593`)

Rebuilt the seed against current `sf/src` (no `FIXED_POINT_MD5` pin):

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/widen_seed7
[seed] hop1 binary md5: 296c48f676deec290387b57132e4e2bd
[seed] hop2 binary md5: 296c48f676deec290387b57132e4e2bd
[seed] two-hop closure OK: hop1 == hop2 == 296c48f676deec290387b57132e4e2bd
=== [seed] Done: /tmp/widen_seed7 ===
```

`/tmp/widen_seed7/zig1_5_clean` md5 = **`296c48f676deec290387b57132e4e2bd`** (confirmed). `gen/` and
`hop2/` emissions are byte-identical (145 module+support files each; no diffs), so the fixed point is
stable across the two hops.

### Battery at HEAD (all executed; nothing skipped)

| gate | observed | pinned / expected | verdict |
|---|---|---|---|
| dump-MD5 (`-fsafe` ×4 + `-ffast` ×4) | `6df1e4d2…`/`98e934f3…`, `e27b7c35…`/`2514f8b5…`, `d51f17ae…`/`e1cc386e…`, `f3be9bb9…`/`66d547d4…` | 8 pins | **8/8 PASS (delta 0)** |
| corpus `scripts/corpus/classify` | `1097 = 923 OK / 58 GREEN / 116 FAIL` | 923/58/116, 0 ICE / 0 CRASH | **exact** |
| `verify_stdlib.sh` | `266 PASS / 0 FAIL over 266 dirs` | 266/0 | **STDLIB GATE OK** |
| examples matrix | `MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0` | 24/24 | **PASS** |
| goldens gol/lisp/json/mud | `fcbf7e7c…` / `b3d9f897…` / `8bda3d5a…` / srv `66c8f0ab…` cli `93147d0f…` | same | **all pinned** |
| semantic markers (in-session) | base 48819 / new 48819 filtered lines, `diff` rc 0 | byte-identical | **diff 0** |
| self-compile | rc 0, 0 `error[`, 0 PANIC, 48 `.c`/48 `.h` | — | **PASS** |

- Dump-MD5 emitted from the repo root with the relative `examples/z98/<p>/main.zig` path
  (`--dump-c89` stdout stream); all 8 pins matched.
- Markers compared **in-session** on the identical input (`sf/src/main.zig`, current source): baseline
  seed binary (`/tmp/widen_seed7/_unpack/zig1-seed/zig1`, md5 `639902d5146233091f6b2f98508ce3eb`) vs
  the new binary (`296c48f6…`), both `-s0 --markers --track-memory`; telemetry (`arena .*: grew`,
  `track-memory:`) filtered from both. Residual = 0.
- `track-memory` at HEAD: `perm=761K mod=1023K scr=1020K pool=11958K type_db=243K total=2804K`
  (baseline seed: `pool=11965K type_db=249K`).

**Ceiling confirmation:** the four `Type`-column ceilings are gone/residual-only —
`name_id`/`payload_idx` are u32, `module_id`/`alignment` are u16. The earlier narrowing's u16/u8
ceilings (65,535 strings / 65,535 payload / 256 modules / 255 alignment) are removed; only the u16
pair remains (65,535), effectively unreachable. `typeDbCeiling`/`typeNarrowU16`/`typeNarrowU8` are
absent from `sf/src` (Task 1).

### Final peak RSS (median of ≥3 interleaved `-s0`)

`/usr/bin/time -v` Maximum RSS, `-s0` self-compile (`--markers --track-memory`), fresh `-o` dir ×5,
repo root CWD, relative path:

| run | 1 | 2 | 3 | 4 | 5 | **median** |
|---|---|---|---|---|---|---|
| RSS (K) | 15,436 | 15,824 | 15,236 | 15,448 | 15,508 | **15,448** |

All 5 samples ≤16,384 K; **median 15,448 K ≤ 16,384 K (the 16 MB target) — margin ≈936 K.** Median
≈15.1 MB. (The expectation was ≈15.5–15.7 MB; the fresh median landed ~0.4–0.6 MB lower — host
variance, well inside the target and consistent with Task 1's pooled 15,516 K.)

## Step 2 — Docs updates

- `docs/sf/QUICK_REF.md`: added a new **`### Compiler limits — Type-column ceilings [added: 2026-10-08]`**
  subsection recording the u32 `name_id`/`payload_idx`, the u16 `module_id`/`alignment` residual
  ceilings (65,535, effectively unreachable), the earlier 32→16 narrowing's u16/u8 ceilings
  (65,535 strings / 65,535 payload / 256 modules / 255 alignment) that this change raised, and that
  the string interner buckets auto-migrate u16→u32 (no ceiling). Also updated the seed block
  **v93 → v94** (archive md5 + fixed point + pool/RSS figures) — the block is documented as updated at
  every closeout that rotates the seed.
- `sf/docs/tech_docs/03_type_resolution.md`: **confirmed 20 B** (`Type` row: `size(u32,0)`,
  `name_id(u32,4)`, `payload_idx(u32,8)`, kind/flags/state/iw (12–15), `module_id(u16,16)`,
  `alignment(u16,18)` — "20 bytes total"); updated in Task 1. **No fix needed (not stale).**

## Step 3 — Seed rotation v93 → v94

```
bash scripts/seed/archive_seed.sh /tmp/widen_seed7/zig1_5_clean /tmp/widen_seed7/gen \
    release/seed/zig1-seed.tgz --update-changelog
```

- `<binary>` = `/tmp/widen_seed7/zig1_5_clean` (md5 `296c48f676deec290387b57132e4e2bd`);
  `<gen_dir>` = its build output dir `/tmp/widen_seed7/gen`.
- Archive C gcc-only rebuild reproduced `296c48f676deec290387b57132e4e2bd`.
- **Archive md5 changed:** `e1955908f3aa58992592f9c021c36d42` (v93) →
  **`16ca54bd63320a4ec1d8e8aee3fe2c43`** (v94).
- `release/seed/CHANGELOG.md` prepended `## 2026-10-08 — seed v94 (HEAD 78dd4593)` with the table
  (binary/fixed point `296c48f6…`, `gen/` 45 `.c` + 46 `.h` / 9,793,884 bytes, archive md5
  `16ca54bd…`). Pre-existing v93 and older entries retained.
- Clean v93→v94 rotation only (no other behavior); STOP rule not triggered.

## Step 4 — Report + commit

- Report: this file. Ledger: `.superpowers/sdd/2026-10-07-zig1-type-limit-widening-plan/progress.md`.
- Commit `docs: type-limit widening plan — closeout + seed v94`; stages `docs/sf/QUICK_REF.md`,
  `sf/docs/tech_docs`, `release/seed`, and (`git add -f`) the task-2 report + progress ledger.
- Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`, `for_open.z98`,
  `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) and the structural plan's
  `progress.md` left untouched. No `sf/src` production change in this task; no push.

## Concerns

1. **RSS median below the expected band.** Fresh median 15,448 K vs the expected ≈15.5–15.7 MB —
   within the ≤16,384 K target with ≈936 K margin, and consistent with Task 1's pooled 15,516 K.
   Host/arena variance, not a regression.
2. **Deviation inherited from Task 1 (not re-litigated):** the 20-B `Type` layout required the two u16
   columns after the u8 columns (in declaration order it would be 24 B). Confirmed in the emitted
   `zig_special_types.h`; all accesses are nominal.
3. The two edited test binaries (`test_sem_reg_bin.zig`, `test_semantic_bin.zig`) remain
   un-gate-verified due to pre-existing `error[3061]` `semanticAnalyzerInit` arity drift — unchanged
   from Task 1, not a widening defect.
