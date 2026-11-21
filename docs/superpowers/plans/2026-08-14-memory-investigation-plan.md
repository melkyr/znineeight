# Compiler Memory / Allocation Investigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Investigate why zig1 can't self-compile under 16MB — measuring per-phase/per-arena peaks AND auditing the compiler's data structures for waste/overallocation. Investigation-only; fixes land in a separate plan after the operator ruling.

**Architecture:** 3 batched I-tasks (I-M1 peak map, I-M2 full-sweep waste audit, I-M3 fix model), each read-only + tech-doc update, then combined STOP.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`/tmp/fx_subfolder/zig1`), `--track-memory --markers`, arena machinery (`allocator.zig`), tech docs (`sf/docs/tech_docs/*.md`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `/tmp/fx_subfolder/zig1`. **`sf/build/out_release/` is WEDGED — any command touching it HANGS; use explicit timeouts on ALL such commands. Never touch out_release.**
- **Self-compile attempt:** `mkdir -p DIR && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir DIR sf/src/main.zig 2>/tmp/err` — known OOM: `OOM: used=1899216 new=3472080 total=2097152` (scratch 2MB) during phase_ImportResolution.
- **`--track-memory` WORKS only with `--markers`** (gated on `pal.markerWrite`, main.zig:239-258). Prints `track-memory: perm=XK mod=XK scr=XK total=XK`.
- **INVESTIGATION ONLY:** zero `sf/src/*.zig` changes. Each I-task updates its covering tech doc (`[updated: 2026-08-14]`) + writes a report.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms.
- **The plan is the ONLY authority.** STOP on any issue.
- **I-tasks report then combined STOP for operator ruling.** No F-tasks in this plan.

---

### Task I-M1: Per-phase / per-arena peak map

**Files:**
- Investigate: `sf/src/main.zig` (phase markers + track-memory), `sf/src/allocator.zig` (arena machinery)
- Modify (docs): the memory-budget tech doc (check `sf/docs/tech_docs/INDEX.md` — `00_shared_infra.md` carried the arena-sizing note)
- Report: `.superpowers/sdd/I-M1-peakmap-report.md`

**Interfaces:**
- Consumes: MEM1/MEM2/MEM3 reports (`.superpowers/sdd/MEM*-report.md`), current arenas (perm 4M/mod 8M/scr 2M).
- Produces: a per-phase/per-arena peak map + the exact OOM budget arithmetic.

**Context:** The OOM fires mid-import (phase_ImportResolution) at scratch 2MB. `--track-memory --markers` prints the final per-arena peaks but never reaches the print (dies in import). I-M1 must build the peak map despite that.

- [ ] **Step 1: Read the phase + memory machinery**

Read `sf/src/main.zig` phase markers (search `markerWrite` for the `"I\n"`/`"Z\n"`/etc. phase markers), the `--track-memory` block (:239-258), and `sf/src/allocator.zig` arena semantics (bump, `sandReset`, `sandResetPeak`, `checkCombinedPeak`). Read the MEM1/MEM2/MEM3 reports for the prior measurements.

- [ ] **Step 2: Measure per-phase peaks on achievable inputs**

Since self-compile OOMs mid-import, build the peak map incrementally: run `--track-memory --markers` on single modules and small multi-module inputs that COMPLETE, recording perm/mod/scr peaks. Use the module-hash-named emitted-C phases as the delimiter. Collect peaks for: hello, a mid-size multi-module example, and the largest single module that completes (if c89_emit.zig OOMs scratch standalone, note that; use the next-largest that completes).

- [ ] **Step 3: Characterize the import-phase scratch behavior**

Read `import_resolver.zig:83-115` (`moduleRegistryResolveImports` — `sandReset(scratch)` per module at :90, `readFile(path, scratch)` :96, `moduleRegistryParseModule` :107). Confirm: source text read into scratch per module, token array grown in scratch (doubling), parser arena `[4096]u8` stack buffer per module (:48), then scratch reset per module. Quantify the single-module scratch demand for the largest file (c89_emit.zig) from the token-array growth (final 64K tokens × 24B = 1.5MB + prior arrays) and confirm the 2MB budget math.

- [ ] **Step 4: Produce the peak map + OOM arithmetic**

Table: phase | perm peak | module peak | scratch peak | total. Plus: the precise arithmetic of why 2MB scratch OOMs on the largest file, and what scratch budget the largest file needs under the CURRENT (wasteful) token-array growth.

- [ ] **Step 5: Update the tech doc**

Memory-budget doc: current arena sizes, measured peaks, OOM arithmetic, `[updated: 2026-08-14]`.

- [ ] **Step 6: Write the report** `.superpowers/sdd/I-M1-peakmap-report.md`.

**Gate:** per-phase/per-arena peak map produced (even if partial for the OOM'd self-compile); OOM budget arithmetic exact; tech doc updated; no compiler source changes.

---

### Task I-M2: Full-sweep data-structure waste audit

**Files:**
- Investigate: all of `sf/src/*.zig` for growable collections
- Modify (docs): memory-budget tech doc
- Report: `.superpowers/sdd/I-M2-wasteaudit-report.md`

**Interfaces:**
- Consumes: I-M1 peak map (which arenas/phases dominate), the known token-array copy-into-bump pattern (`import_resolver.zig:16-26`).
- Produces: a full inventory of growable collections, each with growth strategy, file:line, measured/derived waste.

**Context (operator m0981-Q4):** the metric must cover the code's data structures, not just arena sizes. The token-array doubling is confirmed waste; suspect the same pattern across AST store, symbol tables, LIR, hoisted temps, interner, type registry, source retention.

- [ ] **Step 1: Catalog every growable collection**

Read each `sf/src/*.zig` for array-like growth (`items/len/cap` patterns, `sandAlloc`-fed arrays, geometric doubling). Build a table: collection | file:line | growth strategy | arena (perm/module/scratch) | peak contribution (from I-M1 or code-derived).

Minimum audit set:
- Token array (`import_resolver.zig:16-26`)
- AST store nodes/children/extra_children (`ast.zig`)
- String interner (`string_interner.zig`)
- Symbol tables / type registry (`symbol_registrator.zig`, `type_registry.zig`)
- LIR instruction list / hoisted temps (`lower.zig`, `lir.zig`)
- Module registry / import queue (`module_registry.zig`, `import_resolver.zig`)
- Source manager (`source_manager.zig`)
- Diagnostic collector (`diagnostics.zig`)
- Dep graph / layout edges (`type_resolver.zig`)
- Per-module parser arena (`import_resolver.zig:48` — stack buffer per module, never reused)
- Fixed stack buffers (`[256]u8`, `[4096]u8`, etc.)
- Retained source text in perm (MEM-era 1.3MB closure)

- [ ] **Step 2: Quantify waste per collection**

For each copy-into-bump collection, the waste factor is ~2× (sum of geometric array sizes N + N/2 + N/4 + ... ≈ 2N, old arrays dead in the bump arena). For source retention: how much source text is copied into perm vs. referenced? For stack buffers: how many are allocated per-module/loop and could be reused?

- [ ] **Step 3: Rank by impact + flag low-hanging fruit**

Order by projected saving in the self-compile path (scratch > module > perm for the OOM, but check all). Flag the "low-hanging fruit" (operator m0985: full sweep, optimizations on every part).

- [ ] **Step 4: Update the tech doc** (memory-budget doc, `[updated: 2026-08-14]`).
- [ ] **Step 5: Write the report** `.superpowers/sdd/I-M2-wasteaudit-report.md`.

**Gate:** every growable collection in `sf/src/` cataloged with file:line + growth strategy + quantified waste; ranked by impact; tech doc updated; no compiler source changes.

---

### Task I-M3: Fix model + projected footprint

**Files:**
- Investigate: I-M1 + I-M2 outputs (no new source reads beyond verification)
- Modify (docs): memory-budget tech doc
- Report: `.superpowers/sdd/I-M3-fixmodel-report.md`

**Interfaces:**
- Consumes: I-M1 peak map, I-M2 waste audit.
- Produces: per-fix savings, projected self-compile peak RSS, ranked recommendations.

**Context:** The deliverable must answer: can self-compile fit in 16MB, and with how much margin — under which fixes?

- [ ] **Step 1: Model each candidate fix**

For each I-M2 finding, compute the projected saving (arena bytes) and the fix complexity. Candidate fixes to cost out:
- Two-pass token counting (exact-size array, no doubling waste) OR per-module scratch reuse of the token array
- Reuse the per-module parser arena instead of a fresh 4KB stack buffer
- Free/reference per-module source text after parse (reduce perm retention)
- Grow-in-place (`sandReallocInPlace`, allocator.zig:55-65) where the old array is arena-tail — or restructure so it is
- Overallocation caps: shrink module arena if the map shows it's oversized at 8MB; grow scratch only if unavoidable
- Interner hygiene if over-retention is found

- [ ] **Step 2: Project the self-compile footprint**

Sum the savings into the I-M1 peak map → projected self-compile peak RSS under: (a) no fixes (current), (b) each fix individually, (c) the recommended fix set. State whether 16MB is achieved and the margin.

- [ ] **Step 3: Rank + recommend**

Order fixes by (saving ÷ complexity). Recommend a fix set for the future F-plan. Flag anything where the 16MB budget itself needs re-examination (e.g., if the code is genuinely minimal and 16MB is too tight).

- [ ] **Step 4: Update the tech doc** (`[updated: 2026-08-14]`).
- [ ] **Step 5: Write the report** `.superpowers/sdd/I-M3-fixmodel-report.md`.

**Gate:** per-fix savings computed; projected self-compile footprint under current + recommended; 16MB verdict with margin; ranked recommendations; tech doc updated; no compiler source changes.

---

**Report back — combined STOP for operator ruling** (all 3 I-M reports, one ruling). The ruling picks the F-plan scope.
