# zig1 Memory Refactoring — Investigation + Roadmap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Investigate (5 read-only I tasks, each small and independently reviewable) and then propose (1 P task) a **conclusion/roadmap** for zig1's future memory refactoring — aiming at ≤ 16 MiB pool self-compile and never OOM-ing a 32 MB physical Windows 98 host. Deliverable = a committed roadmap document, NOT the refactoring.

**Architecture:** I-1 hot-structure census → I-2 arena/pool behavior → I-3 zig0 dialect design-space → I-4 I/O spill feasibility → I-5 marker-volume census → P-1 consolidates all findings into the roadmap doc. All I tasks read `sf/src/*.zig` + measure; P-1 commits the roadmap. No `sf/src` changes anywhere.

**Tech Stack:** Zig (`sf/src/*.zig`), zig0 dialect (the binding constraint), C89 (emitted code), bash (measurement).

## Global Constraints

- **Read-only for I tasks: no `sf/src` edits, no commits.** The only commit is P-1's roadmap doc.
- **Hard target frame:** zig1 self-compiles ≤ 16 MiB pool; compilation must never make Windows go "out of memory" (32 MB physical P3/P4 Win98). The roadmap must state how each option respects this.
- **zig0 dialect is binding** (migration is a future objective): only plain structs, unions, u32/u64 + shift/mask helpers, arrays, out-of-line value tables. No packed structs, no bitfields, no anytype, no @Type. Custom binary encoding allowed.
- **I/O tricks in scope:** page-file / partial AST-LIR disk dump may be evaluated; feasibility + risk is a deliverable (I-4).
- **Evidence rule:** every roadmap/finding claim must trace to a `file:line` read or a measurement (count, byte size, RSS/pool number) in the report. No invented figures.
- Byte-identity: 4 MD5 gates (gol `eed963e0…`, lisp `c3c58477…`, json `089e4f04…`, mud `a1d0dd55…`) are untouched this plan (no source changes); re-baselining is operator-allowed for future execution, NOT here.
- Builds/compiler under test unchanged: `/tmp/fx_subfolder/zig1`; rebuild `timeout 900 bash sf/scripts/build_release.sh` (repo root, gate `=== [release] Done ===`, reinstall std lib after wipe); self-compile `timeout 900 bash scripts/self_compile/build_zig1_5.sh`. `timeout 120` on every compiler/binary invocation.
- Measurement mechanics: `--track-memory` requires `--markers`; on self-compile stderr floods (~7.4M lines) — redirect to file + `grep "track-memory:"`. `--output-dir` must pre-exist. `size` for text/data/bss. `grep -c` / `rg -c` for site counts.
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent memroadmap-session --type <discovery|decision|problem|pattern>` per task.
- Reports: one shared `.superpowers/sdd/task-ROADMAP-report.md` (gitignored), appended per task. WARNING: `.superpowers/sdd/task-1-report.md` is TRACKED with unrelated content — never use it. task-brief script matches numeric "Task N" only; prefer self-contained dispatches.
- Editing discipline (should not be needed given read-only): `edit`/`fastedit` only; never touch `sf/build/out_release/`.

---

### Task I-1: Hot-structure census (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ROADMAP-report.md` (append; gitignored)

**Interfaces:**
- Consumes: ast.zig, lir.zig, token.zig, and any hot struct/union definitions across `sf/src`.
- Produces: waste map — exact sizeof (zig0 C layout), per-field usage, count at self-compile scale.

- [ ] **Step 1: Enumerate hot structs/unions**

Read and list every struct/union allocated at scale: `AstNode` (ast.zig:116-128), `LirInst` (lir.zig:22-102), `Token` (token.zig:115-123), plus `OpInfo`, `CallInfo`, type-registry entries (`Type`, `FnType`, `PtrType`, `ErrorUnionType`, …), symbol-table entries, interner/hash-map entries (`hash_mod`), error-set entries. Record for each: definition `file:line`, field list with types, and the emitted C `sizeof` (compute from the zig0 layout rules; padding included).

- [ ] **Step 2: Measure per-field + per-struct usage**

For the top structs, determine which fields are (a) always used, (b) rarely used (side-table candidates), (c) over-wide (u64 holding a u32; 8-byte alignment forced by a union member). Use existing markers where present (`ZZZ_ASTNODE_32B`, `IRN:n180020` = 180,020 nodes) and `grep`/`rg` usage scans in `sf/src`.

