# Task 3 — Lever catalog + recommendation (READ-ONLY) report

Branch: `zig1_improvements` (NO push). Spike terminal task: **NO `sf/src` edits, NO seed rotation,
NO dump-MD5 re-baseline, NO fixes.**

Reference compiler (not rebuilt): `/tmp/nonast_seed/zig1_5_clean`, md5
`d40e875a7ba3aa55d441af56006d6023`. CWD `/workspace/znineeight`, source arg RELATIVE
`sf/src/main.zig`.

## Decisive numbers carried in from Tasks 0–2 (no re-derivation)

- **Gap to close:** `-s0` `pool = 19,274 K` vs `16,384 K` (`-mm16`) → **2,890 K** (Task 0).
- **`diag_read`** (Task 0/1): carve **4,545 K** = live **2,913.4 K** (file text **2,711.1 K** 93.0% +
  per-line u32 index **201.6 K** 6.9% + headers 0.7 K) + unused segment tail **1,631.9 K** (logged
  carve) / **1,635.9 K** (incl. 4,096 B un-logged first segment). **43 of 47** parsed modules faulted
  once; held from semantic analysis through the pool peak; reset once at end-of-run
  (`diagnostics.zig:721`) then process exits.
- **`import_scratch`** (Task 0/2): carve **1,353 K**, but live high-water **582.7 K** (transient, one
  resolved file at a time), reset per `@import`; the excess is temporal, not tail.
- **`source`** (Task 0/2): carve **0 at `-s0`** (39 grows all served from `seg_free_head`); live
  high-water **582.7 K** transient.
- **`module`** (Task 0/2): carve 5,256 K / max live **5,419 K** / tail **1,084 K**; reuses **1,276,415 B**
  of `import_scratch`/`source` segments.
- **`scratch`** (Task 0/2): carve 4,570 K / max live **3,397 K** / tail **1,007 K**.
- **`mod=`/`scr=` are NOT footprints** — they are `Sand.peak` (per-segment high-water), e.g. `-s0`
  `mod=1020 K` vs 5,419 K live (Task 2).

**Measurement framing (critical).** The prize must be stated in **pool-peak bytes**, not live bytes.
Task 2 established that `sandReset` returns segments to the cross-arena `seg_free_head`
(`allocator.zig:78-97`) and `growableSandGrow` re-pops best-fit from it without a carve
(`allocator.zig:132-144`), so a carve can be re-attributed to another arena. Freeing arena X only lowers
the *pool peak* if a later grow reuses X's segments instead of carving new ones. All prizes below are
bounded on that basis.

---

## Step 1 — Lever catalog

### L1 — line-index representation `u32` → `u16`/delta/lazy

- **Mechanism.** The per-line offset index is a `U32ArrayList` held in the `diag_read` arena. Built
  eagerly at fault time: `source_manager.zig:174` `u32ArrayListEnsureCapacity(lo_ptr, cap)` then
  `Append(0)` + one `Append(i+1)` per `'\n'` (`:175-178`). Read back as `[]u32` in
  `sourceManagerGetLineOffsets` (`:223-231`) and `sourceManagerGetLocation` (`:245-247`), and by
  `diagnostics.zig:779-785`. Replace the entry type with `u16` **delta** (line length) or a lazy/varint
  encoding.
- **Files/sites.** `sf/src/source_manager.zig:163-178` (build), `:223-253` (read),
  `sf/src/growable_array.zig` (`U32ArrayList`), `sf/src/diagnostics.zig:745,779-785`.
- **Expected prize (bounded).** Line entries = 51,578 newlines + 43 files = 51,621; live index
  **201.6 K** (Task 1). `u32→u16` = 2 B/entry → **≤ 103.2 K live**. Absolute `u16` is impossible (files
  > 65,535 B: `lower.zig` 596,656, `c89_emit.zig` 531,960, `semantic_analyzer.zig` 425,201, …), so a
  delta/length encoding with an overflow escape is required. Because the `diag_read` carve is driven by
  whole-file segment requests and tail waste (Task 1 segment table), a ~100 K live shrink likely
  **removes no segment** → **pool-peak prize ≈ 0, upper bound 103.2 K**.
