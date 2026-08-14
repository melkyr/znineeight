# Std-Lib Fallback Demotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Demote two latent un-scoped type-resolution fallbacks (D2-class module-0-first `(mi<<32)|name` scans) and route them through the upstream module-scoped paths added in the std-lib closeout F1 fix. Closes the final-review follow-up "latent parallel fallback".

**Architecture:** R (repro attempt, batched both loci) → F (fix both loci) → F-GATE (sweep + reconciliation). STOP for a ruling if R surfaces a design fork (e.g. const-alias "current module" semantics).

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), zig1 (`/tmp/fx_subfolder/zig1`), gcc -m32 C89, tech docs (`sf/docs/tech_docs/*.md`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `/tmp/fx_subfolder/zig1`. **`sf/build/out_release/` is WEDGED — any command touching it HANGS; use explicit timeouts on ALL such commands. Never touch out_release.** Rebuild: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: /tmp/fx_subfolder/zig1 ===`. Reinstall std lib after rebuild: `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **4 MD5 gates byte-identical** (post-F3 AMENDMENT B re-baseline, runtime-identity proof): gol `9cf758d96f25d41980379564a5501bc8`, lisp `524d2872daefb2677c8ddc1ac8f34cf5`, json `066c99974f6052317636854dc4c2a2d5`, mud `a1d0dd55aada9c3fd904ae33f54de32e` (mud NOT a hard gate).
- **Corpus:** 248 dirs, OK=242/FAIL=2/GG=4. FAIL must not increase. FAIL=2 = field_store_drop, self_embed_optional_cycle.
- **RUNTIME gate mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print expected output. Compile-only gates FORBIDDEN.
- **Tech-doc maintenance (AGENTS §1.1.1):** every source-changing F-task updates the covering tech doc — `[updated: 2026-08-14]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present.
- **STOP on any design fork** surfaced during R (e.g. which module is "current" for a const-alias dep) — present to the operator, do not assume.

---

### Task R: Repro attempt for both un-scoped fallbacks

**Files:**
- Investigate (read-only): `sf/src/semantic_analyzer.zig:770-792`, `sf/src/const_alias_prepass.zig:153-187`.
- Create (if reachable): `repro/mi_matrix/<name>/` repro dirs.
- Report: `.superpowers/sdd/task-R-fallback-repro-report.md`

**Context:** Two latent D2-class un-scoped scans remain:
1. `semantic_analyzer.zig:770-792` (`semanticAnalyzerResolveFnCall`): when a fn call's return-type node is missing from the resolved-type table, the `ident_expr` branch (774-785) does a manual module-0-first name-cache scan instead of `resolveTypeExprFull`.
2. `const_alias_prepass.zig:164-172` (`constAliasPrepass` Phase-2 seed): bare name-cache miss → module-0-first scan (`while cmi < tables_len`).

Both may be MASKED post-F1 (`resolveFnSignatures` pre-populates the table for locus 1; locus 2 is an active phase at `main.zig:323`).

- [ ] **Step 1: Determine reachability of locus 1.** Can a program still hit `semanticAnalyzerResolveFnCall`'s `resolvedTypeTableGet` miss? If yes, construct a RED repro (module-instance ≥1 fn whose return type is a bare `ident_expr`); if the table is always pre-populated, record "latent, unreachable" with evidence.
- [ ] **Step 2: Determine reachability of locus 2.** Can a cross-module const-alias prepass resolve a bare type name to the WRONG (lower-index) module? Construct a RED repro if possible (module A defines `Foo`, higher-index module B does `pub const Bar = Foo;` with another `Foo` in a lower-index module). If the alias seed always resolves correctly, record "latent".
- [ ] **Step 3: Write the report** with exact loci (file:line), reachability verdict per locus, RED evidence (or "unreachable" justification), and any design fork requiring an operator ruling.

**Gate:** reachability determined for both loci; RED repro where reachable; report written. **STOP for operator ruling if a design fork surfaced.**

---

### Task F: Fix both fallbacks (route through upstream module-scoped path)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig`, `sf/src/const_alias_prepass.zig`.
- Modify (docs): `sf/docs/tech_docs/05_semantic_analysis.md` (locus 1), `sf/docs/tech_docs/03_type_resolution.md` (locus 2).
- Test: repros from Task R; `arena_multi_inst_xmod`; 4 MD5 gates; corpus.

**Context:** Locus 1's `else` branch already calls `resolveTypeExprFull` with `.module_id = s.module_id` (callee's module — correct, return type is defined there). The fix collapses the `ident_expr` special-case into that same call. Locus 2's fix inserts a current-module-first check before the module-0-first scan.

- [ ] **Step 1 (locus 1):** In `semantic_analyzer.zig:770-792`, delete the `if (rn.kind == ident_expr) { manual scan } else { ... }` special-case; always call `resolveTypeExprFull` with `.module_id = s.module_id`. Remove the now-unused locals (`rn`, `brnk_m`, `rnid`, `nc`, `mti`, `nck`) cleanly.
- [ ] **Step 2 (locus 2):** In `const_alias_prepass.zig:164-172`, insert `if (nameCacheGet(registry, (@intCast(u64, mod_id) << 32) | @intCast(u64, dep_name))) |tid| { resolved = tid; }` before the module-0-first `while` scan; keep the bare-name + `resolveWellKnownTypeName` fallbacks.
- [ ] **Step 3: Rebuild** zig1 (`build_release.sh`, reinstall std lib).
- [ ] **Step 4: Verify** repro GREEN where applicable; `arena_multi_inst_xmod` run rc=0 prints `0`; 4 MD5s byte-identical; corpus 248 dirs no regression.
- [ ] **Step 5: Update tech docs** (`[updated: 2026-08-14]`).
- [ ] **Step 6: Commit**
```bash
git add sf/src/semantic_analyzer.zig sf/src/const_alias_prepass.zig sf/docs/tech_docs/05_semantic_analysis.md sf/docs/tech_docs/03_type_resolution.md
git commit -m "fix: route un-scoped type-resolution fallbacks through module-scoped path"
```

**Gate:** both loci fixed; repro GREEN / no-regression; 4 MD5s byte-identical; corpus no new FAIL; tech docs updated.

---

### Task F-GATE: Gate sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md` (if a repro was added).
- Report: `.superpowers/sdd/task-F-GATE-fallback-report.md`

- [ ] **Step 1: Corpus sweep (248 dirs) + test_analyzer_bin** — no new FAIL; OK=242/FAIL=2/GG=4 unchanged (unless a repro dir was added → 249 dirs, and it classifies OK).
- [ ] **Step 2: 4 MD5 gates** byte-identical.
- [ ] **Step 3: Docs reconciliation** — EXPECTED_FAIL.md version bump + record if a repro landed; QUICK_REF baseline update.
- [ ] **Step 4: Commit**
```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: fallback-demotion gate sweep + reconciliation"
```

**Gate:** corpus no regression; 4 MD5s byte-identical; docs consistent.
