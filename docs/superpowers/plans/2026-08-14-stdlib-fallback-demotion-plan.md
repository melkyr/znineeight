# Std-Lib Fallback Demotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Demote two latent un-scoped type-resolution fallbacks (D2-class module-0-first `(mi<<32)|name` scans) and route them through the upstream module-scoped paths added in the std-lib closeout F1 fix. Closes the final-review follow-up "latent parallel fallback".

**Architecture:** R (repro attempt, batched both loci) → F (fix both loci) → F-GATE (sweep + reconciliation). STOP for a ruling if R surfaces a design fork (e.g. const-alias "current module" semantics).

**AMENDMENT 1 (2026-08-14, operator Option A — root-cause fix):** Task R found locus 1 (`semantic_analyzer.zig:774-785`) is DEAD code, and the REAL bug is a systemic bare-name-cache-key == module-0-scoped-key collision (`type_registry.zig:630` primitives under bare `nid`; `:634-648` module-0 named types under `(0<<32)|name_id == nid`). The F-task scope expands to fix the root cause across 4 sites: (1) reorder `resolveTypeExprFull` current-module-first before bare; (2) scope `symbol_registrator.zig:263`; (3) scope `const_alias_prepass.zig:164-172` (alias declaring module); (4) remove dead `semantic_analyzer.zig:774-785`.

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

### Task F: Fix the root cause (module-scope bare type resolution across 4 sites)

**Files:**
- Modify: `sf/src/type_resolver.zig`, `sf/src/symbol_registrator.zig`, `sf/src/const_alias_prepass.zig`, `sf/src/semantic_analyzer.zig`.
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md` (type_resolver + const_alias_prepass), `sf/docs/tech_docs/05_semantic_analysis.md` (semantic_analyzer + symbol_registrator).
- Test: repros from Task R; `arena_multi_inst_xmod`; 4 MD5 gates; corpus.

**Context (AMENDMENT 1, Option A):** The systemic root cause is that the bare name-cache key (`nid`) collides with module-0's scoped key (`(0<<32)|name_id == name_id`). `resolveTypeExprFull` STEP 1 (`type_resolver.zig:678`) does a bare `nameCacheGet` before the current-module lookup, so bare type references resolve module-0-first. The fix reorders current-module-first and scopes the sibling sites.

- [ ] **Step 1 (`type_resolver.zig:673-692`):** reorder the `ident_expr` arm so the current-module scoped lookup (`:682-686`) runs BEFORE the bare `nameCacheGet` (`:678`). Bare lookup becomes the primitive fallback (second), then the all-modules scan (`:687-692`). Preserve the symbol-lookup tiers (`:694-711`) unchanged.
- [ ] **Step 2 (`symbol_registrator.zig:263`):** scope the `nameCacheGet(type_reg, ident_name_id)` lookup — try `(mod_id<<32)|ident_name_id` (current module) first, then bare (primitive) fallback.
- [ ] **Step 3 (`const_alias_prepass.zig:164-172`):** insert `if (nameCacheGet(registry, (@intCast(u64, mod_id) << 32) | @intCast(u64, dep_name))) |tid| { resolved = tid; }` before the module-0-first `while` scan (alias's declaring module = `mod_id`); keep bare-name + `resolveWellKnownTypeName` fallbacks.
- [ ] **Step 4 (`semantic_analyzer.zig:770-792`):** delete the dead `if (rn.kind == ident_expr) { manual scan } else { ... }` special-case; always call `resolveTypeExprFull` with `.module_id = s.module_id`. Remove now-unused locals cleanly.
- [ ] **Step 5: Rebuild** zig1 (`build_release.sh`, reinstall std lib).
- [ ] **Step 6: Verify** Task R repros GREEN (`r_fallback_fnret`, `r_fallback_constalias`, `r_fallback_constalias_prepass` now compile/run correctly; `r_fallback_fnret_ctl` still `20`); `arena_multi_inst_xmod` run rc=0 prints `0`; 4 MD5s byte-identical; corpus 248 dirs no regression.
- [ ] **Step 7: Update tech docs** (`[updated: 2026-08-14]`).
- [ ] **Step 8: Commit**
```bash
git add sf/src/type_resolver.zig sf/src/symbol_registrator.zig sf/src/const_alias_prepass.zig sf/src/semantic_analyzer.zig sf/docs/tech_docs/03_type_resolution.md sf/docs/tech_docs/05_semantic_analysis.md
git commit -m "fix: module-scope bare type resolution (bare-key/module-0-key collision)"
```

**Gate:** all 4 sites fixed; repros GREEN; `arena_multi_inst_xmod` GREEN; 4 MD5s byte-identical; corpus no new FAIL; tech docs updated.

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