- **Risk.** Medium: overflow handling for long lines; touches the `GetLocation`/print path, so error
  goldens can move.
- **Gate.** Corpus + goldens byte-identical; record dump-MD5 delta; `--track-memory` pool must fall.

### L2 — drop file text after the index is built; re-read on demand

- **Mechanism as specified.** After building the line index, free the file text so only the index is
  retained, re-reading the file at diagnostic time.
- **Disconfirming measurement.** The faulted text **is consumed after** the index is built. Index is
  built inside `sourceManagerFaultIn` at `source_manager.zig:174-178`; the analysis-time span scanners
  then read the payload bytes via `sourceManagerGetSourceContent` — `diagnostics.zig:644` +
  `content[i]` at `:649-667` (`scanIdentSpan`), `:675-683` (`findLastByte`), `:689-696`
  (`findFirstByte`) — reached from `semantic_analyzer.zig:688,4447,5633`. Dropping the text therefore
  forces a re-read on every scan, i.e. the same bytes are faulted again; there is **no peak reduction**
  (and more I/O). L2 is not a distinct lever from L3.
- **Verdict:** **NO-GO** — disconfirming site/number: text is read at `diagnostics.zig:649` *after* the
  index is built at `source_manager.zig:174`; scans are the sole consumer of the faulted text.

### L3 — bound `diag_read` retention (reset/ceiling between modules)

- **Mechanism.** Reset the `diag_read` fault arena periodically during analysis instead of holding all
  43 faulted files to end-of-run, so only the current module's file is live. `sourceManagerResetFaults`
  already does exactly this (`source_manager.zig:194-202`): `sandReset` returns segments 2…N to
  `seg_free_head` (`allocator.zig:78-97`) and clears `loaded` on transient files (`:200`). All
  self-compile modules are added **transient** (`import_resolver.zig:16`
  `sourceManagerAddFileTransient`), so reset re-arms them for re-fault. Today the only caller is
  end-of-run `diagnosticCollectorPrintAll` (`diagnostics.zig:721`); add a per-module call in
  `phase_StaticAnalyzers` (`main.zig:739-778`) after `az_mod.runAllAnalyzers` (`main.zig:775`).
- **Why one file suffices.** Scanners use `self.source_file_id = mods[mi].source_file_id`
  (`main.zig:773`) — the current module only; `runAllAnalyzers` is per-module
  (`main.zig:746-776`), and each module's scratch is already reset per iteration (`main.zig:747`).
  So retention need never exceed one file's triple.
- **Expected prize (bounded).** `diag_read` carve **4,545 K**; largest single file triple = `lower.zig`
  633,960 B (`lower` text 596,656 + index 37,288) → live ≤ ~619 K (633,960 B), **but a per-module reset
  retains one file's *capacity*, not just its live bytes**: the whole-file text segment is exact-fit and
  fills to `end`, forcing the 16-byte header (and index) into a `max(2*last, request)` segment capped at
  1 MiB (`allocator.zig:127-131`), so the worst-case retained instant is ~1.6 MiB, not ~640 K. Upper
  bound = **≤ 4,545 K**; realistic = full-run retention minus that ~1.6 MiB retained instant minus
  freed segments actually reused by emission-phase `scratch`/`module` growth ≈ **~2,900–2,950 K**
  (4,545 − ~1,600); the fix task **MUST measure the actual pool drop**. Task 1 places `diag_read`'s
  peak growth burst (stderr 17521–17824) *before* the emission-phase `scratch`/`module` grows
  (stderr 18246–18512), so freed segments land exactly where the remaining pool growth occurs — the
  best reuse window in the run. **This bound is still above the 2,890 K gap, but thin.**
