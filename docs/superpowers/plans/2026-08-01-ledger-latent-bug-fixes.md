# Ledger Latent Bug Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Fix 4 latent bugs identified during multi-module C89 emission review: basename collision (silent output overwrite), closure edge model (tstIsDep under-closed), Win32 handle truncation, and missing/empty file silent failure.

**Architecture:** 4 I-M research tasks → 4 F-S fix tasks → 1 F-D doc task. Each I-task produces a report with exact edit targets. Each F-task implements one bug fix. F-D updates docs.

**Tech Stack:** zig1 binary at `sf/build/out_release/zig1`, z98-compatible Z98 for source edits, GDB/fprintf for evidence.

**Strict-C89 fwd-decl (ledger item #2) DROPPED — confirmed NOT a bug.** The fwd-decl pass emits `typedef struct X X;` while the guarded pass emits `struct X { ... };` (no `typedef`), no redeclaration conflict. Both coexist even under `-std=c89 -pedantic-errors`. Target compilers MSVC 6 / OpenWatcom accept this pattern. Verified by research 2026-08-01.

## Required Reading (for every subagent)

| Doc | Role | Key sections |
|-----|------|--------------|
| `sf/src/c89_emit.zig` | Emission core | BufferedWriter (:27), C89Emitter (:457), tstIsDep (:832), computeSharedSet (:923), emitSharedHeader (:983), emitModuleHeaderFile (:1841), emitModuleFile (:2038) |
| `sf/src/main.zig` | Pipeline orchestration | parseArgs (:744), phase_C89Emission (:604), output_dir_set (:62) |
| `sf/src/pal.zig` | PAL wrappers | fileOpen (:70), fileWrite (:82), fileClose (:86), readFile (:19) |
| `sf/src/include/zig_pal.c` | C PAL implementation | pal_file_open (:181), pal_file_write (:192), pal_file_close (:207), PlatFile typedef (:16-21) |
| `sf/src/type_resolver.zig` | Type classification | classifyTypeEmissionGroups, fieldEmbedsByValue (:323-330) |
| `sf/src/import_resolver.zig` | Module resolution | readFile null handler (:94-99) |
| `sf/src/module_registry.zig` | Module registry | resolveImport (:263), fileExists gate (:144-161), diag (:171) |
| `sf/src/diagnostics.zig` | Error codes | ErrorCode enum (:10-67), Add (:250-284), HasErrors (:286-288) |
| `.superpowers/sdd/IM7-report.md` | IM7 research | §D exact edit targets, Option B naming scheme |
| `.superpowers/sdd/IM8-report.md` | IM8 research | §D fix list for 5 functions, repros §A5 |
| `.superpowers/sdd/IM8-assessment.md` | IM8 verification | independent verify, D5 required, tstEdgesFill dead |
| `.superpowers/sdd/IM9-report.md` | IM9 research | §D type chain, byte-identity cmd §D:11 |
| `.superpowers/sdd/IM10-report.md` | IM10 research | §D 3 edit sites, ERR_3048, exit codes |
| `sf/docs/tech_docs/08_c89_emission.md` | As-built evidence | §6.1 typedef topo order, §6.8 computeSharedSet, basename+path sections |
| `sf/docs/tech_docs/09_pipeline_orchestration.md` | As-built evidence | phase_C89Emission loop, --output-dir, parseArgs |
| `sf/docs/tech_docs/00_shared_infra.md` | As-built evidence | PAL exports, string interner, arena allocator |
| `sf/docs/tech_docs/03_type_resolution.md` | As-built evidence | TypeId→module mapping, pointer-only classification |
| `sf/docs/tech_docs/01_import_resolution.md` | As-built evidence | ModuleEntry, import_edges, failed state |
| `sf/docs/tech_docs/10_c_runtime.md` | As-built evidence | zig_pal.c exports, PlatFile |
| `docs/sf/QUICK_REF.md` | Gate recipes | Build+run commands, md5 baselines |

## Global Constraints

- **Source changes allowed** — this plan MODIFIES `sf/src/c89_emit.zig`, `sf/src/main.zig`, `sf/src/pal.zig`, `sf/src/include/zig_pal.c`, `sf/src/type_resolver.zig`, `sf/src/import_resolver.zig`, `sf/src/module_registry.zig`, `sf/src/diagnostics.zig`, and related doc files
- **I-tasks are RESEARCH ONLY** — zero code changes, reports are the deliverables. NO Python/sed/awk file-write scripts. Unauthorized modifications are reverted (enforced 2026-08-01)
- **F-S tasks are the implementation** — each F-S consumes its corresponding I-M report + assessment report
- **Byte-identical stdout gate PRESERVED** — bare `--dump-c89` on mud/gol/lisp/json must produce same md5s as QUICK_REF: mud `5fb57e70c2d637276ab0264c1401cd0d`, gol `f855c9f93c73422f56378f3f73231727`, lisp `0ad0204088f91c1eae7c040da8f99a1c`, json `11a5db1d3d43acf4880e2d157590abe3`
- **Corpus gate:** 164/20/6/0 baseline preserved (zero emission regression)
- **Runtime gate:** all 15 working examples build+link+run correctly
- **fastedit/edit only for source edits** — per AGENTS.md §X.7; re-read region before each edit, edit bottom-to-top
- **Commit per task** — I-tasks = empty checkpoint; each F-S = one commit
- **Follow QUICK_REF.md for all build/run commands**
- **Plan says A, do A** — STOP on ambiguity, present to operator
- **Do NOT make out-of-plan fixes** — bugs outside scope are noted, not fixed

---

## I-M RESEARCH TASKS

### Task I-M7: Research basename collision — naming scheme + fix targets

**Files:**
- Read: `sf/src/main.zig`, `sf/src/c89_emit.zig`, `sf/src/include/zig_pal.c`, `sf/docs/tech_docs/08_c89_emission.md`, `sf/docs/tech_docs/09_pipeline_orchestration.md`
- Create: `.superpowers/sdd/IM7-report.md`

**Investigation:**
1. **Duplicate basename logic** — `sf/src/main.zig:658-679` and `sf/src/c89_emit.zig:1886-1908` contain byte-identical basename extraction (last `/` scan → `.zig`/`.z98` strip). Can one site be eliminated so both output-filename and include-path derivations share a single source of truth? Or must both exist (different call contexts)?
2. **Self-host collision audit** — 4 collision groups found (10 files). But self-host tree is compiled by zig0, not zig1. Can we construct a multi-module repro that triggers zig1's collision path? Build a minimal 2-module project where both modules share a basename (`lib/util.zig` + `app/util.zig`), run `zig1 --dump-c89 --output-dir /tmp/out`, verify output overwrite `[c89]`.
3. **Hash-qualified naming scheme** — use `module_id` (u32, guaranteed unique) + short hash of path as suffix: `basename_MID_HASH.h`. What hash function? `h*31+char` is already used in c89_emit.zig for dedup. Is that sufficient for ~100 module collisions or need something stronger? What's the max output path length with hash suffix (must fit in 511-byte pal.zig buffer)?
4. **Include chain rebuild** — after renaming output files, every `#include "name.h"` reference must match. Audit all include-emission sites: `emitModuleHeaderFile` lines 1861/1910-1913 (shared include + dep includes), `emitModuleFile` line 2044 (self-include), `emitSharedHeader` preamble. Are there any hardcoded include paths that assume basename-only names?
5. **zig0 comparison** — zig0 emits `#include "modname.h"` for imports (cbackend.cpp). How does zig0 derive per-module filenames? Does it handle basename collisions? What naming scheme does it use? `[source]`
6. **Doc update blast radius** — which NOTES.md recipes, QUICK_REF sections, and tech docs reference per-module output file names by pattern? Do any recipes depend on specific filenames (e.g., `main.c` for the entry module)?

**Steps:**
- [ ] Read source files + verify collision groups
- [ ] Build collision-triggering repro, confirm silent overwrite `[c89]`
- [ ] Evaluate hash-qualified naming: collision probability, max path length, Z98-hash availability
- [ ] Audit all include-emission sites for hardcoded paths
- [ ] Read zig0 cbackend.cpp for naming scheme comparison `[source]`
- [ ] Write report: A (findings) / B (blast radius) / C (options A/B/C comparison) / D (exact edit targets with file:line)
- [ ] Empty checkpoint commit `bugfix: IM7 research report for basename collision`

---

### Task I-M8: Research closure edge model — tstIsDep + c89NeedsEmitEdge + fieldEmbedsByValue

**Files:**
- Read: `sf/src/c89_emit.zig`, `sf/src/type_resolver.zig`, `sf/docs/tech_docs/03_type_resolution.md`, `sf/docs/tech_docs/08_c89_emission.md`
- Create: `.superpowers/sdd/IM8-report.md`

**Investigation:**
1. **tstIsDep exhaustive audit** — currently handles: struct_type (field iteration), tagged_union_type (tag+fields), array_type (elem), error_union_type (payload). MISSING: optional_type (opt_items payload), slice_type (slice_items elem), union_type (un_items fields). For each missing kind: does it have sub-types reachable by value? What TypeUnion fields to check? `[source]`
2. **c89NeedsEmitEdge false-negatives** — currently returns false for enum_type(26) and error_set_type(23). Both ARE embeddable by value in struct/TU fields. Does computeSharedSet's fixpoint loop (c89_emit.zig:967-968) rely on c89NeedsEmitEdge returning true for these? Or does the fixpoint have its own candidate filter? Trace exact path: field_iteration → tstIsDep → c89NeedsEmitEdge(target) → false → enum never promoted. `[source]`
3. **fieldEmbedsByValue missing entries** — type_resolver.zig:323-330 returns false for enum_type and error_set_type. In C89, both emit as inline typedef integer aliases — they occupy inline space in struct layouts. Does classifyTypeEmissionGroups use fieldEmbedsByValue? If so, fixing this alone might cascade: enum marked CLS:v → included in shared_set seed → no closure needed. Is that the cleaner fix? `[source]` + `[gdb]`
4. **Sibling function audit** — `tstEdgesCount` (c89_emit.zig:857-883) and `tstEdgesFill` are used by the topological sort. Do they have the same missing branches? If the sort is incomplete, does emit order break? Does this only matter for shared header (where order determines if defs appear before uses)? `[source]`
5. **Repro construction** — build minimal 2-module Z98 project: module A defines `enum Color { R, G, B }` used only behind pointers; module B defines a struct that embeds Color by value (with a real struct field to make it CLS:v). Run with `--output-dir`, verify gcc incomplete-type error `[c89]`.
6. **Complete fix list** — for each site (tstIsDep, c89NeedsEmitEdge, fieldEmbedsByValue, tstEdgesCount, tstEdgesFill), what are the exact TypeUnion field accesses needed? Which TypeKind constants? Write pseudocode for each missing branch. `[source]`

**Steps:**
- [ ] Read all 5 affected functions in c89_emit.zig + fieldEmbedsByValue in type_resolver.zig
- [ ] Build minimal enum-by-value repro, confirm incomplete-type compile error `[c89]`
- [ ] Trace field_iteration path through all types to verify which TypeUnion fields embed by value
- [ ] Audit tstEdgesCount/tstEdgesFill for same missing branches
- [ ] Write fix pseudocode: exact field accesses, exact TypeKind constants per missing branch
- [ ] Write report: A (findings) / B (blast radius) / C (options: minimal-fix vs full-audit) / D (exact edit targets with complete fix code at file:line)
- [ ] Empty checkpoint commit `bugfix: IM8 research report for closure edge model`

---

### Task I-M9: Research Win32 handle truncation — type safety fix

**Files:**
- Read: `sf/src/include/zig_pal.c`, `sf/src/pal.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`, `sf/docs/tech_docs/10_c_runtime.md`
- Create: `.superpowers/sdd/IM9-report.md`

**Investigation:**
1. **Vestigial PlatFile audit** — zig_pal.c:16-21 defines `PlatFile` (void* on Win32, int on POSIX) with `PLAT_INVALID_FILE` sentinel. It is NEVER used anywhere. Why? When was it added vs when was `int` hardcoded? Check git log for `PlatFile` `[source]`.
2. **Type chain mapping** — trace the full fd type from C to Zig and back: pal_file_open returns `int` → pal.zig extern declares `i32` → BufferedWriter.fd is `i32` → bufferedWriterFlush calls pal.fileWrite(fd: i32) → extern pal_file_write takes `int` → casts to `(HANDLE)(size_t)fd`. Identify every site that must change if fd type becomes `usize` (pointer-width) on the Zig side. `[source]`
3. **Zig-side type change blast radius** — BufferedWriter struct (c89_emit.zig:31), bufferedWriterInit/bufferedWriterInitFd params (c89_emit.zig:33/38), bufferedWriterFlush call (c89_emit.zig:42), pal.zig externs (:11-13) + wrappers (:70/82/86), main.zig fd variables (:638/689/716), all `@intCast(i32, ...)` calls. Count total lines. `[source]`
4. **PlatFile vs intptr_t** — zig_compat.h already defines `usize` and `u32` etc. Could define `PlatFd` as `usize` in zig_compat.h and use it everywhere. But PlatFile already exists in zig_pal.c. Which is cleaner: fix PlatFile (C side) + use `usize` (Zig side), or define a new type? `[source]`
5. **INVALID_HANDLE_VALUE correctness** — on Win32 `INVALID_HANDLE_VALUE` = `(HANDLE)(LONG_PTR)-1` = `0xFFFFFFFF` (32-bit) or `0xFFFFFFFFFFFFFFFF` (64-bit). Currently checked BEFORE truncation at zig_pal.c:184 — correct. But after switching to pointer-width types, the error sentinel on Zig side should be `@bitCast(usize, @as(isize, -1))` or a named constant. What's the cleanest Z98 representation? `[source]`
6. **Can we test this?** — no Win32 CI. The gate is: build zig1 on Linux (unchanged), verify nm shows correct symbols, verify bare --dump-c89 md5s unchanged. Any functional test of the Win32 path is impossible. What's the confidence check? `[build]`

**Steps:**
- [ ] Read all type chain files + git log for PlatFile history
- [ ] Count exact lines affected by i32→usize change
- [ ] Design PlatFile reactivation: C side (zig_pal.c typedef→actual use) + Zig side (externs/wrappers/struct/callers)
- [ ] Verify Linux build: `bash sf/scripts/build_release.sh` → 0 errors, `nm zig1 | grep pal_file_` unchanged
- [ ] Write report: A (findings) / B (blast radius) / C (options: PlatFile vs intptr_t vs comment-only) / D (exact edit targets)
- [ ] Empty checkpoint commit `bugfix: IM9 research report for Win32 handle truncation`

---

### Task I-M10: Research empty/missing file diagnostics

**Files:**
- Read: `sf/src/main.zig`, `sf/src/pal.zig`, `sf/src/import_resolver.zig`, `sf/src/main_dump.zig` (reference), `sf/docs/tech_docs/01_import_resolution.md`, `sf/docs/tech_docs/09_pipeline_orchestration.md`
- Create: `.superpowers/sdd/IM10-report.md`

**Investigation:**
1. **Root file check placement** — main_dump.zig:73-79 shows the correct pattern: after parseArgs, call `pal.readFile(input_file) orelse { stderr error msg, pal.exit(1) }`. Where in main.zig should this go? Before the parser init (after line ~133, where empty-args check already lives)? Or after module registry init (to access diagnostics system)? `[source]`
2. **Empty file vs missing file distinction** — pal.readFile returns null for BOTH missing file (fopen null) AND empty file (ftell ≤ 0). Can we distinguish them? Option A: change pal.readFile to return different error codes OR use pal.fileExists (pal.zig:49-58) before readFile. Option B: same error message for both ("could not read input file"). What does the operator preference (Error+exit(1) for both) imply for distinction? `[source]`
3. **Dependency file failures** — import_resolver.zig:94-99 silently transitions module to failed state when readFile returns null. For multi-module compilations, should missing dependency files also be hard errors (exit(1))? Or should they add a Diagnostic with ERR_* level, letting the existing diagnosticCollectorHasErrors → exit(2) path handle it? `[source]`
4. **Diagnostic error codes** — import_resolver.zig uses existing error codes (e.g., ERR_3006 for import resolve failure). What error code for "file not found" / "empty file"? Check existing diagnostics: error[(3000|3001|3005|3006|3011|3042|3043|3048|9001)]. Is there an existing "file read error" code? If not, what new code range is available? `[source]`
5. **Corpus + example gate impact** — adding error exit for missing/empty files means some existing gate flows might break. Check: do any corpus repros intentionally use non-existent files? Does build_test.sh expect exit 0 on empty input? Verify: run `zig1 --dump-c89 /nonexistent.zig` at current HEAD to confirm current behavior (silent exit 0). `[c89]`
6. **pal.c_exit vs pal.exit path** — pal.zig has TWO exit functions: `c_exit` (extern, calls C exit()) and `pal.exit` (wrapper). Which should the new error use? main_dump.zig uses `pal.exit(1)`. Is this the convention? `[source]`

**Steps:**
- [ ] Read main.zig parseArgs + main() + import_resolver.zig readFile-null path
- [ ] Verify current silent behavior: run `zig1 --dump-c89 /nonexistent.zig` → exit 0, no stderr `[c89]`
- [ ] Read main_dump.zig:73-79 for reference error-handling pattern
- [ ] Audit existing Diagnostic error codes for file-not-found precedent
- [ ] Check import_resolver.zig for how failed modules interact with phase skipping and diagnostic collection
- [ ] Write report: A (findings) / B (blast radius) / C (options: root-only vs both root+deps) / D (exact edit targets with error message text, exit code, file:line)
- [ ] Empty checkpoint commit `bugfix: IM10 research report for empty/missing file diagnostics`

---

## F-S IMPLEMENTATION TASKS

### Task F-S7: Fix basename collision

**Files:**
- Modify: `sf/src/c89_emit.zig` (include-path derivation, output file naming in emitModuleHeaderFile/emitModuleFile)
- Modify: `sf/src/main.zig` (output file path construction, basename derivation consolidation)

**Pre-requisite:** IM7-report.md §D (exact naming scheme, exact edit targets).

**AMENDMENT 1 (assessment 2026-08-01):** **DROP the MID component.** Naming scheme is now `<basename clamped to 64>_<FNV1a(path) 8 uppercase hex>.c/.h` — **NO module_id**. FNV-1a of the full path alone disambiguates (birthday bound ~2.9×10⁻⁵ for 500 modules); the MID made filenames unstable across builds (import-order shifts MIDs). Visual parity with the existing `zF_7F9D0FD1_name` mangler convention. `moduleQualifiedName` helper in c89_emit.zig returns `basename_HEX8` stem (module_id NOT part of output). Module_id==0 root gate at c89_emit.zig:2055 unaffected — it keys off registration order, not the filename.

**AMENDMENT 2 (assessment 2026-08-01):** Also update the **embedded build script templates** at `c89_emit.zig:4412-4428` that hardcode `main.c` (Unix shell `-c main.c -o main.o`, Windows batch `main.c`, OpenWatcom `main.c`). Either parameterize with `$ROOT_MODULE` or annotate as reference-only/dead. This was missed by the IM7 report.

- [ ] **Step 1 — Consolidate basename logic:** Extract shared basename derivation into a single helper `moduleQualifiedName(emitter, module_id)` in c89_emit.zig (before emitModuleHeaderFile at :1841). Uses `module_reg` + `interner` (both available at both call sites). Body: fetch path via `moduleRegistryGetModules(emitter.module_reg)[module_id].path_id` + stringInternerGet; extract basename (last `/` scan, strip `.zig`/`.z98`); clamp to 64; `hash = hash_mod.fnv1a(path)` (sf/src/util/hash.zig:4-11, FNV-1a 0x811C9DC5/0x01000193 — same pair name mangler uses at :393/:403); build `basename_HEX8` into `[96]u8` buffer using existing `writeHex` (:98-117); intern; return. Eliminate the byte-identical duplicate at c89_emit.zig:1886-1908 AND main.zig:658-679 — both call the helper.
- [ ] **Step 2 — Implement qualified naming:** Output files become `<basename clamped 64>_<FNV1a8>.h` / `.c` (NO MID). main.zig:658-679 replaced by `var base = c89_mod.moduleQualifiedName(&emitter, m.id);`. Path construction :680-688/.h and :706-715/.c uses the qualified stem. **Add explicit length guard:** if `od.len + 1 + base.len + 3 > 511`, print error + exit (currently silently truncates at :685/:712).
- [ ] **Step 3 — Update include chain:** Only one LOC site changes derivation: dep-includes at c89_emit.zig:1909-1913 → `#include "<moduleQualifiedName(emitter, d)>.h"` (keeping the `d == module_id` self-skip). Self-include (emitModuleFile:2044) needs NO code change — qualified `mod_name` flows in from main.zig:702/:725. Shared-header include (emitModuleHeaderFile:1861) uses fixed names, no change. Header guard (emitModuleHeaderFile:1842-1859) is auto-unique via qualified `mod_name` (was `ZIG_MODULE_UTIL_H`, now `ZIG_MODULE_UTIL_7F9D0FD1_H`).
- [ ] **Step 4 — Update embedded build script templates:** `c89_emit.zig:4412-4428` hardcode `main.c`. Update to use the qualified root module name (root = module_id==0 → `main_HEX8.c`), or annotate as reference-only if they are dead templates.
- [ ] **Step 5 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. Lisp `--output-dir /tmp/s7` produces all files with unique qualified names (no overwrite). IM7 collision repro (lib/util.zig + app/util.zig) → **4 distinct module files** (`util_<H1>.h/c` + `util_<H2>.h/c`), single `#include "util_<H>.h"` per dep in main.h, unique guards, link clean. Cross-module includes resolve. Bare `--dump-c89` md5s preserved (stdout path untouched). All 18 examples build+link+run.
- [ ] **Step 6 — Commit checkpoint:** `fix: F-S7 qualified module output filenames`

---

### Task F-S8: Fix closure edge model

**Files:**
- Modify: `sf/src/c89_emit.zig` (tstIsDep, c89NeedsEmitEdge, tstEdgesCount, tstEdgesFill)
- Modify: `sf/src/type_resolver.zig` (fieldEmbedsByValue)

**Pre-requisite:** IM8-report.md §D + IM8-assessment.md (exact fix code for each function).

**AMENDMENT 1 (assessment 2026-08-01):** **fieldEmbedsByValue is REQUIRED, not optional.** Assessment verified it's needed for cross-module correctness when a struct's only by-value fields are enums/error_sets (otherwise the per-module `.h` emits the struct before the enum typedef → same incomplete-type failure in the module header). Also confirmed: adding enum/error_set to fieldEmbedsByValue does NOT make the enum itself CLS:v (classifyTypeEmissionGroups has no enum branch → always defaults to is_po=1). The promotion path (c89NeedsEmitEdge fix) is the primary fix; fieldEmbedsByValue is the companion classification correction. Rejected alternative: adding enum_type/error_set_type branches to classifyTypeEmissionGroups setting is_po=0 (makes ALL enums CLS:v → shared header bloat + breaks ordering for slice/optional-of-enum). 

**AMENDMENT 2 (assessment 2026-08-01):** `tstEdgesFill` (c89_emit.zig:795-830) is **dead code** — zero callers. Fix it anyway for completeness (it mirrors tstIsDep/tstEdgesCount and would be a trap if ever wired up). No behavioral impact.

**AMENDMENT 3 (assessment 2026-08-01):** Slice over-promotion is accepted. Adding `slice_type` source branch to tstIsDep promotes CLS:p struct slice-elements (which only need a fwd-decl) into shared_set. Benign bloat; the coarse existing model treats slice-elem types as by-value refs. Do NOT special-case it.

**AMENDMENT 4 (OPERATOR RULING 2026-08-01 — supersedes AMENDMENT 3):** **Restrict the new slice/optional source branches to enum_type/error_set_type element targets ONLY.** Empirically found by F-S8 implementer: unrestricted slice/optional source branches create a **2-cycle** for self-referential slice types (`json.zig:10` `Array: []JsonValue` → Slice_JsonValue → JsonValue), and `tstTopologicalSort` (c89_emit.zig:857-893) has NO cycle handling — cyclic nodes never enter the Kahn queue and are **silently dropped from `sorted`**, breaking json_parser (gcc `unknown type name`, body + fwd-decl + EU_52 dropped) in both stdout and output-dir paths. game_of_life also reorders (benign, gcc-clean).

**Rationale (upstream-fitness):** The edge model's purpose is EMIT-ORDERING, not "type X references type Y". An edge means "A must be typedef'd before B's body because B's C output uses A's name in a place where fwd-decl is insufficient." The unfiltered fwd-decl pass (emitSharedHeader:999-1021) already emits `typedef struct X X;` for every named struct/TU/union — so struct/TU/union names through slices/optionals need NO edge (fwd-decl suffices), and creating one is WRONG (fictitious ordering → cycles). enum_type and error_set_type are the ONLY non-forward-declarable named kinds (C89 typedefs, emitted as `typedef int X;`/`typedef unsigned int X;`). Restricting slice/optional edges to enum/error_set targets exactly matches C89 semantics: edges exist iff the C name must be in scope. This also eliminates the over-promotion bloat (AMENDMENT 3 revoked) for free. Struct-by-value fields (struct/tagged_union/union source branches), array elems, and error_union payloads KEEP their unrestricted edges (all embed by value → full def required). **Do NOT add cycle-handling to tstTopologicalSort (Option 2 rejected by operator)** — the edge model correction is the upstream fix; Option 2 would move complexity into the sort to rediscover the same "fwd-decl vs full-def" distinction in the wrong place.

- [ ] **Step 1 — Fix c89NeedsEmitEdge (REQUIRED, root cause):** Add `enum_type` and `error_set_type` to c89NeedsEmitEdge (c89_emit.zig:751-762). This unblocks tstIsDep :834 (promotion) and adds topo edges for enum/error_set targets in all source branches. Complete fix list from IM8 §D1-D4 (verified by assessment).
- [ ] **Step 2 — Fix tstIsDep (REQUIRED, AMENDMENT 4 restriction):** Add missing source-kind branches after error_union branch (:851-852): `union_type` → iterate `reg.un_items[payload_idx].fields_start/count` over `fe_items`. `optional_type` and `slice_type` branches → add, BUT the edge fires ONLY when `target` is `enum_type` or `error_set_type`:
  ```zig
  } else if (ty.kind == TypeKind.optional_type) {
      var op = reg.opt_items[@intCast(usize, ty.payload_idx)].payload;
      if (op == target and (target_kind == enum_type or target_kind == error_set_type)) return true;
  } else if (ty.kind == TypeKind.slice_type) {
      var se = reg.slice_items[@intCast(usize, ty.payload_idx)].elem;
      if (se == target and (target_kind == enum_type or target_kind == error_set_type)) return true;
  }
  ```
  (`target_kind = reg.types_items[@intCast(usize, target)].kind`.) This prevents the JsonValue↔Slice_JsonValue 2-cycle (struct slice-elem → NO edge) while still promoting `[]Color`/`?Color` enum/error_set shapes.
- [ ] **Step 3 — Fix tstEdgesCount + tstEdgesFill (REQUIRED, AMENDMENT 4 restriction):** Mirror Step 2's union branch + the enum/error_set-restricted optional/slice branches. Count/fill an edge only when `c89NeedsEmitEdge(target.kind)` and `target != ti` AND (for optional/slice) `target.kind ∈ {enum_type, error_set_type}`. No enum/error_set SOURCE branches needed (backing_type/tags are plain ints). tstEdgesFill is dead code but fix for completeness (AMENDMENT 2).
- [ ] **Step 4 — Fix fieldEmbedsByValue (REQUIRED, AMENDMENT 1):** Add `enum_type` and `error_set_type` to fieldEmbedsByValue (type_resolver.zig:323-330). Companion classification correction, NOT the primary fix.
- [ ] **Step 5 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. Run IM8 §A5 repros #1/#2/#3 → gcc clean (no `unknown type name`). **json_parser regression MUST be gone**: bare `--dump-c89 json_parser` → byte-identical md5 `11a5db1d3d43acf4880e2d157590abe3`, and gcc-clean. game_of_life → byte-identical md5 `f855c9f93c73422f56378f3f73231727`. All 4 stdout md5s preserved (lisp `0ad0204088f91c1eae7c040da8f99a1c`, mud `5fb57e70c2d637276ab0264c1401cd0d`). Lisp `--output-dir` partition still correct. Corpus: zero regressions.
- [ ] **Step 6 — Commit checkpoint:** `fix: F-S8 complete closure edge model in tstIsDep and classifiers`

---

### Task F-S9: Fix Win32 handle truncation

**Files:**
- Modify: `sf/src/include/zig_pal.c` (reactivate PlatFile typedef, use in pal_file_*)
- Modify: `sf/src/pal.zig` (externs + wrappers: i32 → usize)
- Modify: `sf/src/c89_emit.zig` (BufferedWriter.fd: i32 → usize, init/initFd params, flush call)
- Modify: `sf/src/main.zig` (fd variables: i32 → usize, error check `-1` → sentinel constant)

**Pre-requisite:** IM9-report.md §D (exact type chain changes, sentinel constant name, all affected lines).

**AMENDMENT 1 (assessment 2026-08-01):** **Plan deviation accepted.** Sentinel is `@intCast(usize, 0xFFFFFFFF)` NOT `@bitCast(usize, @as(isize, -1))`. Verified: `@bitCast` is absent from `Language_Spec_Z98.md` builtins and never used in `sf/src/` (0 hits); `@intCast(usize, 0xFFFFFFFF)` is the codebase all-ones idiom (67 hits, mirrors `lower.zig:57 TEMP_NONE = 0xFFFFFFFF`). Z98 `usize` = C `unsigned int` = 32-bit on ALL targets (Language_Spec_Z98.md:15, zig_compat.h:27), so `0xFFFFFFFF` = POSIX `-1` and Win32 `INVALID_HANDLE_VALUE` (all-ones at 32-bit) simultaneously.

**AMENDMENT 2 (assessment 2026-08-01):** **Add dead-code comment above `emitZigPalC`** (c89_emit.zig:733-734): `// DEAD CODE — never called. Frozen mirror of sf/src/include/zig_pal.c. If zig_pal.c is modified, update this function to keep byte-identity.` Verified emitZigPalC and emitZigCompatH have ZERO callers. The embedded strings ARE byte-identical mirrors (verified, 4949 bytes) and must be updated in sync with zig_pal.c edits. Add the byte-identity verification command (IM9 §D:11) to the gate.

**AMENDMENT 3 (assessment 2026-08-01):** Fix the **latent `isize`-undefined Win32 compile bug**: `zig_pal.c:17` `#define PLAT_INVALID_FILE ((void*)(isize)-1)` references an undefined identifier (zig_compat.h has no `isize`). Change to `((void*)-1)`. This is REQUIRED — any `_WIN32` compile of zig_pal.c currently fails at the preprocessor.

- [ ] **Step 1 — Reactivate PlatFile in zig_pal.c:** Replace `int` return/param types in pal_file_open/write/close with `PlatFile`. Use existing `PLAT_INVALID_FILE` sentinel. Fix `isize` → `((void*)-1)` (AMENDMENT 3). Win32: `if (h == INVALID_HANDLE_VALUE) return PLAT_INVALID_FILE; return h;` (drop truncation cast). POSIX: `if (!path) return PLAT_INVALID_FILE; return open(...)`. Keep `#ifdef _WIN32` / `#else` branches structurally identical.
- [ ] **Step 2 — Update pal.zig externs + wrappers:** Change `i32` → `usize` for pal_file_open/write/close externs (:11-13) + wrappers fileOpen/fileWrite/fileClose (:70/82/86). Add `pub const INVALID_FD: usize = @intCast(usize, 0xFFFFFFFF);` near :70 (AMENDMENT 1).
- [ ] **Step 3 — Update BufferedWriter:** fd field `i32` → `usize` (c89_emit.zig:31), default `.fd = @intCast(usize, 1)` (:35), `bufferedWriterInitFd(fd: usize)` (:38). Remove `@intCast(i32, ...)` casts. Keep flags args as `i32` (main.zig:638/689/716 `@intCast(i32, 0)` unchanged).
- [ ] **Step 4 — Update main.zig fd checks:** `var fd: i32` → `var fd: usize` (:638/689/716), `== -1` → `== INVALID_FD` (:639/690/717).
- [ ] **Step 5 — Sync embedded mirrors + dead-code comment (AMENDMENT 2):** Apply the same zig_pal.c edits to the embedded h02/h12 string literals at c89_emit.zig:736/:747. Add the dead-code comment above emitZigPalC. Re-run the byte-identity verification command → must print IDENTICAL.
- [ ] **Step 6 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. `nm sf/build/out_release/zig1 | grep pal_file_` shows pal_file_open/write/close still defined once (C89 has no mangling → param-type change keeps symbols identical — the ABI proof). Bare `--dump-c89` md5s preserved (emitZigPalC dead → edit inert to stdout). Lisp `--output-dir /tmp/s9` → files created correctly through the usize fd path. Byte-identity check → IDENTICAL.
- [ ] **Step 7 — Commit checkpoint:** `fix: F-S9 pointer-width file descriptors (Win32 safety)`

---

### Task F-S10: Fix empty/missing file diagnostics

**Files:**
- Modify: `sf/src/main.zig` (root file existence check after parseArgs)
- Modify: `sf/src/pal.zig` (optionally: distinguish empty vs missing in readFile)
- Modify: `sf/src/import_resolver.zig` (diagnostic on readFile failure for dependency files)

**Pre-requisite:** IM10-report.md §D (exact error messages, exit codes, diagnostic error codes, placement).

**AMENDMENT 1 (assessment 2026-08-01):** **Plan gap closed — TWO dependency sites required.** The plan's Step 2 only covers EMPTY deps (import_resolver.zig:95, where readFile returns null after fileExists passed). MISSING deps never reach readFile — `moduleResolverResolve` (module_registry.zig:144-161) gates on fileExists and returns null → `moduleRegistryResolveImport` (module_registry.zig:263) returns null → parser.zig:641-643 discards the result. So a SECOND diagnostic site at module_registry.zig:263 ("could not resolve imported file") is REQUIRED. The two sites cover non-overlapping failure modes. Assessment confirmed module_registry.zig:263 beats parser.zig:641 (resolver owns resolution semantics + has self.diag/interner directly).

**AMENDMENT 2 (assessment 2026-08-01):** **Exit code asymmetry is correct and convention-consistent.** Root file → exit(1) (IO/usage class, matches main_dump.zig:78 + c89_emit open-fail sites). Dependency files → exit(2) via existing `diagnosticCollectorHasErrors → pal.exit(2)` (main.zig:199). Structurally required: the root check runs before DiagnosticCollector init (main.zig:139-141); dependency diagnostics happen inside the pipeline where diag is wired.

**AMENDMENT 3 (assessment 2026-08-01):** **New error code ERR_3048_CANNOT_READ_FILE = 3048** appended to ErrorCode enum (diagnostics.zig:10-67). Explicit value → no existing member shifts. Verified: zero literal-3048 call sites; does NOT match corpus ICE classifier regex `error\[(48|3042|9001|3043)\]` (QUICK_REF:45). Emits as `error[3048]: <message>` (diagnostics.zig:367-383, file_id==0 → no file:line prefix). Use `@enumToInt(...)` at call sites, matching module_registry.zig:401-405 pattern.

**AMENDMENT 4 (assessment 2026-08-01):** **Root check uses readFile pre-check, NOT fileExists.** `pal.fileExists` cannot detect empty files (open+close only). readFile pre-check handles both missing+empty with one call; waste on permanent arena is bounded to ~1 MB (OOM caught → clean exit(1)). Keep byte-parity with main_dump.zig:73-79 (message `"error: could not read input file\n"`, no path appended).

**Files:**
- Modify: `sf/src/main.zig` (root file existence check after parseArgs)
- Modify: `sf/src/import_resolver.zig` (empty-dependency diagnostic at :95)
- Modify: `sf/src/module_registry.zig` (missing-dependency diagnostic at :263)
- Modify: `sf/src/diagnostics.zig` (add ERR_3048_CANNOT_READ_FILE = 3048)

- [ ] **Step 1 — Add root file check in main.zig:** Insert after line 138 (`compiler_alloc.max_mem = cli.max_mem;`), before interner init :139: `var source = pal.readFile(cli.input_file, &compiler_alloc.permanent) orelse { const msg: []const u8 = "error: could not read input file\n"; pal.stderr_write(msg); pal.exit(1); return; };` (source unused afterwards; matches main_dump.zig:73-79 shape). Exit code 1, same message for missing and empty (AMENDMENT 4).
- [ ] **Step 2 — Add diagnostics.zig error code (AMENDMENT 3):** Append `ERR_3048_CANNOT_READ_FILE = 3048,` to ErrorCode enum (explicit value, no shifts).
- [ ] **Step 3 — Add empty-dependency diagnostic in import_resolver.zig:** At :94-99 where readFile returns null, build message `"error: could not read imported file '<path>'"` via `diagnosticBuilderMakeMsg(reg.interner, ...)` + `diagnosticCollectorAdd(reg.diag, 0, @enumToInt(ERR_3048_CANNOT_READ_FILE), 0, 0, 0, msg)`. Add `const diag_mod = @import("diagnostics.zig");`. Keep `state = ModuleState.failed`. Existing main.zig:199 hasErrors gate → exit(2).
- [ ] **Step 4 — Add missing-dependency diagnostic in module_registry.zig (AMENDMENT 1):** In `moduleRegistryResolveImport` at :263, before `return null;`: build message `"error: could not resolve imported file '<path>'"` via diagnosticBuilderMakeMsg + diagnosticCollectorAdd (self.diag, self.interner available). Same ERR_3048 code. → exit(2) via main.zig:199.
- [ ] **Step 5 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. `zig1 --dump-c89 /nonexistent.zig` → stderr `error: could not read input file`, exit(1). `--output-dir` variant → same, exit(1). Empty `.zig` file → same, exit(1). Root importing missing dep → `error[3048]: could not resolve imported file '<path>'`, exit(2). Root importing empty dep → `error[3048]: could not read imported file '<path>'`, exit(2). Lisp `--output-dir` with all files present → works (no false positives). Bare `--dump-c89` md5s preserved.
- [ ] **Step 6 — Commit checkpoint:** `fix: F-S10 error on missing or empty input files`

---

### Task F-D2: Update documentation

**Files:**
- Update: `sf/docs/tech_docs/08_c89_emission.md` (qualified filenames, closure edge model fix, handle type change, error handling)
- Update: `sf/docs/tech_docs/09_pipeline_orchestration.md` (file-not-found error path, fd types)
- Update: `sf/docs/tech_docs/00_shared_infra.md` (PAL fd type change)
- Update: `sf/docs/tech_docs/01_import_resolution.md` (dependency read error diagnostics)
- Update: `sf/docs/tech_docs/03_type_resolution.md` (fieldEmbedsByValue enum/error_set)
- Update: `sf/docs/tech_docs/10_c_runtime.md` (PlatFile reactivation)
- Update: `docs/sf/QUICK_REF.md` (any changed recipe patterns)

**Pre-requisite:** F-S7 through F-S10 all DONE.

- [ ] **Step 1 — Update tech docs:** For each doc, add notes on the fix with `[updated: 2026-08-01]` annotations. Document the qualified naming scheme (basename_HEX8, no MID), the new error behavior (root exit 1, deps exit 2, ERR_3048), the fd type change (usize/PlatFile, INVALID_FD, isize fix), the fieldEmbedsByValue fix (REQUIRED), the dead emitZigPalC/emitZigCompatH mirror sync constraint. Per-report undocumented findings:
  - `08_c89_emission.md`: qualified filename scheme + guard (`ZIG_MODULE_<NAME>_HEX8_H`), closure-edge criterion ("referenced by-value OR in a way requiring the C type name in scope"), slice-elem type-name-in-scope note, fd: i32→usize, embedded build-script template note
  - `09_pipeline_orchestration.md`: file-not-found error path (root exit 1), dependency diagnostics exit 2 at main.zig:199, fd types
  - `00_shared_infra.md`: PAL fd type (usize), INVALID_FD sentinel
  - `01_import_resolution.md`: new ERR_3048 entry, readFile-fail → failed state now surfaces diagnostic, missing-dep resolve-null choke point, `ast_root == 0` skip mechanism (not ModuleState.failed)
  - `03_type_resolution.md`: fieldEmbedsByValue enum/error_set kinds, classifyTypeEmissionGroups no enum branch (enums stay CLS:p)
  - `10_c_runtime.md`: PlatFile reactivation + PLAT_INVALID_FILE, isize→(void*)-1 fix, usize is 32-bit unsigned int (not pointer-sized — correct the label), PlatFile/PLAT_INVALID_FILE rows added
- [ ] **Step 2 — Update QUICK_REF.md:** If any recipe patterns changed (different filenames in per-module loop), update. Glob-based recipes unaffected. Annotate that the 4 fixes are transparent to recipes (except any entry-module filename references).
- [ ] **Step 3 — Final commit:** `fix: address ledger latent bugs — basename collision, closure edges, Win32 handles, file diagnostics`

---

## Execution Notes

- **Execution order:** I-M7→I-M8→I-M9→I-M10 (parallel OK, all research-only) → assessment review → F-S7→F-S8→F-S9→F-S10 (sequential, cumulative changes to same files) → F-D2
- **Research independence:** I-M tasks operate on UNCHANGED source. They can run in any order or parallel. Each produces a standalone report.
- **Fix dependency:** F-S tasks modify overlapping files (c89_emit.zig, main.zig, pal.zig). Sequential execution avoids merge conflicts.
- **Assessment reports:** Each F-S task MUST read its assessment report (.superpowers/sdd/IM*-assessment.md) in addition to the research report. The amendments above encode the assessment decisions.
- **Gate enforcement:** After each F-S stage, verify gates CLEAN. If any gate fails, STOP.
- **Single commit per stage:** Each task produces one checkpoint commit.
- **QUICK_REF.md consultation:** Every subagent MUST read `docs/sf/QUICK_REF.md` before any build/compile/run command.
- **fastedit/edit only:** Source edits via `edit` or `fastedit`. Read target region before each edit. Edit bottom-to-top.
- **Z98 string literal rule:** Always `var msg: []const u8 = "text";` before passing to PAL functions.
- **Plan says A, do A.** If ambiguity, STOP. No out-of-plan fixes.
