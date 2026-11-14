# Task 7 — Closeout (re-verify, docs, seed v93)

Plan: `docs/superpowers/plans/2026-10-07-zig1-structural-live-set-plan.md`
Spec: `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md`
Branch: `zig1_improvements` (NO push). No `sf/src` production edit in this task.

## Step 1 — Re-verification at HEAD (`d69f10e7`)

Rebuilt the seed from `release/seed/zig1-seed.tgz` (v92) against current `sf/src`
(no `FIXED_POINT_MD5` pin):

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/struct_seed7
[seed] two-hop closure OK: hop1 == hop2 == 44b8e7fff5a115743ab5c62adb849555
```

Independent fresh-dir rebuild reproduces the Task-6 fixed point exactly.

### Fixed points / dump-MD5 deltas

| stage | commit | fixed point (binary md5) | dump-MD5 |
|---|---|---|---|
| Task 0 adoption | `c8b87daa` | (v92-era, moving point `2293f756…`) | 8/8 |
| Task 2 interner | `25809d0b` | `9cdcc97bb8dc0a0b94e29b9e981e5376` | 8/8 (delta 0) |
| Task 4 type registry | `da376da0` | `078ed10fc3477c0cfd07140b2dfb4ece` | 8/8 (delta 0) |
| Task 6 comptime | `d69f10e7` | `44b8e7fff5a115743ab5c62adb849555` | 8/8 (delta 0) |

Every fix moved the fixed point; **every fix kept dump-MD5 at 8/8 — no dump-MD5 delta at any
step.** The three fixed points are recorded here and in `release/seed/CHANGELOG.md` (v93).

### Battery at HEAD (all executed; nothing skipped)

| gate | observed | pinned / expected | verdict |
|---|---|---|---|
| dump-MD5 (`-fsafe` ×4 + `-ffast` ×4) | 8 hashes | 8 pins | **8/8 PASS** |
| corpus `scripts/corpus/classify` | `1097 = 923 OK / 58 GREEN / 116 FAIL` | same | **0 ICE / 0 CRASH; exact** |
| `verify_stdlib.sh` | `266 PASS / 0 FAIL over 266 dirs` | 266/0 | **STDLIB GATE OK** |
| examples matrix | `MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0` | 24/24 | **PASS** |
| goldens gol/lisp/json/mud | `fcbf7e7c…` / `b3d9f897…` / `8bda3d5a…` / srv `66c8f0ab…` cli `93147d0f…` | same | **all pinned** |
| semantic markers (in-session) | base 48851 / new 48851 filtered lines, `diff` 0 | byte-identical | **diff 0** |
| self-compile | rc 0, 0 `error[`, 0 PANIC, 48 `.c`/48 `.h` | — | **PASS** |

- Dump-MD5 emitted from the repo root with the relative `examples/z98/<p>/main.zig` path
  (`--dump-c89` stdout stream); all 8 pins matched.
- Markers compared **in-session** on the identical input (`sf/src/main.zig`, current source) by
  the Task-4 binary `/tmp/struct_seed4/zig1_5_clean` (`078ed10f…`) vs the new binary
  (`44b8e7ff…`); telemetry (`arena .*: grew`, `track-memory:`) filtered from both. Residual = 0.
- `track-memory` at HEAD: `perm=761K mod=1023K scr=1020K pool=11965K type_db=249K total=2804K`.

### Final peak RSS (median of ≥3 interleaved `-s0`)

`/usr/bin/time -v` Maximum RSS, `-s0` self-compile, fresh `-o` dir per run:

| run | RSS |
|---|---:|
| 1 | 16,152 K |
| 2 | 16,276 K |
| 3 | 16,192 K |
| 4 | 15,940 K |
| 5 | 16,088 K |
| **median** | **16,152 K** |

All 5 samples ≤16,384 K; **median 16,152 K ≤ 16,384 K (the 16 MB / 16,384 K target)**. Consistent with
the Task-6 interleaved measurement (impl 16,174 K / reviewer 15,938 K). Final pool carve ≈11,965 K
(vs baseline 14,924 K). Peak RSS median ≈**16.0 MB** (baseline ≈17.4 MB at Task 0).

### Stop-gate record (what was / was not executed)

All three work packages (interner, type registry, comptime) **were executed**; the stop-gate first
fired only after Task 6 (comptime) at 16,174 K ≤ 16,384 K. Tasks 3/5 investigations and 4/6 fixes
preceded it, so no fix work was skipped. This closeout re-ran the full battery at HEAD as required.
No task in the plan remains unexecuted.

## Step 2 — Deferred structures (not in this plan)

Recorded for a future plan; the reconnaissance is the reference:

- **AST window / value-pool representation** (#4, ~0.9 MB module arena): 8 resident disk-blocks.
- **Hash-map layout** — interleaved single array (buckets + entries co-located).
- **One-use retention** — classify work arrays and the symbol registry (data built then read once,
  or held after last use).

## Step 3 — Docs updates

- `docs/sf/QUICK_REF.md` — seed block updated **v91 → v93** (archive md5
  `84d295ae04e20c4b722ed219bd9a74f1`, fixed point `44b8e7fff5a115743ab5c62adb849555`, `gen/` 45 `.c`
  + 46 `.h`); appended the 2026-10-06 (v92) and structural live-set (v93) rotations and the new
  `-s0` self-compile figures (pool ≈11,965 K, peak RSS median ≈16.0 MB, down from 14,924 K/≈17.4 MB).
  No unrelated section rewritten.
- `sf/docs/tech_docs/00_shared_infra.md` §2 (`string_interner.zig`) — rewritten to the current code:
  `InternEntry` lost its `hash` column (12 B); `StringInterner` holds width-dispatched
  `buckets_narrow_items: [*]u16` / `buckets_wide_items: [*]u32` + `buckets_is_wide`; added
  `internerBucketsAllocNarrow/Wide`, `internerBucketGet/Set/Zero`, `stringInternerMakeBucketsWide`;
  removed the deleted `ensureCapacityBuckets`/`appendBucket`; updated `stringInternerInit`,
  `stringInternerIntern` (no stored-hash fast reject; one-time wide migration at >65,535) and
  `stringInternerGrowBuckets` (rehash recomputes `fnv1a`); data-flow block updated. `[updated:
  2026-10-07]` on the section.
- `sf/docs/tech_docs/03_type_resolution.md` — Summary Table `Type` fields (11→9) and the `Type`
  struct row updated to the 16-B layout (dropped write-only `is_signed`, `c_name_id` now the
  registry-private `c_name_map` side memo, `name_id`/`payload_idx` u16, `alignment`/`module_id` u8,
  arb width `iw`); `registerPrimitive` note (`iw` from kind) and the data-structures block updated.
  `[updated: 2026-10-07]` on the header.
- `sf/docs/tech_docs/INDEX.md` Table A `Type` row — 32-byte descriptor → 16-byte layout.
- `sf/docs/tech_docs/04_comptime_eval.md` — `ComptimeFoldTable` storage updated to the 16-B
  `FoldVal` dense array + rare index-addressed `wide_ints[*]ComptimeInt` side pool and the
  `comptimeFoldTableInitSized` soft pre-size; `comptimeFoldTableGrow`/`GrowWide` row; "exact fold
  table" narrative updated. `[updated: 2026-10-07]` on the header.

## Step 4 — Deferred verification of the two Task-4 edited test binaries

`sf/scripts/build_test.sh` is the zig0-based harness (`sf/build/zig0`). zig0 is retired and no
longer compiles current `sf/src`: the run ends **`=== [test] Results: 0 passed, 9 failed ===`**
(first failure: `sf/src/ast.zig:569 unable to infer type of variable 'byte_off'`) — the
pre-existing `build_test 0/9` state, unrelated to this plan.

The two Task-4-edited test binaries were then built directly with the current seed compiler
(`/tmp/struct_seed7/zig1_5_clean`, `-ffast -o <dir>`). Both **fail to dump** on a stale API, not on
the narrowed `Type` columns: `sf/src/tests/test_semantic_bin.zig` (60 `error[`) and
`sf/src/tests/test_sym_reg_bin.zig` (2 `error[`) call `semanticAnalyzerInit` with **8** arguments
while `sf/src/semantic_analyzer.zig:168` now declares **17** (`error[3061]: expected 17
argument(s), found 8` + a resulting `error[3000]`). This is pre-existing test-source drift, not a
Task-4 regression; no narrowing-`@intCast` site was flagged. **Conclusion: the two edited test
binaries were NOT runtime-verified** — recorded honestly. No unrequested production fix was added.

## Step 5 — Seed rotation v92 → v93

```
bash scripts/seed/archive_seed.sh /tmp/struct_seed7/zig1_5_clean /tmp/struct_seed7/gen \
    release/seed/zig1-seed.tgz --update-changelog
```

- `<binary>` = `/tmp/struct_seed7/zig1_5_clean` (md5 `44b8e7fff5a115743ab5c62adb849555`);
  `<gen_dir>` = its build output dir `/tmp/struct_seed7/gen` (contains the emitted support; the
  script excludes `zig_runtime.c`/`zig_pal.c`/`c_exit.c` + `zig_compat.h`/`zig_runtime.h`/
  `net_prelude.h` from `gen/` and stages them into `runtime/`).
- Archive C gcc-only rebuild reproduced `44b8e7fff5a115743ab5c62adb849555`.
- **Archive md5 changed:** `3cacdd44df75c0ce96abfd51af93f928` (v92) →
  **`84d295ae04e20c4b722ed219bd9a74f1`** (v93).
- `release/seed/CHANGELOG.md` prepended `## 2026-10-07 — seed v93 (HEAD d69f10e7)` with the table
  (binary/fixed point `44b8e7ff…`, `gen/` 45 `.c` + 46 `.h` / 9,803,909 bytes, archive md5
  `84d295ae…`). Pre-existing v92 and older entries retained.

## Step 6 — Scope / commit

- Docs + seed + report + ledger only; no `sf/src` change. Commit
  `docs: structural live-set plan — closeout + seed v93`; branch `zig1_improvements`, **no push**.
- Pre-existing untracked root strays (`anytype_pos.z98`, `fi.err`, `for_closed.z98`,
  `for_open.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) left untouched.
- `/tmp` fixtures and the `t7_*` scratch outputs are not committed.

## Concerns

1. **Re-verification margin.** Final RSS median 16,152 K is ~232 K under the 16,384 K target —
   thin as in Task 6. All five fresh samples cleared the line (max 16,276 K), but the stop-gate
   remains host-load-sensitive.
2. **Offsetting test binaries remain unverified.** `build_test.sh` (0/9, zig0 retired) and a
   direct seed-compiler build both fail on pre-existing `semanticAnalyzerInit` arity drift in the
   test sources; the narrowed `Type` casts are therefore compile-checked only through the
   production battery, not those tests.
3. **Deferred structures** (AST window/value-pool representation, hash-map single interleaved
   array, one-use retention: classify work arrays + symbol registry) remain unimplemented — held
   for the next plan per the spec's non-goals.
4. **Pool drop not independently isolated** (carried from Task 6): the −2,109 K pool fall across
   the comptime fix exceeds the isolated fold carve; output equivalence, not a carve model, is the
   evidence.

---

## Final-review fix wave (2026-10-07)

Whole-branch review `bb46dee4..b8cd33da` returned **no Critical**. The operator ruled on the
follow-ups: **(1)** add the missing narrowed-column overflow guard (Important I1/I2); **(2)** apply
both doc corrections (M1, M5). This wave did exactly that; no unrelated change, no rewiring, no
push; branch `zig1_improvements`.

### I1/I2 — guard the narrowed `Type` casts (`sf/src/type_registry.zig` + call sites)

Root cause (review): the `Type` u16/u8 narrowing has an inconsistent overflow policy —
`name_id`/`module_id` writes route through `typeNarrowU16`/`typeNarrowU8` (clean
`error: type_registry <field> exceeds <limit> (value <v>)` + `pal.exit`), but `payload_idx`
(`@intCast(u16, …)`) and computed `alignment` (`@intCast(u8, …)`) did not, so a pathological
input would silently truncate.

- `typeNarrowU16`/`typeNarrowU8` were made `pub` (`type_registry.zig:197,202`) so external
  writers use the **same** helper — failure mode unchanged.
- **Every** remaining runtime-valued write to the two narrowed columns now routes through the
  guard, not just the external sites the review enumerated (a partial fix would have left the same
  inconsistency inside `type_registry.zig`):
  - `payload_idx`→u16: `symbol_registrator.zig:127,156,184,195,224,240`;
    `type_resolver.zig:1602,1638,1681,1691`; and internally
    `type_registry.zig:531,553,578,609,639,680,698,764,790` (`self.<kind>_len - 1`).
  - computed `alignment`→u8: `type_resolver.zig:298,299,306,324,325,352,359,369,375,392,393,581`;
    and internally `type_registry.zig:607,637,678,928`.
  - Left as raw `@intCast` **only** the compile-time-literal stores (`payload_idx = 0`;
    `alignment = 0/1/4/8`), which cannot truncate (the review's phrase was "computed alignment").
- No guard site was ambiguous; every listed line was verified to be an actual narrowed WRITE before
  editing (the caveat's "reads / already-cast" cases were checked individually).

### M1 — `FoldVal` size doc correction (no code change)

`FoldVal`'s true target layout is the emitted `gcc -m32` C struct **12 B, align 4** (`u64` is 8 B
align 4 on i386). The compiler's own `@sizeOf`/`@alignOf` use an 8-byte `u64` alignment model, so
the fold-table array is allocated at a **16-byte stride**. Corrected the comments in
`sf/src/comptime_eval.zig:46-70` and the three stale spots in
`sf/docs/tech_docs/04_comptime_eval.md` (header note, `ComptimeFoldTable` table row incl. the
"`FoldVal` 8-byte aligned" cell, and the "Exact fold table" paragraph). No code change.

### M5 — CHANGELOG blank line

Restored the missing blank line between the v93 entry and the `## 2026-10-06 — seed v92` heading in
`release/seed/CHANGELOG.md`.

### Re-verification battery (new binary)

Built from the committed v93 seed against current `sf/src` (no `FIXED_POINT_MD5` pin):

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/fw_seed
[seed] two-hop closure OK: hop1 == hop2 == 639902d5146233091f6b2f98508ce3eb
```

| gate | observed | pinned / expected | verdict |
|---|---|---|---|
| seed closure | `hop1 == hop2 == 639902d5146233091f6b2f98508ce3eb` | — | **PASS** |
| dump-MD5 (`-fsafe` ×4 + `-ffast` ×4) | 8 hashes | 8 pins | **8/8 PASS** (delta 0) |
| corpus `scripts/corpus/classify` | `1097 = 923 OK / 58 GREEN / 116 FAIL` | same | **0 ICE / 0 CRASH; exact** |
| `verify_stdlib.sh` | `266 PASS / 0 FAIL over 266 dirs` | 266/0 | **STDLIB GATE OK** |
| examples matrix | `MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0` | 24/24 | **PASS** |
| goldens gol/lisp/json/mud | `fcbf7e7c…` / `b3d9f897…` / `8bda3d5a…` / srv `66c8f0ab…` cli `93147d0f…` | same | **all pinned** |
| semantic markers (in-session) | base 48856 / new 48856 filtered, `diff` rc 0 | byte-identical | **diff 0** |
| peak RSS (`/usr/bin/time -v`, `-s0`, median of 5) | 16036/16028/15992/16180/16020 K | ≤16,384 K | **median 16,028 K** |

- Markers compared in-session between the committed v93 seed binary
  (`/tmp/fw_seed/_unpack/zig1-seed/zig1`, md5 `44b8e7ff…`) and the new binary (`639902d5…`), the
  identical input `sf/src/main.zig`, with `arena .*: grew` + `track-memory:` filtered. Residual 0.
- `track-memory` at HEAD: `perm=761K mod=1023K scr=1020K pool=11965K type_db=249K total=2804K`
  (pool unchanged — the guard is code-size only).

### Seed re-rotation (v93 re-baselined to the new fixed point)

The guard change moved the fixed point, so the v93 archive no longer matched HEAD. Re-ran the
rotation (same plan closeout) with `scripts/seed/archive_seed.sh <new-binary> /tmp/fw_seed/gen
release/seed/zig1-seed.tgz`. **Per the operator's "amending the v93 entry", the entry was edited
in place (not a new v94)**: `release/seed/CHANGELOG.md`'s v93 heading/fields now record HEAD
`b8cd33da`, seed binary + fixed point `639902d5146233091f6b2f98508ce3eb`, self-emission C
45 `.c` + 46 `.h` (9,815,724 bytes) and **archive md5
`e1955908f3aa58992592f9c021c36d42`** (was `84d295ae…` / `44b8e7ff…`). A provenance sentence
records the `44b8e7ff…` → `639902d5…` re-baseline. `docs/sf/QUICK_REF.md`'s seed block was
updated to the new archive md5 + fixed point (pool/RSS figures unchanged). The archive's
self-contained `gcc` rebuild reproduced `639902d5…`.

### Concerns

1. **v93 amended rather than v94.** The literal archive command carries `--update-changelog`, which
   would auto-increment to v94; the operator's explicit "amending the v93 entry (same plan
   closeout)" was followed instead (script run without the flag, v93 fields edited in place).
2. **Fix-wave RSS margin unchanged** (~356 K under the 16,384 K target; median 16,028 K vs Task 7's
   16,152 K) — host-load-sensitive as before.
3. **Literal-literal `@intCast` stores remain unguarded by design** (`payload_idx = 0`,
   `alignment = 0/1/4/8`): compile-time constants cannot exceed the column ceiling, so no
   truncation is possible.