- **Risk.** Medium. Re-fault at print time is already required and proven by the existing
  reset-before-print path (`diagnostics.zig:721` → `sourceManagerGetLocation` → `sourceManagerFaultIn`,
  `source_manager.zig:219,243`); risk is a behavior/golden change if any analysis-time consumer needs a
  *prior* module's content, or if reset timing perturbs diagnostics. L3's correctness/behavior also
  depends on every `SourceManager` file being added **transient** (so `sourceManagerResetFaults` re-arms
  it for re-fault): true for self-compile via `sourceManagerAddFileTransient`
  (`sf/src/import_resolver.zig:16`), while the non-transient `sourceManagerAddFile` is test-only; the fix
  must note/assert this.
- **Gate.** `repro/mi_matrix` + goldens byte-identical (diagnostics output byte-for-byte);
  dump-MD5 delta vs the pre-fix dump recorded; `--track-memory` pool must drop by ≥ 2,890 K toward
  16,384 K. Prefer a per-module reset; if that perturbs anything, fall back to a ceiling/reset at the
  analysis→lowering boundary (`main.zig:401` already resets `module`).

### L4 — skip fault-in for modules that never produce a source-bearing diagnostic

- **Mechanism.** Avoid `sourceManagerGetSourceContent`/fault when a module will not emit a
  source-bearing diagnostic.
- **Disconfirming measurement.** The faults are **span-computation side effects, not diagnostic-driven**.
  The scanner calls at `semantic_analyzer.zig:688` (`NthIdentSpan`),
  `:4447`/`:4449` (switch-prong capture), `:5633`/`:5636`/`:5640` (`for` captures) feed
  `semanticAnalyzerCheckLocalShadow`/`registerLocalDecl` (symbol spans), and they run unconditionally.
  Yet on this clean run **43 of 47** modules fault while **0** of the 100 diagnostics carry a
  non-zero `file_id` (Task 1: all warnings take the `d.file_id == 0` fast path at
  `diagnostics.zig:727-744`). You cannot pre-know a module emits no source-bearing diagnostic without
  scanning, and skipping the scan changes capture spans → error goldens move.
- **Prize.** Upper bound = full 4,545 K (zero faults), but risk is high (span/symbol semantics), and the
  same bytes are won by L3 without changing spans.
- **Verdict:** **NO-GO standalone** — disconfirming numbers: **43/47 faulted vs 0 source-bearing
  diagnostics**; faults serve `registerLocalDecl` spans, not printed diagnostics.

### L5 — `import_scratch` / `source` caps or early release

- **Mechanism.** Cap/free the `import_scratch` arena (`import_resolver.zig:59-61`, used at
  `parser.zig:780-782` → `module_registry.zig:384` whole-file content-hash read) and the `source` arena
  (`import_resolver.zig:63-65,81`).
- **Disconfirming measurement.** Both are exact-fit and **transient**; `source` carve at `-s0` is **0**
  (all reads reused from `seg_free_head`), and `module` reuses **1,276,415 B** of `import_scratch`/
  `source` segments (Task 2). Capping/freeing them does not lower the pool peak; it only shifts which
  arena carves those segments. Net pool-peak change **≈ 0**.
- **Verdict:** **NO-GO** — disconfirming numbers: `source` `-s0` carve **0**; module reuse
  **1,276,415 B**.

### L6 — right-size / stream the `diag_read` whole-file fault (additional lever, measurement-supported)

- **Mechanism.** `growableSandGrow` sizes new segments `new = max(2*last, request)` capped at 1 MiB
  (`allocator.zig:127-131`); every fault requests a whole file (`source_manager.zig:161`) plus a 16-byte
  header and `4*cap` index (`:163-174`), so large files abandon large tails (Task 1: segment 5
  324,744 B, segment 7 996,896 B unused). Pre-grow an exact-fit segment for the known whole-file
  request, or stream/chunk the fault, so the tail is not held.
- **Files/sites.** `sf/src/source_manager.zig:161-174` (caller) and/or `sf/src/allocator.zig:118-157`
  (policy).
