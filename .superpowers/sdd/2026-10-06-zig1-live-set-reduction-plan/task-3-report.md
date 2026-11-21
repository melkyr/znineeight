# Task 3 — Savings roll-up (READ-ONLY) — SPIKE TERMINAL report

Plan: `docs/superpowers/plans/2026-10-06-zig1-live-set-reduction-plan.md` (Task 3)
Spec: `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md` (§Metric, §Workstream 1/2, §Evidence, §Non-goals)
Consumes: `task-0-report.md`; `task-1-report.md` + `allocation-census.md`; `task-2-report.md` + `workaround-census.md`.
Branch `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no seed rotation**, and
**no dump-MD5 re-baseline**. It re-ran the frozen seed's `-s0` self-compile for a fresh RSS baseline
(throwaway `/tmp` outputs, cleaned) and synthesizes the prior censuses. **No fixes. No imposed
recommendation. No fixed target.** The operator rules which levers to fund.

Binding metric = peak **RSS** (`/usr/bin/time -v` "Maximum resident set size"), median of ≥3
interleaved self-compile runs. `pool`/`total`/per-arena carve are context only. The scoring rule
across this roll-up is the **L3 lesson**: *carve ≠ touched RSS* — only resident/touched pages raise
RSS, so each lever is scored by **expected touched-RSS drop**, never by carve or cumulative churn.

---

## Baseline re-measurement (this session) — confirms Task 0, does not anchor 17,424K

Seed binary `/tmp/liveset_seed/zig1_5_clean`, md5 `2293f756a8250351740cf6acde194d17` (Task 0
`hop1 == hop2` fixed point). Command (CWD `/workspace/znineeight`, RELATIVE src, `-o` dir
pre-created):

```
/usr/bin/time -v /tmp/liveset_seed/zig1_5_clean -s0 --markers --track-memory -o <fresh> sf/src/main.zig
```

| sample | Maximum RSS (kbytes) |
|---|---:|
| 1 | 17,272 |
| 2 | 17,396 |
| 3 | 17,176 |
| **median** | **17,272** |

- Fresh median **17,272K (≈16.9 MiB)**, range 17,176–17,396K. Task 0's median was 17,424K
  (range 17,296–17,564K) → the shared baseline is **≈17.2–17.6 MB, host-noisy**; the exact
  17,424K is **not** anchored. Every fix gate must re-measure median≥3.
- `track-memory` (byte-identical to Task 0): `perm=982K mod=1020K scr=965K pool=14924K
  type_db=346K total=2967K`.
- Per-arena carve (Σ `arena <name>: grew` `new`, 34 events) — byte-identical to Task 0:
  module 5,382,144 / diag_read 4,655,313 / perm 2,558,152 / import_scratch 1,385,155 /
  type_db 1,032,192 / scratch 223,519 / source 0 (Σ 15,236,475).
- Output: 97 files (48 `.c` + 48 `.h` + `build_target.sh`). Baseline equivalence battery (corpus
  1097 = 923/58/116, stdlib 266/0, examples 24/24, goldens gol/lisp/json/mud exact, dump-MD5 8/8)
  is carried from `task-0-report.md` §Step 4 — the tree is unchanged, so it is not re-run here.

---

## Step 1 — Ranked savings table (Tasks 1+2 merged, ordered by expected touched-RSS drop)

Estimates start from the Task 1 shortlist numbers (**cite, not re-derived**), then are **corrected
for the HEAD arena lifecycle** (see Step 2 §D / C2). `cumulative` is Task 1's measured per-function
`sandAlloc` traffic at `-s0` (Task 1 Table 1). **Correction (C2):** the Task 1 premise that `module`
is a never-reset arena is **false at HEAD** — F-FREE (`50b14043`, an ancestor of the Task 0 baseline
`1bb72f62`) calls `sandReset(&ctx.alloc.module)` at the lowering→emission boundary
(`sf/src/main.zig:400-401`); `sandReset` (`sf/src/allocator.zig:78-97`) rewinds the module bump to its
first segment and pushes the rest onto the global `seg_free_head` for best-fit reuse
(`:86-93`) while **keeping `peak`** (`:94`). The module bump peak is `mod=1020K` (`--track-memory`,
both sessions) versus Task 1's cumulative module traffic `5,418.7K` and carve `5,382,144 B` — these
are **not** equal. `perm` and `type_db` are the only closure arenas with no reset. `abandoned-upper`
≈ cumulative/2 is retained only as a **churn** bound, not a residency/peak bound. `touched-RSS` is
re-derived per arena lifecycle below.

**Common gate for every allocation lever** (spec §Evidence, binding): corpus classify diff-empty
(923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH) + runtime goldens gol/lisp/json/mud +
`verify_stdlib` 266/0 + examples 24/24 + dump-MD5 8/8 (stdout-stream; **delta recorded**) +
semantic markers byte-identical IN-SESSION + per-arena carve Σ + **RSS median≥3**. Also per the
plan: seed rebuilt per model, two-hop closure `hop1 == hop2`.

**Effort legend:** Low = single-array in-place/exact-fit first attempt (the
`sandTryReallocInPlace` pattern already used at 21 closure sites, `allocator.zig:219`) or a
one-line init-cap swap; Med = multi-site / deferred-init re-order / AST spill-window semantics;
High = emission-bug dependency, feature gating, or thousands-of-sites churn.

| # | Lever / mechanism | Files / sites (Task 1–2 census) | Measured `cumulative` | Expected touched-RSS | Risk | Effort | Gate (on top of common) |
|---:|---|---|---:|---:|---|---|---|
| 1 | **Hash-map grow-chain.** *In-place variant CLOSED (F-HASHMAP); F-TABLE already disk-backs `resolved_types`; `coercion` already in-place; F-FREE resets `module`.* Surviving residual = deferred-init **pre-size only where occupancy is dense** — S-RES-I showed most node_idx maps are SPARSE-WINS, so a blanket `hint=nodes.len` is disconfirmed. | `sf/src/util/hash.zig:66-74` (`u32ToU32MapGrow`), `:174-182` (`u64ToU32MapGrow`); module maps `main.zig:299-315` (`enum_value_table`, `tuple_index_table`, `call_arg_types`, `call_param_map`, `comptime_folds`, …u64 async maps); `error_code_registry` now **emission** `main.zig:301`; `resolved_type_table.zig:20-31` now F-TABLE disk-backed; `coercion.zig:57` already `sandTryReallocInPlace`; 849 grow calls (Task 1 shortlist row 1, `allocation-census.md:462-464`) | full 3,221,096 B / resident 3,062,480 B (Task 1, **pre-correction**) | ~0.1–0.25M **(module-peak-bounded; occupancy-gated; needs re-measure)** | Med | Med | corpus+goldens+stdlib+examples+dump-MD5 delta+RSS median≥3; byte-identity (exclude emitted-order `error_code_registry`) |
| 2 | **`comptimeFoldTableGrow` in-place/exact-fit.** Single `ComptimeVal[]` (48 B); add the `sandTryReallocInPlace` first attempt (no in-place today). W4 `comptime` is still-blocked so the hand-rolled folder stays; pure allocator strategy. | `sf/src/comptime_eval.zig:70`; 11 doublings; `module` (`main.zig:304`) | 1,535.3K module | ~0.2–0.45M **(bounded by `mod=1020K`; needs re-measure)** | Low–Med | Low | common (single-array tail realloc valid) |
| 3 | **AST head-slot growth in-place/exact-fit.** Grow-chain abandon in `module` — **not** the closed node-layout (I-COMPACT) or token (M5) lever. `module` is reset at `main.zig:401`. | `sf/src/ast.zig:739` (`astSlotEnsureNodeCap`), `:755` (`astSlotEnsurePayloadCap`); 14+14 calls; AST arena `module` (`main.zig:203`) | 1,006.3K module (862.5K + 143.8K) | ~0.15–0.3M **(bounded by `mod=1020K`; needs re-measure)** | Med (AST spill-window semantics) | Med | common |
| 4 | **Interner bucket over-provision.** F-4 set the current sizing (`interner_bc = source.len + source.len/4`, `main.zig:188-190`) → 125,798 buckets × 4 B = 503,192 B, **all zeroed (touched)**; actual distinct strings = 34,020, load-factor 0.5 needs ~68,040 → **excess ≈57,758 buckets ≈231K touched**. Tighten the init hint. `perm` has no reset. | `sf/src/main.zig:188-190` → `sf/src/string_interner.zig:64,82-89` (Task 1 §2e / shortlist row 5) | provisioned buckets 503,192 B touched | ~0.2M | Low | Low | common |
| 5 | **Type-registry grow in-place/exact-fit.** Dense `Type[]`; geometric doubling; `type_db` has no reset. | `sf/src/type_registry.zig:160` (`arrayGrow`), `:179` (`typeRegistryEnsureCapacity`); 77+8 calls | 466.6K type_db | ~0.1–0.2M | Med | Low | common |
| 6 | **Module `u32ArrayListEnsureCapacity` in-place.** Generic single-array helper; add the first attempt. | `sf/src/growable_array.zig:20` (Task 1 shortlist row 6) | module 259.9K; Table 1 lists diag_read **201.6K** but `task-1-report.md:163` says **42.9K** — conflict noted | ~0.05–0.1M **(bounded by `mod=1020K`; needs re-measure)** | Low | Low | common |
| 7 | **W10** `keyword_table` `pub var`+`init()` → `const`. | `sf/src/token.zig:146-194` (Task 2 W10) | — | ~456 B perm (label is `.data`/`.rodata`, not arena-touched); blocked for the array-of-slices shape by an **emission bug** | High (shape) | High | common; **needs emitter fix first** (`l15_const_agg_table` accepted rc 0 but `-o` build rc 1) |
| 8 | **B1** 3 hand-boxed 16 B list headers → inline. | `lexer.zig:26,31-32`; `diagnostics.zig:434,455-456`; `source_manager.zig:76,84-85` (Task 2 Table C) | 3 × 16 B = 48 B gross | ≈0 net (≲4 B pointer each) | Low–Med (aliasing) | Low | common |
| 9 | **W17** 6 spill scalars → `[6]u8`. | `sf/src/spill_store.zig:36-48` (Task 2 W17) | 6 B | 6 B (≈0) | Low–Med | Low | common |
| 10 | **W13** string-literal `[]const u8` workaround (3090 sites). | closure-wide (Task 2 W13) | 0 (stack temps) | 0 | High (diff/fixed-point) | High | common (text-only; moves self-emission fixed point) |
| 11 | **W3 / W5 / W11 / W12** now-removable hygiene. | `extern_c.zig:1-3`; pervasive `@intCast`; `semantic_analyzer.zig:4523,4542` etc. (Task 2) | 0 | 0 | Med/none | Low–Med | common |

**Corrected total.** Rows 1, 2, 3, 6 all allocate from `module`, which F-FREE resets at
`main.zig:401`; their abandoned old buffers are therefore **not** independent live sets — the whole
module group is bounded by the module peak `mod=1020K`, so its combined reclaim is **≤ ~1020K**
(not the sum of the pre-correction bands). Adding the two arenas with no reset — row 4 interner
(`perm`, ~0.2M touched) and row 5 type-registry (`type_db`, ~0.1–0.2M) — gives a **corrected ceiling
of ≈1.0–1.4 MB touched-RSS**, roughly **half** the pre-correction 1.5–2.5 MB. Every module row
still needs a fresh `--track-memory`/RSS remeasure before funding. **Task 2's workaround removals
net ≈0 RSS** (≤456 B optimistic, gated). The two still-blocked load-bearing items — W1 (generics /
hand-written hash maps) and W4 (`comptime`) — **remain** blocked, which is why rows 1–2 stand as
*allocation* levers rather than "removable workarounds" (Task 2 Headline).

**Honesty caveat on the total.** Peak RSS is a **max over the run**, not the sum of per-lever live
sets; the module rows share one arena peak, the post-corrected bands are first-order, and the
baseline is host-noisy (fresh median 17,272K vs Task 0 17,424K). No concrete target is fixed.

---

## Step 2 — NEW-vs-EXHAUSTED judgments (declared non-goal overlaps)

### A. F-HASHMAP — `u32ToU32MapGrow` / `u64ToU32MapGrow` — **split: mechanism partially EXHAUSTED, residual NEW**

- **The mechanism Task 1 names (add `sandTryReallocInPlace` to the map grow) is ALREADY CLOSED.**
  Prior `task-F-HASHMAP-I-report.md` §1 (lines 56-58) + §6 concern 1 (lines 241-248): *"There is no
  in-place grow. In-place tail-grow is **not possible** with the current separate-3-allocation layout
  (only the last-allocated array can be at arena tail; a rehash needs all three at the new capacity
  simultaneously)."* The prior plan amendment repeats it: *"true in-place grow is infeasible with
  the separate-3-array layout."* Disconfirming number: each grow allocates **3 fresh arrays**
  (keys+values+occupied) and rehashes, so there is no single-array tail identity to extend. Task 1
  row 1's stated mechanism **cannot land**.
- **The pre-size-at-init variant was implemented for 7 direct hint'd sites and measured flat.**
  Prior F-HASHMAP-F converted **`keyword_set` / `emitted_type_set` / `fwd_decl_set` /
  `pointer_only_map` / `lfwd` / `lemit` / `cinclude seen`** (7, per `.superpowers/sdd/task-F-HASHMAP-report.md:11-16`
  and `F-HASHMAP-review.md:50-54`) to `...MapInitCap`, gated
  **"perm=121K mod=508K scr=127K pool=3247K type_db=15K total=756K — measurement-identical"**
  (±1K noise on the rogue_mud probe); the intended benefit was only on the large self-compile maps.
- **Sparse-vs-dense (AMENDMENT 15/16):** the S-RES-I census (`docs/superpowers/plans/2026-08-26-zig1-memory-refactor-execution-plan.md:25,27`)
  measured that **only `resolved_types` is DENSE-WINS** (146,701 entries / 76% occupancy; 3,450 KiB →
  941 KiB dense floor — and this is exactly what **F-TABLE has now already landed**). The other
  node_idx tables are **SPARSE-WINS**: `coercion` 135 KiB (2.8%), `enum_value_table` 4.5 KiB (0.15%),
  `comptime_values` 208 KiB (3.2%) — *"dense would ADD ~4.7 MiB."* AMENDMENT 15 had already warned a
  dense array *"can be larger than the sparse hash at low occupancy."* So a blanket
  `hint=nodes.len` pre-size across the remaining maps is **disconfirmed**; the surviving residual is
  per-map and occupancy-gated, i.e. small and unmeasured.
- **Genuinely NEW residual (much smaller than Task 1 row 1):** the prior 6-I report's own §0.5 —
  the **big unhinted module-arena maps** — proposed re-initializing them at the start of
  `phase_TypeResolution` (after import-parse, `nodes.len` final) with `hint=nodes.len`. But at HEAD
  that target set has shrunk: `resolved_types` is now **F-TABLE disk-backed**
  (`resolved_type_table.zig:20-31`), and `coercion` **already** calls `sandTryReallocInPlace`
  (`coercion.zig:57`). Of the survivors, S-RES-I shows `enum_value_table` (4.5 KiB) and
  `comptime_values` (208 KiB) are **sparse-wins** — a `nodes.len` pre-size would over-provision
  them. So the residual is only the remaining **dense-enough** maps, bounded by the module peak
  `mod=1020K`. **Verdict: row 1 survives only as an occupancy-gated deferred-init pre-size; the
  in-place framing is closed and the retained number is not re-derived.**

### B. S-INTERNER — **genuinely NEW angle (different mechanism), but tiny**

- The closed S-INTERNER lever was **write-through / streaming the interner text** — CLOSED
  UNFEASIBLE (AMENDMENT 17). Disconfirming numbers: **pool prize ≈ 0.29 MiB (−1.1%)**; total text
  bulk **288 KiB, not the ~4 MB assumed (14× over)**; emission = **95.9% of Gets (838,798 reads /
  7.36 MB re-read)**; **63% of text interned DURING emission** (concurrent write/read, not
  quiescent); **retained slices exist** across the emitter (transient fault-in buffers break them);
  per-name fseek+fread prohibitive; only mmap-style stable backing would work — unavailable on
  Win9x.
- Task 1 row 4 is a **different mechanism**: shrink the **bucket over-provision at init**
  (touched ≈231K), never touching text residency. It is not covered by the closure → **NEW**, but
  ~0.2M and `perm`-resident.

### C. Exhausted allocator / AST / LIR / spill set — **ALL already closed**

| Lever | Verdict | Disconfirming number |
|---|---|---|
| **M5** (AST side arrays + token value union) | CLOSED unfeasible | `TokenValue` genuinely carries `int_val: u64` + `float_val: f64` → 16 B needs `packed` (rejected) or a value pool; live win only **~60 KB** (scratch transient). Task 2 re-proved the packed `Token` still rejects: `error[3000]` (PACK-AGG is bitfield-only, ≤31-bit leaves, no tagged/wide union field). Live `Token` ≤~80 B (streaming lexer) → **≈0 RSS**; `F-TOKEN` cannot proceed. |
| **I-COMPACT** (16 B `AstNode`) | CLOSED NO-GO | The "16-B" layout is a **byte-identical shuffle** — 28 B/node either way (span/child_2 moved out-of-line, not removed); `pool.peak` effect **0 or negative**. |
| **LIR read** (`lirStreamReadFunction`) | not a lever | **154,990K cumulative churn → carve 0 at `-s0`**; arena `sandReset` per function (`lir_stream.zig:185`) + exact-fit arrays; peak = one function. |
| **scratch** churn | not a lever | 78,424K churn → carve **223,519 B** post-L3; segments reused from `seg_free_head`. |
| **spill** (`spillOpen`) | not a lever | 7 sites, all **disk default at `-s0`** (`fopen`, zero pool bytes); Ram buffers appear only at `-s1+` (`ramEnsure`). |
| **L6 `diag_read` tail bound** | exhausted | Proven **pool-only** — tail carved-but-never-touched; every global growth rule that shrinks `pool` either fragments `type_db` or destroys L3's `source` free-list reuse and **raises** RSS. |
| **AST head-slot growth** (Task 1 row 3) | **NEW mechanism (module-reset corrected)** | It is a **grow-chain abandon in `module`**, not the closed node *layout* (I-COMPACT) or token (M5) lever; Task 1 measured 862.5K module at `-s0`. But `module` is reset at `main.zig:401` (C2) and its peak is `mod=1020K`, so the reclaim is arena-peak-bounded, not cumulative-bounded. Same subsystem, different mechanism. |

### D. Prior allocator workstream — **all landed/exhausted at HEAD** (spec §Non-goals `:124`)

Spec §Non-goals names the *"exhausted allocator/AST/LIR/spill levers (F-1/I-F1, M5, I-COMPACT,
S-INTERNER)"*. The F-series commits are **ancestors of the Task 0 baseline `1bb72f62`** (verified
`git merge-base --is-ancestor`), so they are **already closed**, not new levers:

| Lever | Status + disconfirming evidence / source |
|---|---|
| **F-1 / I-F1** free-list keyed "reset = release" | **closed.** F-1 BLOCKED: off-ladder reuse inflated the doubling base → `pool=` **+732 K regression**; replaced by read-only **I-F1** (re-investigation), closed. The corrected policy later lands as F-FREE. Source: `docs/superpowers/plans/2026-09-01-allocator-crux-measurement-plan.md` AMENDMENT 2/3. Overlaps Task 1's `seg_free_head` reuse assumption. |
| **F-2** `1216fd06` segment-growth cap | **landed.** `max_segment` 2 MiB → **1 MiB** (`sf/src/allocator.zig:118`). Cuts segment headroom; Task 1's "over-sizing / headroom" class is already tuned. |
| **F-3** `e35de6dd` emitter maps off scratch + per-fn scratch reset | **landed.** Moves `error_code_registry` / `global_decls` / mangler / `cinclude` onto `emission` and resets scratch per emitted fn — directly addresses Task 1's 78,424K scratch churn → carve now **223,519 B**. |
| **F-4** `fb6daa56` pre-size high-churn arrays | **landed (narrower than plan).** The landed diff is **interner pre-size only** (`interner_bc = source.len + source.len/4`, `main.zig:188-190`) — so it directly **is** row 4's current sizing. The plan AMENDMENT 2 projected hash maps ~974K / astStore 1,458K / type_db 276K, but those did **not** land in this commit → rows 1/3/5 are **partially-overlapping (intent recorded, change not landed)** and remain open. |
| **F-FREE** `50b14043` free analysis arena at boundary | **landed.** `sandReset(&ctx.alloc.module)` `main.zig:401` + `seg_free_head` splice (`allocator.zig:86-93`). **Invalidates the rows-1–3 "never-reset module" premise** (C2); module peak `mod=1020K`. |
| **F-TABLE** `40d72e04` disk-back `resolved_types` | **landed.** `resolved_type_table.zig:20-31` is now a dense 5 B/node disk spill + sparse `src_map`; removes `resolved_type_table.zig:29-30` maps from row 1 (AMENDMENT 16: 3,450 KiB → 941 KiB, realized). |
| **I-SPILL** conditional-spill follow-up | **deferred** (gated after the F-series), not a lever here. |
| **M5 / I-COMPACT / S-INTERNER** | see §C and §B — all closed; not re-opened by this roll-up. |

---

## Step 3 — Rejected and deferred levers (with the disconfirming number)

### Rejected (measured, not levers)

| Lever | Disconfirming evidence |
|---|---|
| `diag_read` text + line index (`source_manager.zig:161/163/174`) | 2,711.1K text + 201.6K index; **L3 per-module reset already in `sf/src`**; `u32→u16` index ≤101K live and **≈0 pool** (prior L1). |
| `lir_read` 154,990K churn | **carve 0** at `-s0` (`sandReset` per fn). |
| `scratch` 78,424K churn | **carve 223,519 B** post-L3. |
| `import_scratch` / `source` whole-file reads (`module_registry.zig:384`) | 2,686K / 2,790K churn, exact-fit, reset per import/module; prior **L5 disconfirmed** (module reuses 1,276,415 B) → ≈0 pool. |
| Interner **entries** tail | Pre-size **62,899 × 16 B = 1,006,384 B**, only 34,020 written → **462,064 B ≈ 451 KiB carved-but-NOT-touched** (no RSS). **Authoritative**; this corrects the stale `62,861 × 16 B / ~461K` at `task-1-report.md:85`. |
| Packed `Token` (F-TOKEN / W14) | Packed struct with tagged-union field / `u32` / >31-bit union member → `error[3000]`; **still-blocked**; ≈0 RSS anyway. |
| W10 `keyword_table` → `const` | ~456 B `.data`/`.rodata` (not arena-touched), blocked for the array-of-slices shape by an emission bug (`variable or field '_0' declared void`); "touched-RSS" label was loose (Task 2 minor). |
| W13 (3090 sites) / W3 / W5 / W11 / W12 | 0 RSS; text-only changes that move the self-emission fixed point. |
| W1 `anytype`/`@Type`; W2 `@cImport`; W4 `comptime`; W6 pointer capture; W7 `switch else` (deliberate rule); W8 method syntax | **still-blocked** (`error[16]`/`error[2000]`/`error[3000]`/`error[3068]`). |
| Boxing B1 (3 hand-boxed headers) | 3 × 16 B = **48 B gross, ≈0 net** after pointer/pad; most `*ArrayList` are embedded, and 252 `*T` are shared-context params (not removable). |
| Inline `[N]` buffers | 8 × `[512]u8` = **4,096 B on stack**, touched once; `buf:[4096]u8`, `la:[3]Token`, etc. — negligible. |
| Alignment pad / list headers | ≤3–7 B pad per alloc; prior measured **63 B total** for the 43 `diag_read` file triples; list headers 16 B × tens — negligible. |

### Deferred (out of scope until/unless the operator rules)

- **General boxing / array-vs-scalar layout sweep** — spec §Scope Out; Task 2 Table C confirms it
  holds no RSS lever (252 `*T`, dominated by shared-context pointers).
- **86Box/PCem Win98 idle-floor measurement** and the **concrete RSS target** — both deferred;
  the target is fixed only *after* the operator's ruling on this table (spec §Metric).
- **`[N]Packed` control probe** (Task 2 minor) and **W9 `std.debug.print` tuple probe** (std API,
  not in the 45-module closure).
- **W10 array-of-slices `const` path** — pending an emitter fix.
- **All prospective fixes** (`F-ALLOC-*`, `F-TOKEN`, `F-WORKAROUND-*`, `F-BOX-*`) — not this spike;
  authored as a separate fix plan **after** the ruling, one task per confirmed lever.

---

## Operator decision input (no recommendation, no target)

The spike ranks the honest savings; the operator funds what they choose. In descending expected
touched-RSS (post-C2 correction):

1. `comptimeFoldTableGrow` in-place — ~0.2–0.45M *(module-bounded by `mod=1020K`)*
2. Interner bucket over-provision — ~0.2M *(`perm`, no reset; touched = zeroed buckets)*
3. AST head-slot growth in-place — ~0.15–0.3M *(module-bounded)*
4. Hash-map deferred-init pre-size (occupancy-gated residual; in-place closed; `resolved_types` now
   F-TABLE) — ~0.1–0.25M *(module-bounded)*
5. Type-registry grow in-place — ~0.1–0.2M *(`type_db`, no reset)*
6. Module `u32ArrayListEnsureCapacity` in-place — ~0.05–0.1M *(module-bounded)*

**Corrected ceiling ≈1.0–1.4 MB** touched-RSS for rows 1–6 grouped by arena (module group ≤ ~1020K;
plus `perm` ~0.2M and `type_db` ~0.1–0.2M); Task 2 workarounds **≈0 RSS**. Realized peak drop is
likely below the sum (peak = max over the run; the module rows share one arena peak), and the
baseline is host-noisy (~17.2–17.6 MB). **STOP — no fixes.**

---

## Concerns

1. **Row 1 is the least certain and is now the smallest.** Task 1's ~0.5–0.9M was derived for the
   in-place-at-tail mechanism, which prior F-HASHMAP ruled **infeasible** for the 3-array map
   layout; `resolved_types` is now disk-backed (F-TABLE) and `coercion` already in-place, and the
   surviving maps are mostly sparse (AMENDMENT 16). Its corrected band (~0.1–0.25M) is a placeholder
   pending per-map occupancy + a fresh remeasure.
2. **Abandoned ≈ cumulative/2 is a first-order upper bound** (pure geometric doubling; assumes every
   old buffer is truly dead). Some grows are pre-sized via `…InitCap` and some sites already use
   `sandTryReallocInPlace`, so real reclaim is lower.
3. **Counts are per enclosing function, not per `sandAlloc` line** — the frozen seed binary carries
   no DWARF line info; multi-site functions (e.g. `emitHoistedDecls`, 23 sites) share their
   aggregate.
4. **Cumulative churn ≠ footprint — and `module` is NOT never-reset.** Only `perm` and `type_db`
   lack a reset; `module` is reset at `main.zig:401` (F-FREE) and its peak is `mod=1020K`, so the
   module rows are arena-peak-bounded, not cumulative-bounded (C2).
5. **Data-dependent** — Task 1's probe numbers are for HEAD `1bb72f62`; small `sf/src` changes shift
   them by tens of KB. Every fix must re-measure median≥3.
6. **Stale interner citation absorbed** — `task-1-report.md:85` says `62,861 × 16 B / ~461K`; the
   authoritative value from `main.zig:188-190` + `string_interner.zig:91-93` is **62,899 × 16 B =
   1,006,384 B**, entries tail **462,064 B ≈ 451 KiB** carved-not-touched. This roll-up uses the
   corrected value.
7. **Fresh baseline confirms host noise** — this session's median 17,272K vs Task 0's 17,424K; pool
   and carve are byte-stable. Do not anchor either exact RSS.
8. **`tests/lexer_tests.zig` is compiled into the production binary** (`lexer.zig:16`) — code-size,
   not runtime-memory, observation.
9. **Unexplained `module` carve-vs-peak gap.** Task 0's carve table says module Σ `new` =
   5,382,144 B and Task 1's probe 5,418.7K, but `--track-memory mod=1020K` (`main.zig:409-410`).
   With a single reset (`main.zig:401`) these cannot all be simultaneously "cumulative = carve =
   touched peak". The module rows are therefore **provisional** and must be re-measured before
   funding.
10. **Row 6 `diag_read` conflict unresolved.** `allocation-census.md:85` lists
    `u32ArrayListEnsureCapacity` diag_read **201.6K**; `task-1-report.md:163` says **42.9K**. Noted
    in row 6; neither is load-bearing (the module 259.9K portion is what row 6 targets).
11. **Cleanup** — the fresh `-s0` runs wrote only under `/tmp/t3_run{1,2,3}` (now removed); no
    `sf/src` edit, no `.zig1_*.tmp` created. Pre-existing untracked root strays (`anytype_pos.z98`,
    `fi.err`, `for_*.z98`, `name_u65.z98`, `num_member.z98`, `q.err`, `sh.err`, `sz_u0.z98`) were
    left untouched. Only this report is committed.

---

## Commands used (evidence)

```
# fresh baseline (re-measure, do not anchor 17,424K)
for i in 1 2 3; do rm -rf /tmp/t3_run$i && mkdir -p /tmp/t3_run$i/out
  /usr/bin/time -v -o /tmp/t3_run$i/time.txt /tmp/liveset_seed/zig1_5_clean \
      -s0 --markers --track-memory -o /tmp/t3_run$i/out sf/src/main.zig
