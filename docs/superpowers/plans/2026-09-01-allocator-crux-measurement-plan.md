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

## After the measurement (gated redesign — added by amendment)

After the operator picks the redesign direction from the I-MEAS-3 crux map **and the I-EMIT emission study**, this plan is amended with the F-task(s): a segment free-list keyed on "reset = release", growth-policy tuning, per-arena pools, an emission-targeted fix if I-EMIT finds one, or the combination the data supports. Each F-task carries the full gate battery (4 MD5 keep-or-re-baseline with golden 9/9 runtime evidence, self-compile 41 `.c` / 0 err / 0 PANIC, reference 0-warning, Z98 dialect, `edit`/`fastedit` only) and a `pool=` before/after measurement.