- **Expected prize (bounded).** `diag_read` tail waste = logged carve 4,654,398 − live 2,983,362 =
  **1,631.9 K** (1,635.9 K incl. 4,096 B un-logged first segment). Pool-peak prize upper bound
  **≈ 1,632 K**. Overlaps L3: if L3 keeps one file live, per-file exact-fit still removes that file's
  tail. **Do L6 only if L3 measures short.**
- **Risk.** Medium: a global growth-policy change perturbs `module`/`scratch` reuse (tails 1,084 K /
  1,007 K, Task 2); a targeted pre-grow at the fault site is lower-blast-radius.
- **Gate.** Same corpus/goldens battery + recorded dump-MD5 delta; re-measure `diag_read` carve/live and
  pool peak.

### Additional context (not catalogued as levers)

`module` tail **1,084 K** and `scratch` tail **1,007 K** (Task 2) are larger than L6's prize but are the
exhausted allocator-tier levers the spec lists as non-goals (F-1/I-F1, M5, I-COMPACT, S-INTERNER).
Not pursued.

---

## Step 2 — Ranked by expected prize ÷ risk

| rank | lever | mechanism | prize bound (pool peak) | risk | verdict |
|---|---|---|---|---|---|
| **1** | **L3** | reset `diag_read` per module (`source_manager.zig:194`; call from `main.zig:775`) | **≤ 4,545 K; ~2,900–2,950 K realistic** | Medium | **PROCEED (primary)** |
| 2 | L6 | right-size/stream whole-file `diag_read` fault (`source_manager.zig:161-174` / `allocator.zig:127-131`) | ≤ 1,631.9 K | Medium | PROCEED only if L3 falls short |
| 3 | L1 | `u32`→`u16`/delta line index (`source_manager.zig:174`) | ≤ 103.2 K live; ~0 pool | Medium | Defer |
| — | L4 | skip fault-in when no source-bearing diag | (4,545 K upper, unattainable) | High | **NO-GO** — 43/47 faulted, 0 source-bearing; spans feed `registerLocalDecl` |
| — | L2 | drop text after index, re-read | 0 net | High | **NO-GO** — text read at `diagnostics.zig:649` after index built at `source_manager.zig:174` |
| — | L5 | cap/free `import_scratch`/`source` | ≈ 0 | Low | **NO-GO** — `source -s0` carve 0; module reuse 1,276,415 B |

---

## Step 3 — Recommendation

**PROCEED, one lever: L3 — bound `diag_read` retention by resetting the fault arena per module.**

Rationale: L3's measurement-bounded prize (~2,900–2,950 K) **is still above the 2,890 K gap, but thin**, it reuses an existing,
already-correct primitive (`sourceManagerResetFaults`), and the existing reset-before-print path proves
re-faulting is supported. Author a separate fix plan with a single L3 task
(`measure → implement → corpus+goldens+stdlib → record dump-MD5 delta → commit`). L2/L4/L5 are
**NO-GO** (measurements above). L6 is a **conditional second** task only if L3's measured pool does not
reach ≤ 16,384 K; L1 is deferred (bounded ≤ 103 K and likely 0 pool peak).

STOP. No fixes performed by this spike.

---

## Concerns

1. **Pool-peak accounting is reuse-dependent.** L3's ~2,900–2,950 K assumes emission-phase `scratch`/`module`
   grows reuse the freed `diag_read` segments via `seg_free_head` best-fit (`allocator.zig:159-191`).
   Task 2 showed reclaim is real but not guaranteed size-matched; the L3 fix task must *measure* the
   actual pool drop, not assume the bound.
2. **No dump-MD5 baseline was captured by the spike.** Task 0 recorded only the binary md5
   (`d40e875a…`) and dump file counts (48 `.c`/48 `.h`); it did **not** record a hash of the emitted C
   dump. The fix plan's gate ("record dump-MD5 delta") must first capture a pre-fix dump MD5.
