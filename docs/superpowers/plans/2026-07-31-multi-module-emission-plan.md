# Multi-Module C89 Emission — Option A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Implement per-module `.c`/`.h` emission in zig1's C89 backend matching the design oracle (`docs/sf/LIR_C89_Emission_p2.md` §2.1) and zig0's organization pattern.

**Architecture:** 6 I-tasks (research + report per category) → 1 F-A task (unified implementation). Each I-task reads source + traces + designs multiple options, producing a report with exact edit targets. F-A implements all findings from all 6 reports. Option B intentionally rejected — this plan delivers full per-module encapsulation (shared types header + per-module `.h` + per-module `.c`).

**Tech Stack:** zig1 binary at `sf/build/out_release/zig1`, z98-compatible Z98 for source edits, GDB/fprintf for evidence.

## Required Reading (for every subagent)

| Doc | Role | Key sections |
|-----|------|--------------|
| `docs/sf/LIR_C89_Emission_p2.md` | Design oracle | §2.1 two-phase output, §3 C89 type emission, shared/per-module split |
| `sf/docs/tech_docs/08_c89_emission.md` | As-built evidence | §6.1 typedef topo order, §6.3 @cInclude, §6.4 fn order, §6.5 2-phase, §6.7 MARKER_* sites |
| `sf/docs/tech_docs/09_pipeline_orchestration.md` | As-built evidence | §4 CompilerCli, §6.1 arena peaks, §6.3 DepGraph lifecycle |
| `sf/docs/tech_docs/03_type_resolution.md` | As-built evidence | §6.1 TypeId→module mapping, §6.4 pointer-only classification (CLS:p/CLS:v) |
| `sf/docs/tech_docs/01_import_resolution.md` | As-built evidence | §6.1 module graphs, import_edges, ModuleEntry |
| `sf/docs/tech_docs/07_lir_lowering.md` | As-built evidence | FNL marker, LirInst distribution, fn→module_id |
| `.superpowers/sdd/IA-report.md` | Prior research (IA) | All 7 Qs answered, blast radius, concerns, zig0 comparison |

## Global Constraints

- **Source changes allowed** — this plan MODIFIES `sf/src/c89_emit.zig`, `sf/src/main.zig`, `sf/src/pal.zig`, `sf/src/include/zig_pal.c`, and related files
- **I-tasks are RESEARCH ONLY** — zero code changes, empty checkpoint commits, reports are the deliverables
- **F-A is the ONLY implementation task** — it consumes all 6 I-reports
- **Byte-identical gate suspended** — multi-module output changes the emission format (new hashes by design; behavior preserved)
- **Corpus gate:** 184 repros, OK=176 FAIL=8 ICE=0 CRASH=0 (gcc exit-code classifier; harness adapts from `gcc -c single.c` to `gcc -c per-file.c ... link`)
- **Runtime gate:** all 18 Z98 examples build + link + run correctly per their NOTES.md recipes
- **fastedit/edit only for source edits** — per AGENTS.md §X.7; re-read region before each edit, edit bottom-to-top
- **Commit per task** — I-tasks = empty checkpoint; F-A = one implementation commit
- **Follow QUICK_REF.md for all build/run commands**
- **Plan says A, you do A** — STOP on ambiguity, present to operator
- **Do NOT make out-of-plan fixes** — source bugs unrelated to multi-module emission are noted, not fixed

---

### Task I-M1: Research type ownership — which types go in which module's `.h`

**Files:**
- Read: `sf/src/type_registry.zig`, `sf/src/type_resolver.zig`, `sf/src/c89_emit.zig`
- Create: `.superpowers/sdd/IM1-report.md`