done   # RSS 17272 / 17396 / 17176 -> median 17,272 K
awk '/arena .*: grew/ {name=$2; sub(/:$/,"",name); sum[name]+=$6} END{for(n in sum) print n, sum[n]}' \
    /tmp/t3_run1/markers.txt    # byte-identical to Task 0 carve
md5sum /tmp/liveset_seed/zig1_5_clean   # 2293f756a8250351740cf6acde194d17
rm -rf /tmp/t3_run1 /tmp/t3_run2 /tmp/t3_run3
```

---

## Fix round 1

Independent review returned **Spec ❌ / Needs fixes**. All findings addressed below; `sf/src`
remains unmodified (READ-ONLY). Evidence commands are `git`/`grep`/`sed` against the current
worktree.

**C1 — New-vs-exhausted omitted F-1/I-F1 and the prior allocator workstream (Critical).** Resolved.
Added **Step 2 §D** covering **F-1/I-F1, F-2 `1216fd06`, F-3 `e35de6dd`, F-4 `fb6daa56`,
F-FREE `50b14043`, F-TABLE `40d72e04`** (plus I-SPILL deferred), each with status and disconfirming
number, citing `docs/superpowers/plans/2026-09-01-allocator-crux-measurement-plan.md` AMENDMENT 2
for F-1's `pool=` **+732 K regression** and AMENDMENT 15/16 for dense-vs-sparse. Verified with
`git merge-base --is-ancestor <F-*> 1bb72f62` → **all six are ancestors of the Task 0 baseline**,
so they are already closed. Row adjustments: F-TABLE removes `resolved_type_table.zig:29-30` from
row 1; F-3 covers the scratch-churn class; F-4 **is** row 4's interner sizing; F-2 already tuned
segment headroom. Note: the landed F-4 diff (`git show fb6daa56 --stat` = `main.zig | 4 +++-`)
changed **only** `interner_bc`, not the AMENDMENT-2-projected hash/astStore/type_db arrays —
recorded as partially-overlapping (intent on record, change not landed).

**C2 — `module` "never-reset arena" premise false at HEAD (Critical).** Resolved. Verified
`sf/src/main.zig:400-401` (`resolvedTypeTableClose` + `sandReset(&ctx.alloc.module) // free the dead
analysis arena at lowering→emission boundary`) and `sf/src/allocator.zig:78-97` (rewind + splice the
rest of the chain onto the global `seg_free_head`; `peak` intentionally kept at `:94`). Corrected
the Step 1 intro, rows 1/2/3/6, the total, the operator list, and Step 2 §C/§D: only `perm` and
`type_db` have no reset; the module group is bounded by `mod=1020K` (not Task 1 cumulative
`5,418.7K`). Added concern 9 on the unexplained module carve-vs-peak gap (5,382,144 B carve vs
1,020 K peak).

**I1 — Row 1 stale/superseded (Important).** Resolved. Re-verified against current source: (a)
`resolved_type_table.zig:20-31` is the **F-TABLE disk-backed dense spill + sparse `src_map`** — no
`index`/`source_index` maps; (b) `coercion.zig:57` **already** calls `sandTryReallocInPlace`;
(c) the maps are at `main.zig:299-315`, and `error_code_registry` moved to
`compiler_alloc.emission` (`main.zig:301`). Reconciled sparse-vs-dense per **AMENDMENT 15/16**: only
`resolved_types` is DENSE-WINS (already landed by F-TABLE); `coercion` 135 KiB, `enum_value_table`
4.5 KiB, `comptime_values` 208 KiB are SPARSE-WINS, and "dense would ADD ~4.7 MiB". Row 1's `hint =
nodes.len` across six maps is therefore **disconfirmed**; re-derived the surviving residual to
**~0.1–0.25M, occupancy-gated, module-peak-bounded, needs re-measure**.

**Minors.**
- **F-HASHMAP-I citation:** `§1/§7` → **§1 (lines 56-58) + §6 concern 1 (lines 241-248)** (6-I has no
  §7).
- **"6 direct hint'd sites" → 7:** cited `.superpowers/sdd/task-F-HASHMAP-report.md:11-16` and
  `F-HASHMAP-review.md:50-54` (keyword_set, emitted_type_set, fwd_decl_set, pointer_only_map, lfwd,
  lemit, cinclude seen).
- **Row 6 `diag_read` conflict:** now noted in the row (`allocation-census.md:85` 201.6K vs
  `task-1-report.md:163` 42.9K) and concern 10.
- **W10 effort:** `Med` → **`High`** (needs the emitter fix first).

Constraint checks re-run: no `sf/src` path staged; only `task-3-report.md` staged with `git add -f`;
no `sf/src` file modified and no `.zig1_*.tmp` created. Operator requirement intact: **no imposed
recommendation, no fixed target.**
