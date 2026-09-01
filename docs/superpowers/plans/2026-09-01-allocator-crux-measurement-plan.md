# zig1 Allocator Crux Measurement → Gated Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure exactly where `pool.peak` (25,742 K) goes — per-arena chain, live, and the three churn classes (segment headroom, dead array buffers, reset-retained segments) — plus study the C89-emission peak specifically, then present a crux map + redesign options to the operator, whose decision gates the allocator redesign F-tasks (added by amendment).

**Architecture:** Read-only measurement tasks (I-MEAS-1 per-arena chain+live; I-MEAS-2 array-level dead-buffer churn; I-MEAS-3 synthesis+crux map+STOP-present), all measured on the reference zig1 via existing `arena grew` markers plus instrumented `/tmp` builds (the I-4B pattern — never touch `sf/src`). **AMENDMENT 1 (operator-ruled 2026-09-01):** I-MEAS-3's crux map showed the C89-emission phase is the pool peak (17,653,076 → 26,360,112, +8,707,036 B = scratch +4,194,304 + lir_read +2,415,360 + perm +2,097,152) and that emission's live set is tiny (~3.1 MB) — the peak is cumulative chain retention surfacing at the last phase. The operator directed (m1165/m1168/m1170) a focused **I-EMIT task** (added after I-MEAS-3) to break down the emission phase's +8.7 MB by allocation site and determine whether emission-specific waste exists beyond the general levers. The redesign is gated: after I-MEAS-3 + I-EMIT the operator picks a direction and the plan is amended with F-task(s).

**Tech Stack:** Zig (sf/src, read-only), C89 (instrumented emitted C in /tmp), bash, gcc -m32.

## Global Constraints

- **Read-only I-tasks:** NO `sf/src` edits, NO commits, NO `sf/build/out_release/` touches. Measurement via (a) existing `arena grew` markers and (b) instrumented **copies** of the emitted C in `/tmp` (the I-4B pattern: checkpoint loggers into generated `main.c`/`allocator.c`, recompiled into a throwaway binary). Working tree must end identical to start (only pre-existing dirty files).
- **Measurement workload:** reference zig1 self-compiling `sf/src/main.zig`. Use `timeout 120` on all compiler/binary invocations, `timeout 900` on builds. `--output-dir` MUST pre-exist (`mkdir -p` first).
- **Relevant current facts:** `pool=25,742K`, `total=5,755K` (perm 1,661 + mod 2,047 + scr 2,047); six growable arenas `perm`/`module`/`scratch`/`lir_read` (allocator.zig:209-212) + `type_db` + `import_scratch`; `pool` is a monotonic bump never reset; segment growth on-demand doubling capped 2 MiB + exact-fit final (`growableSandGrow` allocator.zig:108-133); `sandTryReallocInPlace` allocator.zig:161-174; `arenaGrew` marker allocator.zig:135-148 emits `arena <name>: grew <old> -> <new>` only on NEW segments; `sandReset` allocator.zig:78-87 rewinds + reuses chain, never frees.
- **MD5 gate baselines** (informational for I-tasks — no emission change so they must not move): gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `4591fef0`.
- **Z98 dialect** for any Zig code read (no anytype/@Type; the instrumented C is C89).
- **Ledger:** append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent memrefactor-session --type <discovery|decision|pattern> --summary "<s>" "<body>"`.
- **Report file:** `.superpowers/sdd/task-ALLOC-report.md` (gitignored; append sections per task). WARNING: `task-1-report.md` is TRACKED — never reuse.
- **Pre-existing dirty files never staged:** `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
- Design doc: `docs/superpowers/specs/2026-09-01-allocator-crux-measurement-design.md`.