**Investigation:**
1. `Type.module_id` mapping — which types carry module ownership? Named types via `typeRegistryRegisterNamedType` (type_registry.zig:629-641) vs synthetic types (ptr/slice/optional/error_union/array/tuple/fn/error_set) created with `module_id=0` (type_registry.zig:336,352,376,406,435,475,492,513,537)
2. `module_id==0` ambiguity — root module vs synthetic. `emitSpecialTypes` filter (c89_emit.zig:925-937) already skips types with `name_id==0`. For per-module ownership: key on `name_id != 0` + `module_id == target_module`
3. Transitive signature-referenced types — if module A's public fn uses `*comptime_eval.ComptimeEval`, does comptime_eval's type go in A's `.h` or does A just `#include "comptime_eval.h"`? Design oracle says latter: per-module `.h` includes only direct-import `.h`s, type definitions live in the owning module's `.h`. This is the design-intended answer — verify it works with the actual type graph
4. Pointer-only (CLS:p) types per module — forward-declarable, no full definition needed in importers' `.h`s. Value-embedding (CLS:v) + synthetics go in `zig_special_types.h`
5. `emitSpecialTypes` global sort (tstTopologicalSort, c89_emit.zig:846) — reusable as-is; partition by type ownership after sort
6. 256-module cap: `moduleRegistrySortModules` has `[256]u32` buffers (module_registry.zig:330,342). For 48-module self-host, 256 is enough. Decide: keep cap or grow to `usize` dynamic arrays

**Steps:**
- [ ] Read source files + tech docs (03/08/09)
- [ ] GDB on zig1 to verify `Type.module_id` for all named types in lisp_interpreter_curr (10 modules — worst case) `[gdb]`
- [ ] Write report: A (findings) / B (blast radius) / C (options) / D (exact edit targets for F-A)
- [ ] Empty checkpoint commit `bugfix: IM1 research report for type ownership`

---

### Task I-M2: Research import ordering — per-module `#include` chains

**Files:**
- Read: `sf/src/module_registry.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`
- Create: `.superpowers/sdd/IM2-report.md`

**Investigation:**
1. Direct-import edges: `import_edges_items[]` + `imports_start`/`import_count` on each `ModuleEntry` (module_registry.zig:165-167, 252-258). For module M, its direct imports = `import_edges_items[imports_start .. imports_start+import_count]`
2. Include order: M's `.h` must `#include` its direct imports' `.h`s in dependency order (Kahn). Option A: wire `moduleRegistrySortModules` (already implemented, test-only, module_registry.zig:327-412). Option B: direct-edge iteration (no sort needed — just emit `#include "dep.h"` for each direct import in order; depth-first include chains handled by transitive guards). Which is correct?
3. 256-cap assessment: `moduleRegistrySortModules` uses `[256]u32` for module_id worklist + in_degree. For 48-module self-host, 256 is sufficient. For future-proofing, increase to `usize` dynamic arrays (module_registry.zig:330,342 → growable arrays). Cost: ~20 lines, no gate impact. Decide: increase cap in I-M2 or leave for F-A.
4. Circular dependency handling — if A depends on B and B depends on A, include guards prevent infinite recursion; header can still compile. `moduleRegistrySortModules` already detects cycles (ERR_3005). Deciding which `.h` goes first in a cycle is arbitrary (include guards make either order valid)
5. `c_includes` per module — already collected in `ModuleEntry.c_includes` (module_registry.zig:439-451). Per-module `.h` uses its own `entry.c_includes`, not the global union
6. zig0 comparison — zig0 emits `#include "<import>.h"` for each direct import (cbackend.cpp:737-751), no additional topological sort beyond the per-module `@import` list

**Steps:**
- [ ] Read source files + tech docs (01/08/09)
- [ ] GDB on zig1 at import_edges for lisp_interpreter_curr (10 modules) — verify edge counts match P1 module graph `[gdb]`
- [ ] Test `moduleRegistrySortModules` on lisp graph in isolation (scratch binary) — confirm it produces a valid topological order `[markers]`
- [ ] Write report with options, exact edit targets, cap decision
- [ ] Empty checkpoint commit `bugfix: IM2 research report for import ordering`

---

### Task I-M3: Research PAL file I/O — BufferedWriter sink abstraction

**Files:**
- Read: `sf/src/pal.zig`, `sf/src/extern_c.zig`, `sf/src/include/zig_pal.c`, `sf/src/c89_emit.zig`
- Create: `.superpowers/sdd/IM3-report.md`