3. **Seed moved mid-spike.** `git log` shows `5ea276d0 release(seed): rotate v91 -> v92` landed between
   the Task 1 and Task 2 report commits. Measurements used a binary built from the v91 archive
   (`release/seed/zig1-seed.tgz`) into `/tmp/nonast_seed`. Any fix plan must confirm which seed era it
   targets; the reference binary remains `d40e875a7ba3aa55d441af56006d6023` for this spike.
4. **Recorded archived fixed point does not reproduce** (Task 0 rc=1 at the `FIXED_POINT_MD5` gate):
   hop1==hop2==`d40e875a…` ≠ archived `0b8c3e4ac0b1fc49c0bdf8caf9d39945`. The measurement binary is a
   valid self-fixed-point of current `sf/src`, not the archived point. No re-baseline performed (spike
   rule).
5. **Error-corpus I/O and goldens.** L3 re-faults source at print time for source-bearing diagnostics
   (`diagnostics.zig:745`), increasing I/O on the error corpus; goldens must be byte-identical
   including diagnostic formatting.
6. **Data-dependent fault set.** Which 43 modules fault depends on the current worktree source
   (Task 1 concern 5); small source changes shift the carve by tens of KB, so L3's prize must be
   re-measured after any future source change.
7. **`L nodes=` marker is compiled out** (`pal.zig:210-216`, `g_markers_debug = 0`); `IRN:n`/`IRE:x`
   remain the only AST/LIR scale markers (Task 0).
8. **Untracked strays** (`*.z98`, `*.err` at repo root) pre-existed and were not staged; this commit
   stages **only** this report with `git add -f`.

## Step 4 — Commit

Committed with `git add -f` and message `docs: non-AST memory spike — findings + lever catalog` (only
this report; `.superpowers/sdd/.gitignore` ignores `*`, so `-f` is required). No source files staged.

---

## Review-fix (final)

Final review corrections applied (docs-only, no `sf/src` change):

- **A — L3 prize bound under-subtracted capacity.** L3's realistic bound was `~3,900 K` (4,545 − one
  file's *live* ~640 K). Corrected to **~2,900–2,950 K** (4,545 − ~1,600): a per-module reset retains
  one file's *capacity* — the exact-fit whole-file text segment fills to `end`, forcing the 16-byte
  header into a `max(2*last, request)` capped-at-1-MiB segment (`allocator.zig:127-131`), so the
  worst-case retained instant is ~1.6 MiB, not ~640 K. Live one-file figure corrected `~640 K` →
  **~619 K (633,960 B)**. Upper bound kept at **≤ 4,545 K**. Step 1 L3 bullet, ranked table row 1, the
  Step 3 rationale, and Concerns #1 now all read ~2,900–2,950 K; the bound is still above the 2,890 K
  gap but thin, so the fix task **MUST measure the actual pool drop**.
- **B — L3 transient-file dependency.** L3 `Risk` bullet now states correctness/behavior depends on
  every `SourceManager` file being added **transient** (self-compile: `sourceManagerAddFileTransient`,
  `sf/src/import_resolver.zig:16`; non-transient `sourceManagerAddFile` is test-only), so the fix must
  note/assert it.
- **C — tail arithmetic off ~4 K / mislabeled.** Logged tail = 4,654,398 − 2,983,362 = 1,671,036 B =
  **1,631.9 K**; the incl-initial-4,096-B figure is 1,675,132 B = **1,635.9 K**. Corrected in
  `task-1-report.md` reconciliation (`1,635.9 K` → `1,631.9 K` logged / `1,635.9 K` incl. initial),
  the Task 3 "Decisive numbers" bullet (`1,632.8 K` → `1,631.9 K`; `1,675.1 K` → `1,635.9 K`), L6
  (`1,632.8 K` → `1,631.9 K`; parenthetical `1,675.1 K` → `1,635.9 K`; `≈ 1,633 K` → `≈ 1,632 K`), and
  the ranked table row 2 (`≤ 1,632.8 K` → `≤ 1,631.9 K`).