**AMENDMENT 2 (operator-ruled 2026-09-01, redesign F-task set — all 4 levers + spill-threshold follow-up):** after the measurement stage (I-MEAS-1/2/3 + I-EMIT, all approved) the operator directed (m1191/m1192) the redesign amendment with **all four levers** so the spill decision can be re-evaluated afterwards: **F-1 segment free-list keyed on "reset = release"** (~8.1 MB, reset-retained chains), **F-2 growth-policy tuning** (~3.5–5.5 MB, segment headroom incl. lir_read near-empty 2 MiB cap segment), **F-3 emitter-level** (move persistent emitter maps off scratch + per-function scratch reset during emission, ~6.4 MB — the one piece the other three do NOT cover; I-EMIT finding: 94.4% of emission scratch churn is `emitHoistedDecls` per-function arrays, main.zig:738/740 + c89_emit.zig:614-627), **F-4 dead-buffer pre-sizing / tail-aware ordering** (~3.2 MB, class b: astStore extra-children/extra-ranges ast.zig:148/180 1,458 K, si_entries 491 K, hash maps ~974 K, type_db 276 K). **Order (AMENDMENT 3, operator-ruled 2026-09-01):** the F-1 free-list attempt was BLOCKED (off-ladder reuse inflated the doubling base, `pool=` +732 K regression; see `## F-1 fix` in the report) and the operator deferred it — **F-1 is replaced by read-only `Task I-F1` (free-list quirk re-investigation, placed after F-4)**. **Execution order: F-2 → F-3 → F-4 → I-F1 → I-SPILL.** **Closing I-SPILL task (follow-up, gated after the 4):** re-measure `pool.peak` after the 4 levers and evaluate making S-LIR / S-AST / S-HASH **conditional** — spill to disk only when `pool.peak` is projected to cross a threshold, so small compiles skip disk I/O entirely. Each F-task carries the full gate battery and a `pool=` before/after measurement.

---

### Task I-MEAS-1: Per-arena chain + live breakdown (read-only)

**Files:**
- (Read) `sf/src/allocator.zig`, `sf/src/main.zig` (`runCompiler` phase list :200-272, arena init :160-220)
- (Create, /tmp only) instrumented build: `/tmp/meas1_gen/` (emitted C), `/tmp/meas1_instr/` (patched C + throwaway binary)

**Interfaces:**
- Consumes: the design doc's allocator facts; existing `arenaGrew` marker (allocator.zig:135-148).
- Produces: the per-arena chain/live/headroom table + peak-phase identification for I-MEAS-3.

- [ ] **Step 1: Build the reference zig1 fresh**