**Investigation:**
1. Current PAL exports: `readFile`, `fileExists`, `stdout_write`, `stderr_write`, `exit`, `initArgs`, `argCount`, `argGet`, `markersEnabled`, `isMarkersEnabled`, `markerWrite`, `markerWriteInt` (pal.zig:16-106). NO file-open/write/close
2. Extern C surface: `extern_c.zig` exposes only `write`, `__bootstrap_print`, `__bootstrap_print_int`. `write` = syscall wrapper. Route file I/O through `extern_c.write` with per-module fd OR add new externs (`fopen`/`fclose`/`fwrite` via C stdio — simpler, already available in zig_pal.c's linked environment)
3. `BufferedWriter` redesign (c89_emit.zig:27-73): add `fd: i32` field, `bufferedWriterInit` takes fd param, `bufferedWriterFlush` writes to fd instead of hardcoded `pal.stdout_write` (c89_emit.zig:36-42). Keep stdout as default (fd=1) so bare `--dump-c89` single-file output is byte-identical
4. `zig_pal.c` additive implementation — add `pal_file_open(const char* path, int flags)` / `pal_file_write(int fd, const char* buf, unsigned int len)` / `pal_file_close(int fd)`. Use POSIX `open`/`write`/`close` (already linked via existing `write` extern). MUST be additive (no symbol conflicts with existing `pal_print_stdout` at zig_pal.c:90-104)
5. Gate impact: new externs must be declared in all test harnesses that link against zig_pal.c. All 18 examples already link `sf/src/include/zig_pal.c` — additive only, no breakage
6. Per-module file naming convention: `"<module_name>.h"` / `"<module_name>.c"` derived from module path (basename without extension, or from `ModuleEntry.path_id` interning)

**Steps:**
- [ ] Read source files
- [ ] Add `extern fn pal_file_open(path: [*]const u8, flags: i32) i32` etc. to `pal.zig`, define in `zig_pal.c`, build zig1 — confirm no link errors `[build]`
- [ ] Test BufferedWriter with fd=stdout on a single example — `--dump-c89` md5 MUST match current baseline `[c89]`
- [ ] Write report with exact PAL API design, BufferedWriter changes, file-naming convention
- [ ] Empty checkpoint commit `bugfix: IM3 research report for PAL file I/O`

---

### Task I-M4: Research shared header partitioning — `zig_special_types.h` generation

**Files:**
- Read: `sf/src/c89_emit.zig`, `sf/src/type_resolver.zig`, `sf/src/include/zig_special_types.h`
- Create: `.superpowers/sdd/IM4-report.md`

**Investigation:**
1. Current `emitSpecialTypes` (c89_emit.zig:884-…) output — all type definitions in single stream. Partition into:
   - **Shared `zig_special_types.h`**: ALL synthetic types (slices, optionals, error unions, error sets, fn pointers) + ALL value-embedding named types (CLS:v from `classifyTypeEmissionGroups`, type_resolver.zig:332-533). These are the types that must be available to every module. Each guarded by `#ifndef ZIG_<tag>_<name>`
   - **Per-module `.h`**: pointer-only named types (CLS:p) — forward-declarable (`typedef struct <cname> <cname>;`), full definition optional in owning module's `.h`. Per-module fn prototypes + public globals + `@cInclude`
2. Guard macros — what naming scheme? zig0 uses `ZIG_SLICE_<mangled>`, `ZIG_STRUCT_<cname>`, `ZIG_TAGGED_UNION_<cname>`. zig1 already has `c_name_id` on each `Type` (type_registry.zig). Adopt or adapt zig0's guard convention
3. `emitSpecialTypes` emits BOTH passes (E2A pointer-only + E2B value-embedding). For multi-module: value-embedding → `zig_special_types.h`; pointer-only → forward-decl in shared OR full def in owning module's `.h`. The design says "pointer-only types forward-declared where referenced, full def at owning site"
4. `zig_special_types.h` currently a 4-line empty stub at `sf/src/include/zig_special_types.h` — zig1 will now GENERATE this file into `--output-dir`, NOT copy the stub
5. `tstTopologicalSort` (c89_emit.zig:846) global sort — reusable unchanged; partition after sort by type ownership + pointer-only/value-embedding classification
6. `emitIncludes` preamble (c89_emit.zig:706-711) — currently emits `zig_compat.h` + `zig_runtime.h` into stdout. With per-module output: include them in `zig_special_types.h` once, plus in each module `.h` (guard-protected, benign duplication per 08:751-755)

**Steps:**
- [ ] Read source + tech docs (03/08)
- [ ] Trace `classifyTypeEmissionGroups` for lisp_interpreter_curr — identify CLS:v (value-embedding) vs CLS:p (pointer-only) sets `[gdb]`
- [ ] Verify guard-macro naming: `c_name_id` from `Type` struct, FNV-1a name mangler scheme
- [ ] Write report with partition algorithm, guard scheme, exact edit targets
- [ ] Empty checkpoint commit `bugfix: IM4 research report for shared header partitioning`

---

### Task I-M5: Research emission loop restructuring

**Files:**
- Read: `sf/src/c89_emit.zig`, `sf/src/main.zig`
- Create: `.superpowers/sdd/IM5-report.md`

**Investigation:**
1. `emitModule` (c89_emit.zig:1600-1665) — currently single-call, hardcoded name `"output"`. Restructure: signature takes `module_id` + fn slice, emits one module's `.c` + `.h`. `main()` wrapper (c89_emit.zig:1623-1662) only in root module's `.c`
2. `phase_C89Emission` (main.zig:603-630) — restructure from single-emit to per-module loop:
   - When `--output-dir` set: emit shared `zig_special_types.h` once (consuming IM4 partition) → loop modules (`moduleRegistryGetModules`) → for each: emit `.h` + `.c` via `emitModule`, open/close BufferedWriter per file (IM3 PAL API)
   - When no `--output-dir`: keep current stdout single-file path (byte-identical gate preserved)
3. Fn grouping: slice `ctx.lir_fns` by `LirFunction.module_id` (lir.zig field, set at main.zig:572). Each module only gets its own functions. `emitModuleHeader` fwd-decl block (c89_emit.zig:1558-1593) becomes per-module (only that module's fns)
4. `emitIncludes` — currently per-compilation (c89_emit.zig:706-711, called from main.zig:622). Become per-module (each `.h` includes its own `@cInclude` directives from `ModuleEntry.c_includes`). Or move entirely to `zig_special_types.h` (runtime headers + compat)
5. Marker preservation: `FINAL_FLUSH` (main.zig:628) becomes per-file; `E2A`/`E2B` markers in shared header pass; `C` phase marker unchanged
6. `FNL` marker (lower.zig:4108) already per-fn — unaffected. Per-module `M<id>` (main.zig:535) already exists — reusable

**Steps:**
- [ ] Read source + tech docs (08/09)
- [ ] fprintf on `emitModule` entry + fn loop to confirm emission order per module `[fprintf]`
- [ ] Design `emitModule` new signature + `phase_C89Emission` new loop with file:line targets
- [ ] Write report with exact code structure, all call-site changes, marker adjustments
- [ ] Empty checkpoint commit `bugfix: IM5 research report for emission loop restructuring`

---

### Task I-M6: Research CLI activation + gate adaptation

**Files:**
- Read: `sf/src/main.zig`, `docs/sf/QUICK_REF.md`, all 18 `examples/z98/*/NOTES.md`
- Create: `.superpowers/sdd/IM6-report.md`

**Investigation:**
1. `--output-dir`/`-o` flag — already parsed (main.zig:706-710) but NEVER consulted by any phase. Activate: `phase_C89Emission` reads `ctx.cli.output_dir`. Default remains `"."` (parsed default). Behavior: `--dump-c89 --output-dir DIR` → multi-file to DIR; bare `--dump-c89` → stdout single-file (current). `--output-dir` without `--dump-c89` → still requires `--dump-c89` (don't change the gate contract)
2. Gate adaptation — byte-identical gate SUSPENDED (new hashes by design). Corpus gate: `gcc -c single.c` harness becomes `gcc -c DIR/*.c` → link → classify by gcc exit code. Must confirm corpus baseline remains 176/8/0/0 after harness change
3. 18-example gate — for each NOTES.md: update zig1 recipe to include `--output-dir DIR` → build each `.c` + link → run → compare output. Standard recipe: `zig1 --dump-c89 --output-dir /tmp/out <entry>` → `gcc -m32 -std=c89 -c /tmp/out/*.c` → `gcc -m32 *.o sf/src/include/*.c -o /tmp/out/prog` → run. Each NOTES.md updated with new recipe
4. zig0 bootstrap compatibility — the bootstrap recipe in QUICK_REF uses `./sf/build/zig0 --header-priority-include -o /tmp/z1/zig1.c sf/src/main.zig` which already produces per-module `.c`/`.h`. No change needed — zig0 is the oracle
5. Test harness — existing `build_test.sh` tests function under single-file `--dump-c89`. Adapt or skip (test harness is secondary to corpus + example gates)
6. QUICK_REF.md update — new "Multi-Module Build" section: `zig1 --dump-c89 --output-dir DIR <entry>` + gcc recipe per example

**Steps:**
- [ ] Read 18 NOTES.md + QUICK_REF
- [ ] Simulate the new harness on lisp_interpreter_curr (10 modules) — confirm N `.c` files, gcc -c all, link, run `[c89]`
- [ ] Simulate corpus gate on a few repros — confirm classifier works with per-file `.c` `[c89]`
- [ ] Write report with exact CLI behavior, gate recipe changes, NOTES.md update plan
- [ ] Empty checkpoint commit `bugfix: IM6 research report for CLI and gates`

---

### Task F-A: Implement multi-module C89 emission (Option A)

**Files:**
- Modify: `sf/src/c89_emit.zig` (BufferedWriter sink, emitSpecialTypes partition, emitModule restructure)
- Modify: `sf/src/main.zig` (phase_C89Emission loop, CLI activation, `--output-dir` consumption)
- Modify: `sf/src/pal.zig` (file_open/file_write/file_close API)
- Modify: `sf/src/include/zig_pal.c` (POSIX file I/O implementation)
- Possibly modify: `sf/src/module_registry.zig` (cap increase if needed)
- Update: `sf/docs/tech_docs/08_c89_emission.md`, `09_pipeline_orchestration.md`, `01_import_resolution.md`
- Update: all 18 `examples/z98/*/NOTES.md` (new multi-module build recipes)

**Pre-requisites:** All 6 I-reports (IM1–IM6) with exact edit targets (file:line). F-A consumes ALL of them.

**Implementation per I-reports:**

- [ ] **Step 1:** Write failing test — assert `--dump-c89 --output-dir DIR` produces N `.c` + N `.h` + 1 `zig_special_types.h` for a multi-module input
- [ ] **Step 2:** Implement PAL file I/O (IM3) + BufferedWriter sink (IM3)
- [ ] **Step 3:** Implement shared header partitioning (IM4) — generate `zig_special_types.h`
- [ ] **Step 4:** Implement per-module `.h` emission (IM1 — type ownership, IM2 — import ordering)
- [ ] **Step 5:** Implement per-module `.c` emission (IM5 — `emitModule` restructure, fn grouping, per-module `@cInclude`, `main()` wrapper placement)
- [ ] **Step 6:** Implement CLI activation + `phase_C89Emission` loop (IM5 + IM6)
- [ ] **Step 7:** Gate: corpus 184 repros (each `.c` compiles standalone → link → gcc exit code classifies). Target: 176/8/0/0
- [ ] **Step 8:** Gate: all 18 Z98 examples build per-module → link → run → output matches NOTES.md reference
- [ ] **Step 9:** Gate: byte-identical gate re-baseline — recapture man/gol/lisp/json hashes with new output format
- [ ] **Step 10:** Update NOTES.md for all 18 examples with new multi-module recipes
- [ ] **Step 11:** Update QUICK_REF.md — add Multi-Module Build section, re-baseline hashes
- [ ] **Step 12:** Update tech docs 08/09/01 with new evidence `[c89]` + `[markers]` (emission loop, CLI activation, type ownership tables)
- [ ] **Step 13:** Commit `feat: FA implement multi-module C89 emission`

---

## Execution Notes

- **Execution order:** IM1 → IM2 → IM3 → IM4 → IM5 → IM6 → F-A. IM1 establishes type ownership (depended on by IM4). IM2 establishes import ordering (depended on by IM5). IM3 is independent (PAL API). IM4 depends on IM1. IM5 depends on IM2 + IM4. IM6 is independent (read-only, gates) but ran last before F-A to update all edge-case recipes.
- **I-tasks SUBAGENT-DISPATCHED** — one subagent per I-task. Empty checkpoint commits. Reports are the deliverables.
- **F-A SUBAGENT-DISPATCHED** — consumes all 6 I-reports from `.superpowers/sdd/IM1-report.md` through `IM6-report.md`. Must read ALL 6 before implementing.
- **I-task review gates:** Each I-task reviewed (spec + quality) before the next I-task dispatches. Clean review = ledger update, proceed to next.
- **After IM6, BEFORE F-A:** controller presents all 6 I-report summaries to operator for go/no-go.
- **Compression FORBIDDEN during execution** — per operator standing order.
