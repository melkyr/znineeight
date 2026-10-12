# Std-Lib Search Path (`@import("std")`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `@import("std")` resolve through a search path (CLI `-I`/`--lib-dir` + compiler-binary-relative default install path), eliminating ~19 duplicated std lib copies. Win9x-primary portability. Migrate examples + repros to bare `@import("std")`.

**Architecture:** R (repro) → I (resolver + install-path practice investigation) → combined STOP → F (search-path + CLI + default path + resolution) → F-migration (21 examples + ~47 repros) → F-gate sweep.

**Tech Stack:** Z98 compiler (`sf/src/module_registry.zig`, `import_resolver.zig`, `main.zig`), zig1 (`/tmp/fx_subfolder/zig1`), std lib (`sf/src/std*.zig`), gcc -m32 C89, tech docs (`sf/docs/tech_docs/*.md`).

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **Compiler under test:** `/tmp/fx_subfolder/zig1`. **`sf/build/out_release/` is WEDGED — any command touching it HANGS; use explicit timeouts on ALL such commands. Never touch out_release.**
- **Win9x-PRIMARY (operator m0983):** the default install-path resolution MUST be portable to MSVC6/OpenWatcom (argv[0]/executable-dir derivation, no POSIX-only APIs, forward/backslash tolerant). **Linux is a side effect.** Flag any non-portable assumption for operator review at the ruling.
- **Search-path order:** user `-I`/`--lib-dir` dirs (CLI order) FIRST, then the compiler-default install path.
- **4 MD5 gates byte-identical** UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B): gol `ff47d18dc8ef00e9b8f92f5e0a14c34a`, lisp `c1cb748b423eef191b9c9ce7023ae2a0`, json `376fd6812ef751913bdad00de676ceb6`, mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT a gate). **Migration re-baselines are EXPECTED** (import path IDs / module hashes change) — operator-approved if runtime-identical.
- **Corpus:** 246 dirs, OK=239/FAIL=3/GG=4. FAIL must not increase. FAIL=3 = field_store_drop, test_stub_0, self_embed_optional_cycle.
- **RUNTIME gate mandatory** (AGENTS §2.5.3): every migrated example/repro must run rc=0 AND print the expected output.
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task updates the covering tech doc — `[updated: 2026-08-14]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present.
- **I-tasks report then STOP for combined operator ruling.** F-tasks do NOT start until the ruling.

---

### Task R: Repro — bare `@import("std")` fails

**Files:**
- Create: `repro/mi_matrix/std_import_bare_xmod/{main.zig,std.zig,std_io.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R-searchpath-report.md`

**Interfaces:**
- Consumes: the D1 gap (bare `@import("std")` unresolved; local copies required today).
- Produces: a reproducible RED gate for the I/F tasks.

**Context:** `@import("std")` (bare module name) currently fails to resolve — the resolver handles relative paths / registered names, not a search path. The repro exercises the bare import and documents the failure.

- [ ] **Step 1: Write the repro**

`repro/mi_matrix/std_import_bare_xmod/main.zig`:
```zig
const std = @import("std");

pub fn main() void {
    std.io.printInt(@intCast(i32, 42));
}
```
Include a local `std.zig` + `std_io.zig` (io-only, from `union_literal_nested_xmod`) **in a subdirectory NOT on any path** (e.g. `repro/mi_matrix/std_import_bare_xmod/local/`) so the bare import cannot fall back to a sibling — the repro must prove the bare-name resolution fails WITHOUT a local sibling, and that a `-I`/`--lib-dir` pointing at `local/` makes it succeed. NOTES.md documents the two-state test (no flag → fails; with `--lib-dir local/` → succeeds, proving the search-path mechanism is the fix).

- [ ] **Step 2: Verify RED**

`/tmp/fx_subfolder/zig1 --dump-c89 repro/mi_matrix/std_import_bare_xmod/main.zig > /tmp/r.c 2>/tmp/r.err; echo "rc=$?"` — expected rc≠0 (unresolved `@import("std")`, error[2000]-class). Record the exact error.

- [ ] **Step 3: Verify the `--lib-dir` hypothesis (even though the flag doesn't exist yet)**

Note: the flag is NOT implemented yet — this step documents the EXPECTED post-fix behavior only. Skip actual execution if the flag is absent; record the expectation in NOTES.md.

- [ ] **Step 4: Write NOTES.md + report + commit**

```bash
git add repro/mi_matrix/std_import_bare_xmod/
git commit -m "repro: bare @import(std) unresolved without search path (std_import_bare_xmod)"
```

**Gate:** RED reproduced (unresolved bare import, exact error recorded); NOTES.md documents the search-path mechanism + expected post-fix behavior; committed.

---

### Task I: Investigation — resolver + install-path practice

**Files:**
- Investigate: `sf/src/module_registry.zig` (`moduleResolverResolve` :144, `joinPath` :109), `sf/src/import_resolver.zig`, `sf/src/main.zig` (CLI parsing + entry-module registration), `sf/src/pal.zig` (path/executable helpers)
- Modify (docs): covering tech doc (check INDEX.md — `07_lir_lowering.md` covers import resolution or `00_shared_infra.md`)
- Report: `.superpowers/sdd/I-searchpath-report.md`

**Interfaces:**
- Consumes: R repro, the D1 gap.
- Produces: exact resolver mechanism, install-path recommendation (Win9x-portable), tech-doc update, fix recommendation for the ruling.

**Context:** Bare `@import("std")` must resolve against a search path. The right practice (operator m0983): CLI `-I` dirs + compiler-binary-relative default install path — like standard compilers. Win9x is primary; Linux is a side effect.

- [ ] **Step 1: Read the current resolver**

`sf/src/module_registry.zig` `moduleResolverResolve` (:144) + `joinPath` (:109): how is an import path resolved today (relative to importer? lib dir?). `import_resolver.zig` `moduleRegistryParseModule`/`moduleRegistryResolveImports`. `main.zig` CLI parsing (where flags are read) + how the entry module is registered. Report exactly where a search-path list would plug in.

- [ ] **Step 2: Check zig0's std-relative resolution**

Read the zig0 oracle's import resolution (in `examples/zig0/*` or the compiler's zig0-era source) — how does it resolve the std lib / modules by name? Cross-check `src/runtime` references. Extract the practice zig1 should mirror.

- [ ] **Step 3: Determine the Win9x-portable install-path mechanism**

The default path must resolve relative to the compiler binary on Win9x. Options to evaluate (report each + recommendation):
- argv[0]-relative: derive `<bindir>/../lib/` from argv[0] — simplest, portable, but argv[0] may be relative/absent.
- GetModuleFileName (Win) / /proc/self/exe (Linux) — non-portable to Win9x in the POSIX sense; Win9x has GetModuleFileName. Evaluate what's truly portable to MSVC6/Watcom.
- A compile-time baked path (configured at build time via a `-D`-style macro or a config const) — matches the `host_is_windows` config-const pattern (closeout plan F2).
- Recommendation must be Win9x-primary; Linux is a side effect (document the Linux mechanism as best-effort).

- [ ] **Step 4: Update the tech doc**

Document the current resolver behavior, the D1 gap, the recommended search-path design, `[updated: 2026-08-14]`. No compiler code changes.

- [ ] **Step 5: Write the report** `.superpowers/sdd/I-searchpath-report.md` — resolver plug-in point, zig0 practice, Win9x-portable install-path recommendation, blast radius (migration scope: ~19 copies, 21 examples, ~47 repros), fix options.

**Gate:** resolver mechanism documented with file:line; zig0 practice extracted; Win9x-portable default-path recommendation made; blast radius assessed; tech doc updated. No compiler code changes.

**Report back — combined STOP for operator ruling on F (search-path design + install-path mechanism + migration scope).**

---

### Task F: Search path + CLI flag + default path + resolution

**Files:**
- Modify: `sf/src/module_registry.zig` (search-path list, bare-name resolution), `sf/src/main.zig` (CLI `-I`/`--lib-dir` parsing + default-path init), possibly `sf/src/import_resolver.zig` (pass search paths), `sf/src/pal.zig` (executable-dir helper)
- Modify (docs): covering tech doc
- Test: `std_import_bare_xmod/` (RED → GREEN with `--lib-dir local/` AND with the default path)

**Interfaces:**
- Consumes: I ruling, R repro.
- Produces: `@import("std")` resolves via user `-I` dirs then the default install path.

- [ ] **Step 1: Implement per I ruling** — search-path list in the resolver; `-I`/`--lib-dir` CLI parsing (repeatable); default install-path resolution at init (Win9x-portable per ruling); bare-name → `std.zig` in each dir.
- [ ] **Step 2: Build + verify repro GREEN:** `std_import_bare_xmod` with `--lib-dir <local>` resolves + runs rc=0 printing `42`. Also verify WITHOUT the flag but with a std lib at the DEFAULT install path: resolves + runs.
- [ ] **Step 3: Verify 4 MD5 gates** (no migration yet — resolver addition should be byte-neutral for relative-path imports; verify no gate emitted-C change)
- [ ] **Step 4: Verify corpus no new FAIL**
- [ ] **Step 5: Update tech doc to FIXED**
- [ ] **Step 6: Commit**
```bash
git add sf/src/module_registry.zig sf/src/main.zig <...> sf/docs/tech_docs/<covering>
git commit -m "feat: @import search path with -I/--lib-dir + default install path"
```

**Gate:** repro GREEN via flag AND default path; 4 MD5s byte-identical (no migration yet); corpus no new FAIL; tech doc updated.

---

### Task F-MIGRATE: Migrate examples + repros to bare `@import("std")`, delete local copies

**Files:**
- Modify: 21 `examples/z98/*/` .zig sources (replace `@import("std.zig")`-style locals with `@import("std")`), ~47 `repro/mi_matrix/*/` .zig sources
- Delete: ~19 local `std.zig`/`std_io.zig`/`std_arena.zig`/`std_net.zig` copies (keep one canonical set in the std install path)
- Report: `.superpowers/sdd/task-F-MIGRATE-report.md`

**Interfaces:**
- Consumes: F (search path working), I blast-radius list.
- Produces: all examples + repros use bare `@import("std")`; local copies deleted.

**Context:** Every example/repro currently ships local std copies (post-F4 convention). With the search path resolving `@import("std")`, the copies are removable. The canonical std lib lives at the default install path.

- [ ] **Step 1: Enumerate the copies + import sites**

`find examples repro -name 'std.zig' -o -name 'std_io.zig' -o -name 'std_arena.zig' -o -name 'std_net.zig'` → the ~19 trees. `grep -rn '@import("std' examples repro` → the import sites (some use `std.zig` local name, some `std`). Categorize: which use the `std` name vs a local name.

- [ ] **Step 2: Migrate the examples**

21 examples: replace local std imports with `@import("std")`. Where an example's std needs more than the canonical root (e.g. arena/net), verify the canonical std.zig re-exports cover it (the canonical root re-exports io+arena+net — verify) or keep a documented minimal local root if the canonical set doesn't match (report the deviation for operator note).

- [ ] **Step 3: Migrate the repros**

~47 repros: same replacement. The `io`-only repros map to `@import("std")` + `std.io`. Verify each migrated repro still dumps/compiles/links/runs with the expected output (RUNTIME gate).

- [ ] **Step 4: Delete the local copies**

Remove the ~19 `std*.zig` trees from examples/repro dirs once all importers are migrated.

- [ ] **Step 5: Verify gates**

4 MD5 gates (re-baseline EXPECTED — module hashes change with import path; runtime-identical proof per AMENDMENT B). Corpus no new FAIL. 21-example matrix + representative repros run rc=0.

- [ ] **Step 6: Update docs** (EXPECTED_FAIL migration record, tech doc, QUICK_REF)
- [ ] **Step 7: Commit**
```bash
git add examples/ repro/ <docs>
git commit -m "refactor: migrate examples+repros to @import(std) search path, remove local std copies"
```

**Gate:** all examples + repros use bare `@import("std")`; ~19 copies deleted; 4 MD5s re-baselined with runtime proof; corpus no new FAIL; docs updated.

---

### Task F-GATE: Gate sweep + full reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, covering tech docs
- Report: `.superpowers/sdd/task-F-GATE-searchpath-report.md`

**Interfaces:**
- Consumes: F + F-MIGRATE.
- Produces: final manifest reflecting post-search-path state.

- [ ] **Step 1: Full 21-example matrix**
- [ ] **Step 2: 4 MD5 gates (post-migration baselines)**
- [ ] **Step 3: Corpus sweep + test_analyzer_bin PASS**
- [ ] **Step 4: EXPECTED_FAIL.md version bump + search-path record; QUICK_REF baseline**
- [ ] **Step 5: Commit**
```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md <tech docs>
git commit -m "docs: search-path gate sweep + reconciliation"
```

**Gate:** 21/21 matrix; 4 MD5s verified (re-baselined with runtime proof); corpus no new FAIL; EXPECTED_FAIL + QUICK_REF + tech docs consistent.