- [ ] **Step 3: Count at self-compile scale**

Measure or estimate each struct's instance count at self-compile (markers, or array/arena high-water from `--track-memory --markers` on the self-compile dump). Compute each struct's total bytes (count × sizeof).

- [ ] **Step 4: Waste map + synthesis**

Output table: struct | sizeof | count | bytes | per-field waste notes | compaction candidates. End with one paragraph: "what this means for ≤16 MB". Report + ledger + mnemoria (discovery).

---

### Task I-2: Arena/pool behavior (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ROADMAP-report.md` (append)

**Interfaces:**
- Consumes: allocator.zig (:78-87 sandReset, :108-130 growableSandGrow, :158-171 sandTryReallocInPlace, :184 pool buf, :186 pool bump, :191-192 MAX_MEM, :216-228 checkCombinedPeak), main.zig (:155-157 type_db stack arena, :239-258 track-memory).
- Produces: arena-flow diagram + 83 MB→20 MB gap breakdown + reclaim/spill points.

- [ ] **Step 1: Map the arena architecture**

From allocator.zig, document: the pool bump (`pool: Sand`, monotonic, never reset), the three GrowableSand segment arenas (perm/mod/scr) backed by the pool, segment doubling policy (4K→8→16…), `sandReset` "keep peak + post-reset reuse", `sandTryReallocInPlace` tail-guard, and the separate type_db stack arena.

- [ ] **Step 2: Explain the 83 MB vs 20 MB gap**

Using the Task-2 memory-comparison data (`pool=83210K total=20372K` at self-compile) and reading the growth paths, break down what the 83 MB cumulative high-water is (which collection/arena, how many segments, churn) vs the 20 MB live. Identify the top contributors to the geometric doubling (e.g. module arena 16 MB live → ~32 MB pool chain).

- [ ] **Step 3: Enumerate reclaim / spill points**

Where can memory be returned to the pool (which sandReset sites exist — per scope/function/module), where does `sandTryReallocInPlace` already avoid waste, and where is a structural return-to-pool or spill-to-disk possible? Note the `checkCombinedPeak` bug (gates POOL_SIZE not max_mem — 16 MB budget unenforced).

- [ ] **Step 4: Report + synthesis**

Arena-flow diagram, gap breakdown table, reclaim/spill points, one paragraph "what this means for ≤16 MB". Report + ledger + mnemoria (discovery/pattern).

---

### Task I-3: zig0 dialect design-space (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ROADMAP-report.md` (append)

**Interfaces:**
- Consumes: the whole `sf/src` corpus (patterns already in use), zig0 bootstrap behavior.
- Produces: the legal representation toolkit + existing patterns to reuse.

- [ ] **Step 1: Catalog what zig0 actually compiles**

From existing `sf/src` patterns, list the representation constructs in use and confirmed working: plain structs, `union(enum)`/`union`, `u32`/`u64` fields, shift/mask helpers (e.g. `start << 32 | count` packing), arrays, out-of-line value tables (AstStore int/float pool pattern). Confirm NOT available: packed structs (Token 16 B `FIXME` rejected), bitfields, `anytype`, `@Type`. Record `file:line` evidence for each.

- [ ] **Step 2: Map each I-1 compaction candidate onto the toolkit**

For each I-1 candidate (AstNode 32→~20-24 B, LirInst 32→~16-20 B, Token 24→~12-16 B, side tables for child_2/extra operands), specify the zig0-legal encoding: exact field layout (u32 fields, shifts), which existing pattern it mirrors, and any zig0 limitation it must dodge.

- [ ] **Step 3: Verify feasibility of the top candidates**

For the 2-3 highest-value candidates, confirm (by reading the consumers in `sf/src`) that the encoding change is mechanically expressible in zig0 (no dialect feature the rewrite would need). Note any consumer that would need touching.

- [ ] **Step 4: Report + synthesis**

Toolkit table (construct | zig0-supported? | evidence), candidate→encoding mapping, one paragraph "what this means for ≤16 MB". Report + ledger + mnemoria (discovery/pattern).

---

### Task I-4: I/O spill feasibility (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ROADMAP-report.md` (append)

**Interfaces:**
- Consumes: the pipeline main → parser → semantic_analyzer → lower → c89_emit (import_resolver.zig, parser.zig, lower.zig, c89_emit.zig); the allocator/pool model from I-2.
- Produces: spill points + feasibility + risk (page-file / partial AST-LIR disk dump).