Run (repo root): `timeout 900 bash sf/scripts/build_release.sh`
Expected: gate line `=== [release] Done ===`; then reinstall std lib: `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.

- [ ] **Step 2: Capture the segment-allocation log (existing markers)**

Run: `mkdir -p /tmp/meas1_gen && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --markers --output-dir /tmp/meas1_gen sf/src/main.zig 2>/tmp/meas1_gen/markers.log`
Expected: rc=0; `/tmp/meas1_gen/markers.log` contains `arena <name>: grew <old> -> <new>` lines (M7 keeps `arenaGrew` live).

- [ ] **Step 3: Compute per-arena segment chains from the marker log**

Parse `/tmp/meas1_gen/markers.log`: for each arena name, the chain = Σ of the `<new>` sizes over its `arena ... grew` lines (each fires once per NEW segment; reuse does not fire).
Record: per-arena chain (perm/module/scratch/lir_read/type_db/import_scratch), total chain Σ, and how it compares to `pool.peak` (25,742 K baseline). Report the dominant arena.

- [ ] **Step 4: Build an instrumented /tmp compiler for per-phase live**

Patch COPIES of the emitted C in `/tmp/meas1_instr/` (copy `/tmp/meas1_gen/*.c` + `.h`, then edit the copies — never the originals, never `sf/src`):
- In `allocator.c`: add a `meas_log()` that writes the current `view.pos`, chain Σ (walk `first`→`last` via `.next`), and `pool.peak` for all six arenas; call it at the top of `sandAlloc`/`growableSandGrow`/`sandReset` only if a `MEAS` compile-time global is on (so the instrumented build is the only one that logs).
- In `main.c`: add a checkpoint call at each `runCompiler` phase boundary (import resolution → symbol registration → type resolution → front resolution → comptime eval → semantic analysis → static analyzers → LIR lowering → C89 emission), emitting `PHASE <n>` then `meas_log()`.

Recompile the copies (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include -c *.c`, then link with `<repo>/sf/src/include/{zig_runtime.c,zig_pal.c,c_exit.c}`) into `/tmp/meas1_instr/zig1_meas`.

- [ ] **Step 5: Measure per-phase live and the peak phase**

Run the instrumented compiler self-compiling: `mkdir -p /tmp/meas1_out && timeout 120 /tmp/meas1_instr/zig1_meas --dump-c89 --output-dir /tmp/meas1_out sf/src/main.zig 2>/tmp/meas1_instr/phase.log`
Expected: rc=0; `/tmp/meas1_instr/phase.log` has the per-phase per-arena live/chain table + pool.peak trajectory.
Record: (a) the phase where pool.peak jumps to its max, (b) per-arena live at that phase, (c) per-arena headroom = chain − live at that phase, (d) which arenas' chains are pure reset-retained (live near 0 but chain high, e.g. scratch between resets).

- [ ] **Step 6: Cross-check and report**

Cross-check Step-3 chains vs Step-5 chain Σ (should agree within marker/checkpoint ordering). Append `## I-MEAS-1` to `.superpowers/sdd/task-ALLOC-report.md` with: the per-arena chain/live/headroom table, the peak phase, the dominant-arena answer, and any anomaly. Do NOT append the ledger or run mnemoria (read-only; controller-owned).

### Task I-MEAS-2: Array-level dead-buffer churn (read-only)

**Files:**
- (Read) `sf/src/allocator.zig` (`sandTryReallocInPlace` :161-174, `sandReallocInPlace` :176-178), the ~28 realloc call sites
- (Create, /tmp only) instrumented `allocator.c` in `/tmp/meas2_instr/`

**Interfaces:**
- Consumes: I-MEAS-1's instrumented build mechanics (reuse/refresh the pattern).
- Produces: the churn split — dead array buffers vs segment headroom vs reset-retained — for I-MEAS-3.

- [ ] **Step 1: Identify all in-place-realloc sites**

Grep `sf/src` for `sandReallocInPlace`/`sandTryReallocInPlace` (expect ~28 sites, e.g. `growable_array.zig`, `ast.zig`, `resolved_type_table.zig`, interner/hash maps). For each, note the array element size × capacity semantics (does the caller realloc the whole backing buffer?).

- [ ] **Step 2: Instrument realloc outcomes in /tmp**

In the instrumented copy `allocator.c` (refresh from I-MEAS-1's `/tmp/meas1_gen` if not reused), patch `sandTryReallocInPlace` to accumulate:
- `in_place_bytes` += `old_size` on success,
- `dead_bytes` += `old_size` on failure (the caller's ensureCapacity then does `sandAlloc(new)` + copy + abandons `old_ptr` → `old_size` becomes dead space in its segment),
plus counters of success/failure calls.
Emit a summary at process end (a marker at the final `checkCombinedPeak` or after `phase_C89Emission`).

- [ ] **Step 3: Measure dead-buffer bytes**

Rebuild the instrumented compiler (same gcc recipe as I-MEAS-1 Step 4) and run the self-compile (same as I-MEAS-1 Step 5). Record `dead_bytes` (total dead-buffer churn), `in_place_bytes` (bytes saved by in-place growth), and the success/failure call counts.
Optionally cross-tabulate dead_bytes per calling site by noting the largest offenders (from Step 1's site map + per-site read of the emitted C).

- [ ] **Step 4: Report**

Append `## I-MEAS-2` to `.superpowers/sdd/task-ALLOC-report.md`: the dead-buffer vs headroom vs reset-retained split (headroom from I-MEAS-1 headroom column; reset-retained = reset arenas' live≈0 chains), per-site offenders, and the total churn the three classes account for vs the ~20,000 K gap.

### Task I-MEAS-3: Synthesis + crux map + STOP-present (read-only)

**Files:**
- (Read) I-MEAS-1 + I-MEAS-2 report sections, `sf/src/allocator.zig`

**Interfaces:**
- Consumes: I-MEAS-1 (chain/live/headroom/peak phase), I-MEAS-2 (dead-buffer churn).
- Produces: the crux map + redesign options + recommendation for the operator's gating decision.

- [ ] **Step 1: Build the crux map**

From I-MEAS-1 + I-MEAS-2, produce a table over the six arenas: chain / live / headroom / dead-buffer / reset-retained, plus the total 25,742 K reconciliation. Rank the churn classes and the dominant arenas by bytes.

- [ ] **Step 2: Evaluate redesign candidates**

For each candidate, give: expected pool drop (bytes, from the crux-map numbers), risk, effort, and Z98-expressibility:
- **Segment free-list keyed on "reset = release"** (scratch + any reset arena returns segments to a free-list; `growableSandGrow` allocates from the list before the bump). Prize = the reset-retained + reusable chain bytes.
- **Growth-policy tuning** (factor/cap/exact-fit changes at `growableSandGrow`; e.g. fewer/larger segments). Prize = segment headroom + chain-geometry bytes.
- **Per-arena pools** (split the single bump into per-arena bumps so each resets independently). Prize = enables the reset-reclaim across all arenas; larger change.
- **Compaction / reset-aware bump** (any other mechanism the data suggests).
Also record what each candidate does NOT buy (e.g. a free-list does not reclaim dead array buffers unless combined with per-arena reset).

- [ ] **Step 3: STOP-present the crux map + recommendation**

Present the crux map, the ranked levers with expected pool drops, and a recommendation to the operator. **Do NOT proceed to any F-task.** The operator's decision becomes an amendment adding the redesign F-task(s) to this plan.

- [ ] **Step 4: Report + ledger**

Append `## I-MEAS-3` (crux map + options + recommendation) to `.superpowers/sdd/task-ALLOC-report.md`. Record the STOP-present outcome in the report. Do NOT modify `sf/src`, do NOT commit.

---

### Task I-EMIT: C89-emission allocation-site breakdown (read-only)

**Files:**
- (Read) `sf/src/c89_emit.zig`, `sf/src/lir_stream.zig`, `sf/src/allocator.zig`, the `## I-MEAS-1/2/3` report sections
- (Create, /tmp only) instrumented build under `/tmp/emit_instr/` (patched copies; never `/tmp/meas1_gen`/`/tmp/meas2_instr` originals, never `sf/src`)

**Interfaces:**
- Consumes: I-MEAS-1/2/3 data — emission phase (phase 8→9) grows `pool.peak` 17,653,076 → 26,360,112 = **+8,707,036 B**: scratch +4,194,304 (emitter working set), lir_read +2,415,360 (S-LIR fault-in), perm +2,097,152 (interner); emission's live set at peak is ~3.1 MB.
- Produces: the emission-phase allocation-site breakdown + a verdict (emission-specific waste exists / the general levers already cover it) for the redesign amendment.

- [ ] **Step 1: Verify the reference zig1 is fresh**

`/tmp/fx_subfolder/zig1` from I-MEAS-1 is current (HEAD 2a70487d; no rebuild needed unless a build proves stale — rebuild only then, `timeout 900 bash sf/scripts/build_release.sh` from repo root + reinstall std lib).

- [ ] **Step 2: Instrument the emission phase by allocation site**

Refresh an instrumented build in `/tmp/emit_instr/` (patch copies of the pristine emitted C from `/tmp/meas1_gen`; the I-MEAS-1/I-MEAS-2 pattern — MEAS gating flag, patched `allocator.c`/`main.c`, linked with `include/zig_runtime.c` + `include/zig_pal.c` + the `c_exit` shim, `-fsanitize=address` optional):
- In `allocator.c` `sandAlloc`: add a per-arena byte histogram keyed by **caller return address** (the I-MEAS-2 histogram pattern), plus per-arena byte accumulators; gate accumulation to `phase_C89Emission` only (start at the emission phase entry in `main.c`, stop + dump at its exit).
- In `lir_stream.c` (`lirStreamReadFunction`): record per-function fault-in byte sizes (to confirm lir_read's chain = the largest single function's LIR).

Recompile (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include -c *.c`; link into `/tmp/emit_instr/zig1_emit`).

- [ ] **Step 3: Measure and map sites**

Run: `mkdir -p /tmp/emit_out && timeout 120 /tmp/emit_instr/zig1_emit --dump-c89 --output-dir /tmp/emit_out sf/src/main.zig 2>/tmp/emit_instr/emit.log`
Expected: rc=0. Map the histogram's return addresses to function names using the emitted `c89_emit_*.c` (or `nm`/`addr2line`). Break down the emission phase's +8.7 MB:
- **scratch** (+4,194,304): which emitter functions (e.g. name mangling, per-module emission state, buffered writer, `temp_global_map`, hoisted-decl handling) allocate the bytes; live vs dead within emission.
- **lir_read** (+2,415,360): per-function fault-in sizes; confirm the largest-function bound.
- **perm** (+2,097,152): what is interned during emission (mangled names vs type names vs identifiers); count/size by kind.

- [ ] **Step 4: Verdict + report**

Assess each as genuine working set vs emission-specific churn. Specifically answer: does emission have waste the three general levers (reset=release free-list, growth-policy tuning, dead-buffer) do NOT cover (e.g. emitter scratch churn beyond reset-reuse, an oversized single-function LIR, or avoidable interning)? Append `## I-EMIT` to `.superpowers/sdd/task-ALLOC-report.md` with the site breakdown table + verdict + recommendation for the redesign amendment. Do NOT append ledger or run mnemoria (controller-owned). Do NOT modify `sf/src`, do NOT commit.

---

## After the measurement (gated redesign — AMENDMENT 2 F-tasks)

After the operator picked the redesign direction from the I-MEAS-3 crux map + the I-EMIT emission study, this plan was amended (AMENDMENT 2) with the F-tasks below. **AMENDMENT 3 (operator-ruled 2026-09-01, after the F-1 attempt):** the F-1 free-list attempt (report `.superpowers/sdd/task-ALLOC-report.md` `## F-1 fix`) was **BLOCKED** — the brief's best-fit-and-splice mechanism REGRESSED `pool=` 25,742 K → 26,474 K (+732 K): reusing off-ladder free segments (import_scratch 455,156 B, parser odd sizes) as the doubling base inflated subsequent carves (module +642 K, scratch +468 K) beyond the real savings (type_db −262 K, lir_read −99 K, parser −25 K). Tree reverted clean, no commit, 4 MD5 gates untouched. The operator deferred the free-list: **Task F-1 is replaced by a read-only investigation `Task I-F1`** (placed after F-4) that re-investigates the quirk and checks for a missed subtlety before any re-attempt. **Execution order is now F-2 → F-3 → F-4 → I-F1 → I-SPILL.** Each F-task carries the full gate battery (4 MD5 keep-or-re-baseline with golden 9/9 runtime evidence, self-compile 41 `.c` / 0 err / 0 PANIC, reference 0-warning, Z98 dialect, `edit`/`fastedit` only) and a `pool=` before/after measurement.

---

### Task I-F1: Free-list quirk re-investigation — missed-subtlety check (read-only, replaces F-1)

**Files:**
- (Read) `sf/src/allocator.zig`, the `## F-1 fix` report section (`.superpowers/sdd/task-ALLOC-report.md`), the `arena grew` marker log (regenerate `/tmp/if1_markers.log` via `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --markers --output-dir /tmp/if1_gen sf/src/main.zig 2>…`), the I-MEAS-1/2/3 chain/headroom tables
- Report: append `## I-F1` to `.superpowers/sdd/task-ALLOC-report.md`

**Interfaces:**
- Consumes: the F-1 attempt's BLOCKED result — best-fit splice of off-ladder free segments (import_scratch 455,156 B, parser 8,192/16,384) as the doubling base inflated subsequent carves (module +642 K, scratch +468 K) → `pool=` +732 K; the only real reuse savings were type_db −262 K, lir_read −99 K, parser −25 K. The reset-retained prize estimate (~8.1 MB upper bound, I-MEAS-3: scratch 8,384,512 + import_scratch 647,059 + parser 28,672 − scratch live 798,046).
- Produces: a verdict — either (a) a concrete corrected reuse policy that provably reduces `pool.peak` below 25,742 K (with a simulated number), or (b) a definitive close of F-1 (the prize is unreachable under the monotonic bump), plus any subtlety the F-1 attempt missed.

- [ ] **Step 1: Reconstruct the segment-allocation timeline**

From the marker log (`arena <name>: grew <old> -> <new>` events) + the I-MEAS-1 phase table, build the ordered timeline of every segment carve: arena, size, phase, and how it advances `pool.peak`. Identify the peak moment (post-C89-emission) and which carves happen before vs after it.

- [ ] **Step 2: Analyze the failure mechanism precisely**

For each reuse event in the F-1 attempt, show which off-ladder size became a doubling base and the resulting inflated carves (module 455,156 → 910,312 → 1,820,624; scratch 41,238 → 82,476 → …). Quantify how much of the +750,095 B growth is ladder inflation vs genuine reuse loss.

- [ ] **Step 3: Simulate the ladder-conserving policy**

Against the reconstructed timeline, simulate reuse constrained so no off-ladder size ever becomes a doubling base (e.g. only reuse when `size == new_size`, or only when `size` is on the 4K→2 MiB ladder, or exact-fit the reused segment's ladder accounting). Compute the hypothetical `pool.peak` under each variant. Does any variant drop below 25,742 K, and by how much?

- [ ] **Step 4: Check the missed subtlety — the timing of the peak**

The `pool.peak` is the monotonic bump high-water reached at the LAST phase (emission). A free-list only prevents FUTURE carves by reusing already-carved segments. Determine whether the reset arenas' chains (scratch resets between phases; import_scratch/parser after import) are available for reuse BEFORE the peak moment — i.e. whether the ~8.1 MB prize is reachable in principle, or whether the peak is set by carves that no free-list can avoid (no reset-arena segment of a useful size exists before the peak).

- [ ] **Step 5: STOP-present + report**

Present the verdict to the operator: pursue F-1 with a specific corrected policy (and which), or close F-1 definitively with the reasoning. Append `## I-F1` to `.superpowers/sdd/task-ALLOC-report.md`. NO `sf/src` edits, NO commit, NO ledger/mnemoria (controller-owned).

---

### Task F-2: Growth-policy tuning (segment headroom) (F)

**Files:**
- Modify: `sf/src/allocator.zig` (`growableSandGrow` :108-133)
- Commit: `perf: tune segment growth policy (cut headroom)`

**Interfaces:**
- Consumes: I-MEAS-1/2/3 headroom table — class (a) ≈ 5,547 K (27.8%): perm 1,216,006 + module 757,112 + scratch 1,299,106 + lir_read 2,096,720 + type_db 311,296; lir_read's near-empty 2 MiB cap segment is the single largest (2,419,456 chain / 432 B live at peak).
- Produces: `pool.peak` drop toward the headroom prize (~3.5–5.5 MB).

- [ ] **Step 1: Golden baseline capture**

Capture `/tmp/golden_F2/` (same set as F-1 Step 1) + record baseline `pool=`.

- [ ] **Step 2: Decide the tuning mechanism against the headroom table**

Choose from (record the choice + rationale in the report): (a) lower the 2 MiB cap (e.g. 1 MiB) so a 1.3 MB request doesn't carve a 2 MiB segment — but keep exact-fit-final so overshoot beyond the cap is still exact; (b) exact-fit downward: when the requested `size` is `<=` the doubled/capped `new_size`, allocate `max(next_pow2(size), min_segment)` instead of the full doubled/capped value; (c) both. MUST preserve the amortized-O(1)-copy property of doubling (do not regress to per-grow full copies) and keep `sandTryReallocInPlace` working (tail arrays need headroom — do not remove all headroom). Prefer the option that cuts lir_read/type_db slack most with least impact on in-place realloc.

- [ ] **Step 3: Implement + verify — NO semantic change**

Implement the chosen mechanism in `growableSandGrow`. Gates identical to F-1 Step 3: 4 MD5 byte-identical, golden 9/9, self-compile 41 `.c` / 0 err / 0 PANIC, ref 0-warning.

- [ ] **Step 4: Measure `pool=` before/after**

Report the `pool=` delta (expected: toward ~3.5–5.5 MB).

- [ ] **Step 5: Commit**

```bash
git add sf/src/allocator.zig
git commit -m "perf: tune segment growth policy (cut headroom)"
```

---

### Task F-3: Emitter-level — move persistent maps off scratch + per-function scratch reset (F)

**Files:**
- Modify: `sf/src/main.zig` (arena selection for `nameManglerInit` :738 / `c89EmitterInit` :740), `sf/src/c89_emit.zig` (emitter maps `emitted_type_set`/`fwd_decl_set`/`temp_global_map`/`ts_ref_set` :614-627; per-function scratch reset), possibly `sf/src/allocator.zig` if a dedicated arena is added
- Commit: `perf: move emitter maps off scratch + per-function scratch reset (emission churn)`

**Interfaces:**
- Consumes: I-EMIT finding — 94.4% of emission scratch churn (6,651,545 B cumulative) is `emitHoistedDecls` per-function arrays; both 2 MiB cap carves during emission come from tiny 1024/512 B requests; persistent emitter maps init from scratch (main.zig:738/740) → scratch cannot reset during emission; ~6.4 MB off peak estimate.
- Produces: `pool.peak` drop toward the emission-churn prize (~6.4 MB, estimate); enables per-function scratch reset.

- [ ] **Step 1: Golden baseline capture**

Capture `/tmp/golden_F3/` (same set) + record baseline `pool=`.

- [ ] **Step 2: First measurement — exact `emitHoistedDecls` footprint**

Before any change, measure the exact single-function hoisted-decl footprint (the I-EMIT report deferred this): instrument /tmp or read the emitted C to size the per-function arrays (`emitHoistedDecls` c89_emit.zig:2727-2745). Record as the F-3 prize anchor.

- [ ] **Step 3: Move persistent emitter maps off scratch**

Relocate the persistent maps (`nameMangler`, `emitted_type_set`, `fwd_decl_set`, `temp_global_map`, `ts_ref_set`) from `ctx.alloc.scratch` to `ctx.alloc.module` (or a dedicated arena) so scratch becomes reset-safe during emission. Update the init calls (`nameManglerInit`/`c89EmitterInit` at main.zig:738/740) to pass the new allocator. Verify every map's reads/writes still work (they persist across the whole emission).

- [ ] **Step 4: Reset scratch per-function during emission**

Add a scratch reset at each function-emission boundary (the same "reset = release" principle as F-1, applied mid-phase) to reclaim the dead `emitHoistedDecls` arrays. Ensure no emitter state survives the reset except the now-relocated persistent maps (verify by the byte-identity gates).

- [ ] **Step 5: Verify — NO semantic change + measure**

Gates: 4 MD5 byte-identical, golden 9/9, self-compile 41 `.c` / 0 err / 0 PANIC, ref 0-warning. Report `pool=` before/after (expected: toward ~6.4 MB off peak).

- [ ] **Step 6: Commit**

```bash
git add sf/src/main.zig sf/src/c89_emit.zig
git commit -m "perf: move emitter maps off scratch + per-function scratch reset (emission churn)"
```

---

### Task F-4: Dead-buffer pre-sizing / tail-aware ordering (class b) (F)

**Files:**
- Modify: `sf/src/ast.zig` (astStore extra-children/extra-ranges growth :148/:180, 1,458 K offender), the interner (`sf/src/string_interner.zig`, si_entries 491 K), the hash-map growth sites (U32ToU32Map etc., ~974 K), `sf/src/resolved_type_table.zig`/type_db if its 276 K offender is targeted
- Commit: `perf: pre-size high-churn arrays (kill dead-buffer copy churn)`

**Interfaces:**
- Consumes: I-MEAS-2 churn data — class (b) ≈ 3,236 K (16.2%): module 1,573,856 dominates (astStore extra-children/extra-ranges 1,458 K), perm 7,040, scratch 56,032, parser 7,840; always-copy net perm 745 K + module 2,240 K + type_db 269 K.
- Produces: `pool.peak` drop toward the dead-buffer prize (~3.2 MB).

- [ ] **Step 1: Golden baseline capture**

Capture `/tmp/golden_F4/` (same set) + record baseline `pool=`.

- [ ] **Step 2: Decide mechanism per offender**

For each top offender (astStore extra-children/extra-ranges ast.zig:148/180; si_entries string_interner; hash-map arrays; type_db): choose (a) pre-size capacity where the final size is knowable (e.g. reserve from a token count / module size), (b) tail-aware allocation ordering (allocate the growing array last so `sandTryReallocInPlace` succeeds), or (c) both. Record the choice + rationale in the report. Preserve byte-identity (array CONTENT/order unchanged; only allocation timing/sizing).

- [ ] **Step 3: Implement + verify — NO semantic change**

Implement. Gates: 4 MD5 byte-identical, golden 9/9, self-compile 41 `.c` / 0 err / 0 PANIC, ref 0-warning.

- [ ] **Step 4: Measure `pool=` before/after**

Report the `pool=` delta (expected: toward ~3.2 MB).

- [ ] **Step 5: Commit**

```bash
git add sf/src/ast.zig sf/src/string_interner.zig <other modified>
git commit -m "perf: pre-size high-churn arrays (kill dead-buffer copy churn)"
```

---

### Task I-SPILL: Conditional-spill evaluation (read-only, gated after F-4)

**Files:**
- (Read) `sf/src/lir_stream.zig`, `sf/src/ast.zig` (spill machinery), `sf/src/module_registry.zig` (hash spill), the F-1..F-4 `pool=` before/after measurements
- Report: append `## I-SPILL` to `.superpowers/sdd/task-ALLOC-report.md`

**Interfaces:**
- Consumes: the post-F-4 `pool.peak` (expected high-teens/low-teens MB vs the pre-lever 25,742 K).
- Produces: a go/no-go + design for making S-LIR / S-AST / S-HASH conditional (spill only when `pool.peak` is projected to cross a threshold; small compiles skip disk I/O).

- [ ] **Step 1: Measure the post-F-4 `pool.peak` on the full range**

Run `--track-memory` on the reference zig1 self-compile AND on a small-program ladder (hello, game_of_life, lisp_interpreter_curr, json_parser) to establish the spread: small compiles vs the self-compile.

- [ ] **Step 2: Design conditional spill**

For each of S-LIR / S-AST / S-HASH, design the threshold gate: a projected-memory check (e.g. module count / AST node count / `pool.peak` trend) that switches the spill on only when needed. Consider: (a) always-spill (current) vs (b) threshold-gated vs (c) never-spill below a hard floor. Record the decision inputs (I/O cost of spilling, Win9x memory ceiling, per-size-class measurements).

- [ ] **Step 3: STOP-present the recommendation**

Present the go/no-go + the conditional-spill design to the operator. Do NOT implement. Append `## I-SPILL` to `.superpowers/sdd/task-ALLOC-report.md`. No `sf/src` edits, no commit.
