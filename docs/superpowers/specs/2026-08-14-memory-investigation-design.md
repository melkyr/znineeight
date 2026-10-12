# Compiler Memory / Allocation Investigation Design Spec

**Date:** 2026-08-14
**Status:** Approved by operator (m0981, m0985). Ready for plan.

## 1. Goal

Investigate *why* zig1 cannot self-compile within the 16 MB budget, looking at **both** the bump-arena sizing AND the compiler code's data structures. The operator's hypothesis (m0977): "we are wasting memory or overallocating, because that's why we aren't able to self compile under 16mb." Investigation-first: I-tasks → report → combined STOP → separate fix plan.

## 2. Problem Statement

Prior studies (MEM1/MEM2/MEM3, `.superpowers/sdd/`) established:
- zig0 self-compiles 35,316 lines of `sf/src` at ~41 MB RSS (malloc-based); ASan-free zig1 beats zig0 on all example inputs (RSS 1,880-4,120 KB).
- The static arenas were resized (F5, 2026-08-08) to perm 4MB / module 8MB / scratch 2MB with a 16 MB budget (`allocator.zig:74-79`).
- **Self-compile STILL fails:** the import phase OOMs in the **scratch** arena (2MB) lexing the largest file (~5,071-line c89_emit.zig): `OOM: used=1899216 new=3472080 total=2097152`. The token array's geometric doubling (`tokenArrayEnsureCapacity`, `import_resolver.zig:16-26`) allocates a fresh copy per doubling into the bump arena, leaving the old arrays as dead space — final 64K×24B = 1.5MB PLUS all prior arrays ≈ 3MB needed > 2MB available.
- Operator m0442 deferred a scratch-arena optimization (per-module scratch reset / scratch 4MB / token array → module arena) to future investigation. This plan IS that investigation, broadened to a full-sweep data-structure audit.

**Key open question:** is 16MB even needed, or is the code wasting memory (copy-into-bump growth patterns, oversized collections, retained source text, over-interned strings) such that a smaller footprint would fit? The operator wants the metric to cover the code's data structures, not just the arena sizes (m0981-Q4).

## 3. Architecture

Three investigation tasks (I-M1, I-M2, I-M3), each read-only (no compiler source changes), each updating the memory-budget tech doc, producing a report. Combined STOP for operator ruling → a separate F-plan later.

**I-M1 — Peak map:** per-phase / per-arena peak memory during self-compile and representative examples, pinpointing the exact OOM and each phase's contribution.

**I-M2 — Full-sweep data-structure waste audit:** every growable collection in `sf/src/` and its growth strategy; quantify each overallocation with file:line and measured waste.

**I-M3 — Fix model:** per-fix savings, projected self-compile footprint, ranked recommendations.

## 4. Tasks

### 4.1 I-M1 — Per-phase / per-arena peak map

Measure `--track-memory --markers` output across the self-compile attempt (and representative examples) to map peak usage per phase (ImportResolution, TypeResolution, SemanticAnalysis, ComptimeEvaluation, LIRLowering, C89Emission) and per arena (perm/module/scratch). The `main.zig` phase markers (`"I\n"`, `"Z\n"`, etc.) plus `--track-memory` give the per-arena peaks at completion — but the OOM fires mid-import, so also instrument/narrow via smaller inputs and the per-module scratch behavior. Deliver a peak map + the precise OOM budget arithmetic.

### 4.2 I-M2 — Full-sweep data-structure waste audit

Enumerate every growable collection in `sf/src/` and its growth strategy. Known categories to audit:
- **Copy-into-bump growth** (geometric-doubling arrays allocated fresh via `sandAlloc`, old array dead): token array (`import_resolver.zig:16-26`), AST store nodes/children/extra_children (`ast.zig`), string interner (`string_interner.zig`), symbol tables, LIR instruction list, hoisted-temps list, type-registry items. Each wastes ~2× (sum of geometric sizes) in the bump arena.
- **Retained source text:** `source_manager.zig` + `readFile` — is each module's source copied into perm and never freed? Quantify the 1.3MB closure (MEM-era figure).
- **Oversized fixed buffers / static arrays:** e.g. `main.zig` per-phase stack buffers, `[256]u8` scratch, 4KB parser arena per module (`import_resolver.zig:48` — allocated fresh per module, never reused), etc.
- **Interner growth:** string interner dedup (good) vs. over-retention (strings interned for ephemeral names never needed later).
- **Duplicate data:** same name/type stored in multiple registries; copies where a reference would do.

For each: file:line, growth strategy, measured peak contribution (via `--track-memory` deltas or code-derived bounds), estimated waste. Rank by impact.

### 4.3 I-M3 — Fix model

For each waste identified in I-M2, compute the projected saving and the resulting self-compile footprint. Produce ranked recommendations, e.g.:
- Two-pass token counting (lex once to count, allocate exact-size array, lex again) OR per-module scratch reuse for the token array — removes the ~2× scratch waste.
- Reuse the per-module parser arena (`import_resolver.zig:48` 4KB×modules) instead of a fresh stack buffer per module.
- Reduce perm source-text retention (free per-module source after parse, or reference-file instead of copy).
- Growable/free-list allocator vs. pure bump for long-lived arrays.
- Static arena size reduction if measurements show headroom.

Deliver: projected self-compile peak RSS under each fix, and whether 16MB is achievable (and with how much margin) — or whether the budget itself needs re-examination.

## 5. Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — ⭐ SUBAGENT CHEAT-SHEET (lines 1-60). Copy exact commands.
- **Compiler under test:** `/tmp/fx_subfolder/zig1` (out_release WEDGED — use timeouts). Self-compile attempt: `mkdir -p DIR && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir DIR sf/src/main.zig`.
- **`--track-memory` requires `--markers`** (gated on `pal.markerWrite`, main.zig:239-258).
- **INVESTIGATION ONLY:** no compiler source changes. Tech docs updated with `[updated: 2026-08-14]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read before each edit; bottom-to-top). NO sed/python/bulk transforms.
- **The plan is the ONLY authority.** STOP on any issue.
- **I-tasks report then combined STOP for operator ruling.** No fixes in this plan.

## 6. Out of Scope

- **Any fixes** (separate F-plan after the ruling)
- Data-structure changes not directly tied to memory
- Code-quality refactors unrelated to memory