- [ ] **Step 1: Map the pipeline + data lifetimes**

Read the pipeline to establish where the AST store and LIR are built, when they die, and the module boundaries. Determine single-pass vs multi-pass structure and whether AST/LIR can be re-loaded per module.

- [ ] **Step 2: Identify spill points**

Where could AST/LIR be partially dumped to disk/page-file: per-module boundaries, per-function LIR spill after relocation, token/parse streaming. For each: what must be serialized, what re-load requires, and whether the C89 emission is streaming-friendly.

- [ ] **Step 3: Win98 OOM failure-mode + graceful degradation**

Read how pool exhaustion manifests today (checkCombinedPeak vs max_mem) and what "out of memory" means on the Win98 target (32 MB physical). Assess whether a spill path can guarantee no-OOM, or whether it only reduces the peak.

- [ ] **Step 4: Report + synthesis**

Spill points table (point | mechanism | serialized data | re-load | risk), feasibility verdict, one paragraph "what this means for ≤16 MB / no-OOM". Report + ledger + mnemoria (discovery/decision).

---

### Task I-5: Marker-volume census (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ROADMAP-report.md` (append)

**Interfaces:**
- Consumes: pal.zig (markerWrite :130-134), `rg 'markerWrite' sf/src`, main.zig marker gating.
- Produces: reduction options — rodata bytes, per-site volume, stderr I/O cost.

- [ ] **Step 1: Count + classify marker sites**

`rg -c 'markerWrite' sf/src/*.zig` (baseline: 2,932 `[]const u8="…"` sites). Classify: per-file counts, the `pal.markerWrite`/`markerWriteInt` split, and which sites are diagnostics vs debug (each `pal.markerWrite` call site).

- [ ] **Step 2: Measure rodata + stderr volume**

Estimate rodata bytes from the marker strings (sum of string lengths across sites) and the `--markers` self-compile stderr volume (82 MB / ~7.4M lines / ~27 s wall — from memory-comparison closeout M3/M4). Note markers are NOT arena memory — only wall + rodata.

- [ ] **Step 3: Reduction options**

Options: gate strings by a single `#define`-style flag, coarsen the marker set, compress repeated prefixes, or convert markers to numeric codes. For each: expected rodata/stderr/wall reduction + any loss of debuggability.

- [ ] **Step 4: Report + synthesis**

Site table, rodata + stderr numbers, reduction options with estimates, one paragraph "what this means for ≤16 MB". Report + ledger + mnemoria (discovery).

---

### Task P-1: Roadmap conclusion (proposal — the committed deliverable)

**Files:**
- Create: `docs/superpowers/specs/2026-08-26-zig1-memory-refactor-roadmap.md`
- Commit: `docs: zig1 memory refactor roadmap (≤16MB pool, no-OOM)`

**Interfaces:**
- Consumes: I-1..I-5 findings (report), the operator's hard target (≤16 MiB pool self-compile, never OOM 32 MB Win98), zig0-dialect constraint.
- Produces: the roadmap document — the conclusion for the zig1 future refactoring.

- [ ] **Step 1: Consolidate findings**

Read `.superpowers/sdd/task-ROADMAP-report.md` (I-1..I-5). Build the consolidated picture: current 83 MB cumulative / 20 MB live vs 16 MiB target; the two drivers (32-byte structs, geometric segment doubling); spill + marker levers.

- [ ] **Step 2: Define the roadmap items**

For each candidate (representation compaction per struct, arena reclaim / pool reset, segment-growth policy, I/O spill, marker reduction): pool-reduction estimate (MB), zig0-compat (toolkit from I-3), implementation risk, effort, and which I-1..I-5 evidence supports it. Order by value/risk.

- [ ] **Step 3: Write the roadmap doc**

Structure: current state (measured), the 16 MiB / no-OOM frame, prioritized roadmap with per-item estimates + recommended order, the "what cannot happen" guarantee analysis (each option's effect on OOM risk), and the acceptance criteria for a future execution plan (e.g. self-compile pool ≤ 16 MiB; 4 MD5 gates re-baselinable; no Windows OOM). Every number must trace to the report.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim (above), staging ONLY the roadmap doc. Report: roadmap summary + evidence trace. Ledger + mnemoria (decision/pattern). No other commits, no `sf/src` changes.
