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

### Task F-S1: PAL File I/O + BufferedWriter fd sink (IM3)

**Files:**
- Modify: `sf/src/include/zig_pal.c` (+fcntl.h, +pal_file_open/write/close)
- Modify: `sf/src/pal.zig` (+externs, +fileOpen/fileWrite/fileClose wrappers)
- Modify: `sf/src/c89_emit.zig` (BufferedWriter.fd field, bufferedWriterInitFd, flush→fileWrite, emitZigPalC sync)
- Modify: `sf/scripts/build_release.sh` (+link `sf/src/include/zig_pal.c` into zig1)
- Update: all docs describing how zig1 is built (QUICK_REF.md manual bootstrap recipes, AGENTS.md §2.2/§9.3, `docs/Building.md`, `sf/docs/tech_docs/10_c_runtime.md`, `sf/docs/tech_docs/11_build_system.md`)

**Pre-requisite:** IM3-report.md §D (exact code for zig_pal.c + pal.zig + BufferedWriter changes).

**Scope — ONLY PAL I/O + its link/build wiring + build docs. No emission restructuring. No shared header. No main.zig changes.**

- [ ] **Step 1 — zig_pal.c:** Add `#include <fcntl.h>` after `<unistd.h>` in non-Win32 block. Add `pal_file_open` (POSIX open/Win32 CreateFileA), `pal_file_write` (partial-write loop), `pal_file_close` (close/CloseHandle) after `pal_f64_to_str`, before footer. Exact C code from IM3-report.md §D.1.
- [ ] **Step 2 — pal.zig:** Add 3 `extern "c" fn pal_file_open/write/close(...)` declarations (pattern: pal.zig:5-10). Add `pub fn fileOpen/fileWrite/fileClose` wrappers (pattern: pal.zig:59-65, c_path copy:17-24). Path length cap 511.
- [ ] **Step 3 — BufferedWriter (c89_emit.zig:27-73):** Add `fd: i32` to struct (after pos). `bufferedWriterInit` sets `.fd = @intCast(i32, 1)`. Add `pub fn bufferedWriterInitFd(fd: i32) BufferedWriter`. `bufferedWriterFlush (:36-42)`: change `pal.stdout_write(self.buf...)` to `pal.fileWrite(self.fd, self.buf...)`. Keep FL:p/FE:p markers.
- [ ] **Step 4 — emitZigPalC (c89_emit.zig:724-738):** Update embedded string literals to include pal_file_open/write/close (match updated zig_pal.c). The h12 footer moves to h13.
- [ ] **Step 5 — build_release.sh link (OPERATOR RULING 2026-08-01):** Append `"$ROOT_DIR/src/include/zig_pal.c"` to the gcc link line so zig1 itself links the PAL (which defines the new `pal_file_*` symbols). Without this, `pal.zig`'s new externs are undefined at zig1 link time. (Discovered by F-S1: `zig_pal.c` is only linked into *generated programs*, never into zig1. Option A chosen over `zig_runtime.c` duplication.)
- [ ] **Step 6 — build docs (OPERATOR RULING 2026-08-01):** Update EVERY manual zig1 build recipe to include `sf/src/include/zig_pal.c` in the gcc link (someone manually compiling would otherwise hit the same undefined-reference error): QUICK_REF.md bootstrap recipes (:81-85, :99-105, :164-167), AGENTS.md §2.2/§9.3, `docs/Building.md`, `sf/docs/tech_docs/10_c_runtime.md`, `sf/docs/tech_docs/11_build_system.md`.
- [ ] **Step 7 — Gate:** `bash sf/scripts/build_release.sh` → 0 zig0 errors + gcc 0 errors + `[release] Done`. `sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum` == `0ad0204088f91c1eae7c040da8f99a1c` (byte-identical fd=1 path). Verify fd=1 byte-identity: compile+run any example, output matches reference. `nm sf/build/out_release/zig1 | grep pal_file_` shows all three defined once, no conflicts.
- [ ] **Step 7b — build_test.sh link (OPERATOR RULING 2026-08-01):** Append `"$ROOT_DIR/src/include/zig_pal.c"` to the gcc link line in `sf/scripts/build_test.sh` (after `$c_files`). Without this, all 9 test binaries FAIL to link (undefined `pal_file_*` from emitted `pal.c`). Update any doc recipe referencing build_test.sh (QUICK_REF "Build and Run Tests", AGENTS.md §9.2) to note the link. Verify: `bash sf/scripts/build_test.sh` → all 9 PASS.
- [ ] **Step 8 — Commit checkpoint:** `build: F-S1 PAL file I/O + BufferedWriter fd sink + zig_pal link`

**STOP HERE — do not proceed to F-S2 unless all gates pass.**

---

### Task F-S2: Shared Header `zig_special_types.h` Generation (IM1 + IM4)

**Files:**
- Modify: `sf/src/c89_emit.zig` (tstTopologicalSort→pub, computeSharedSet, emitSharedHeader, ctypeGuardWrite, shared_set on C89Emitter, emitSpecialTypes signature change)
- Modify: `sf/src/main.zig` (output_dir_set field, emitSharedHeader call when --output-dir set)

**Pre-requisites:** F-S1 DONE + IM1-report.md §D + IM4-report.md §D.

**AMENDMENT 1 (operator confirmed):** Add `kind == fn_type(24)` to shared_set initial seed. fn types have `name_id != 0` but `module_id == 0` — partition drops them otherwise. They go to shared header.

**AMENDMENT 2 (operator confirmed):** Add `output_dir_set: bool` field to CompilerCli struct (default false, set true when --output-dir/-o parsed at main.zig:706-710). Branch on this bool, NOT on `output_dir != "."` sentinel.

**Scope — ONLY: shared header generation infrastructure. Per-module .h/.c emission NOT in this stage.**

- [ ] **Step 1 — tstTopologicalSort → pub (c89_emit.zig:846):** Change `fn` → `pub fn`.
- [ ] **Step 2 — emitSpecialTypes signature (c89_emit.zig:884):** Change to `pub fn emitSpecialTypes(emitter: *C89Emitter, reg: *TypeRegistry, sorted: [*]u32) void`. Delete internal sort call at :885. In emitModule (:1602), call `tstTopologicalSort` then pass result to emitSpecialTypes.
- [ ] **Step 3 — shared_set on C89Emitter (c89_emit.zig:457):** Add `shared_set: U32ToU32Map` field. Init in c89EmitterInit with `hash_mod.u32ToU32MapInit(alloc)`.
- [ ] **Step 4 — ctypeGuardWrite (new fn in c89_emit.zig):** Writes `ZIG_<TAG>_` prefix for each TypeKind. Tag table from IM4-report.md §A Q2: struct/tagged_union→ZIG_STRUCT_, union→ZIG_UNION_, enum→ZIG_ENUM_, error_set→ZIG_ERROR_SET_, slice→ZIG_SLICE_, optional→ZIG_OPTIONAL_, error_union→ZIG_ERRORUNION_, array→ZIG_ARRAY_, fn_type→ZIG_FNPTR_, i64→ZIG_I64_, u64→ZIG_U64_.
- [ ] **Step 5 — computeSharedSet (new fn in c89_emit.zig):** Seed: synthetics (name_id==0 passing 2a/2b allow-list) ∪ CLS:v (pointer_only_map miss) ∪ i64/u64 ∪ fn_type(24) named (AMENDMENT 1). Closure: add named CLS:p types by-value-referenced by shared_set members (via tstIsDep, c89_emit.zig:821-844). Iterate to fixpoint over FINAL reg.types_len.
- [ ] **Step 6 — emitSharedHeader (new pub fn in c89_emit.zig):** Calls computeSharedSet. Opens output file via pal.fileOpen(output_dir ++ "/zig_special_types.h"). File guard ZIG_SPECIAL_TYPES_H. Preamble: #include zig_compat.h + zig_runtime.h. Unfiltered fwd-decl pass (typedef struct X X; for every named struct/TU/union). Sub-pass 2a filtered to shared_set (each typedef guarded ZIG_<TAG>_<cname>). Sub-pass 2b entirely. End guard. Flush+close. E2A/E2B/ESTA/ESTB markers preserved.
- [ ] **Step 7 — main.zig CompilerCli (Amendment 2):** Add `output_dir_set: bool` field (after output_dir at :62). Init to `false` in parseArgs struct init (:637 area). Set `cli.output_dir_set = true` in the --output-dir/-o parse branch (:706-710).
- [ ] **Step 8 — main.zig phase_C89Emission:** After emitter init (:617), add branch: if `ctx.cli.output_dir_set` AND `ctx.cli.dump_c89`: run `tstTopologicalSort` once, call `emitSharedHeader`, keep stdout path afterward. Else: keep :618-629 verbatim (stdout unchanged). Note: per-module loop NOT wired yet.
- [ ] **Step 9 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. `sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/s2 examples/z98/lisp_interpreter_curr/main.zig` → produces `/tmp/s2/zig_special_types.h` (non-empty, gcc-compiles standalone). `sf/build/out_release/zig1 --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum` == `0ad0204088f91c1eae7c040da8f99a1c` (stdout unchanged). Verify guards are `#ifndef ZIG_<TAG>_<cname>` format.
- [ ] **Step 10 — Commit checkpoint:** `build: F-S2 shared header zig_special_types.h generation`

**STOP HERE — do not proceed to F-S3 unless all gates pass.**

---

### Task F-S3: Per-Module `.h` Emission (IM1 + IM2 + IM4)

**Files:**
- Modify: `sf/src/c89_emit.zig` (emitModuleHeaderFile: module guard, dep includes, owned CLS:p type defs, fn fwd-decls)
- Modify: `sf/src/main.zig` (module loop for .h files only — NOT .c files)

**Pre-requisites:** F-S2 DONE + IM1-report.md §D + IM2-report.md §D + IM4-report.md §D.

**Scope — ONLY per-module .h files. Per-module .c files NOT in this stage.**

- [ ] **Step 1 — Add mr_mod import to c89_emit.zig:** `const mr_mod = @import("module_registry.zig");` after existing imports. Verify no circular import (module_registry.zig must NOT import c89_emit.zig).
- [ ] **Step 2 — emitModuleHeaderFile (new pub fn in c89_emit.zig):** Signature takes `emitter, mod_name, fns, c_includes, dep_mod_ids, sorted`. Module file guard `#ifndef ZIG_MODULE_<NAME>_H` (NAME = uppercased basename, non-alnum→_). Include zig_compat.h + zig_special_types.h. Per-module @cInclude from c_includes (use existing logic :1564-1582). Dep .h includes from dep_mod_ids (skipping self, bare basename). Per-module owned CLS:p type defs: iterate sorted, emit full defs with guards for `name_id!=0 && module_id==M.id && kind in {struct(25),tu(28),union(27),enum(26),error_set(23)} && pointer_only_map && NOT in shared_set`. Fn fwd-decls for module's non-extern fns. End guard.
- [ ] **Step 3 — main.zig per-module loop (.h only):** Extend F-S2's branch: after emitSharedHeader, loop `mr_mod.moduleRegistryGetModules(ctx.module_reg)`. For each module M: derive basename from path_id (after last /, strip .zig/.z98). Build dep module ids from import_edges_items[M.imports_start .. M.imports_start+M.import_count]. Build M's fn slice (scan ctx.lir_fns for contiguous module_id block). Open `<output_dir>/<basename>.h`: fd=pal.fileOpen(path,0), on -1: diag+pal.exit(1). emitter.writer = bufferedWriterInitFd(fd). emitModuleHeaderFile. Flush. Close. Do NOT emit .c files yet.
- [ ] **Step 4 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. `zig1 --dump-c89 --output-dir /tmp/s3 examples/z98/lisp_interpreter_curr/main.zig` → produces 10 .h files + zig_special_types.h (NO .c files). Each .h gcc-compiles standalone: `gcc -m32 -std=c89 -c -I sf/src/include -o /dev/null -x c <file>.h`. main.h `#include`s dep .h basenames in order. Bare --dump-c89 md5 unchanged.
- [ ] **Step 5 — Commit checkpoint:** `build: F-S3 per-module .h emission`

**STOP HERE — do not proceed to F-S4 unless all gates pass.**

---

### Task F-S4: Per-Module `.c` Emission (IM5)

**Files:**
- Modify: `sf/src/c89_emit.zig` (extract emitMainWrapper, add emitModuleFile)
- Modify: `sf/src/main.zig` (complete .c emission in module loop)

**Pre-requisites:** F-S3 DONE + IM5-report.md §D.

**Scope — ONLY per-module .c files. This completes the emission pipeline.**

- [ ] **Step 1 — Extract emitMainWrapper (c89_emit.zig:1623-1662):** Move the inline main() wrapper block into `fn emitMainWrapper(emitter: *C89Emitter, func: LirFunction) void`. In emitModule (:1623), replace the inline block with `emitMainWrapper(emitter, func)` (keeping is_pub==1 && name=="main" guard around the call). **Gate:** build zig1, bare --dump-c89 lisp md5 == baseline. This must be behavior-neutral.
- [ ] **Step 2 — emitModuleFile (new pub fn in c89_emit.zig):** Signature `pub fn emitModuleFile(emitter: *C89Emitter, module_id: u32, mod_name: []const u8, fns: []LirFunction) void`. Write `#include "<mod_name>.h"\n`. Fn loop (mirror emitModule:1607-1663 minus type header+header calls): skip extern. set switch_cases. emitFunctionSignature. emitHoistedDecls. dl_hoisted=0. emitFunctionBody. Main wrapper: `if (module_id==0 && fns[i].is_pub==1 && name=="main") { emitMainWrapper(&fns[i]); }`. End with emitModuleFooter.
- [ ] **Step 3 — main.zig complete .c loop:** Extend F-S3's per-module loop. After .h flush+close: open `<output_dir>/<basename>.c`. emitter.writer = bufferedWriterInitFd(fd). emitModuleFile(...). Flush. Close. Per-file FINAL_FLUSH marker. Keep stdout branch (:618-629) verbatim.
- [ ] **Step 4 — Gate:** `bash sf/scripts/build_release.sh` → 0 errors. `zig1 --dump-c89 --output-dir /tmp/s4 examples/z98/lisp_interpreter_curr/main.zig` → 10 .c + 10 .h + zig_special_types.h. Each .c gcc-compiles standalone. Link all: `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/s4/*.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/s4/lisp`. Run: `printf '(+ 1 2)\n' | /tmp/s4/lisp` → `> 3`. Bare --dump-c89 md5 matches baseline.
- [ ] **Step 5 — Commit checkpoint:** `build: F-S4 per-module .c emission`

**STOP HERE — do not proceed to F-S5 unless all gates pass.**

---

### Task F-S5: Gate Sweep (Corpus + 18 Examples)

**Files:**
- No source changes. Gate harness scripts (scratch).

**Pre-requisite:** F-S4 DONE.

- [ ] **Step 1 — Corpus gate (184 repros):** For each tracked repro in `repro/mi_matrix/*/main.zig` (exclude `test_stub_0/`): `rm -rf $DIR && mkdir -p $DIR`, `zig1 --dump-c89 --output-dir $DIR <repro>`. Per-file gcc: `for f in $DIR/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c "$f" -o /dev/null || ok=0; done`. Classifier: dump rc≥128=CRASH, stderr error[(48|3042|9001)]=ICE, gcc rc==0=OK, else=FAIL. Target: OK=176 FAIL=8 ICE=0 CRASH=0. **STOP if any regression from baseline.**
- [ ] **Step 2 — 18 examples runtime:** For each `examples/z98/*/NOTES.md` entry: `zig1 --dump-c89 --output-dir /tmp/out <entry>`, `gcc -c /tmp/out/*.c` per-file, link with zig_runtime.c+zig_pal.c (+net_runtime.c for mud), run → output matches reference. 3 BROKEN stay BROKEN. **STOP if any passing example regresses.**
- [ ] **Step 3 — Stdout md5 preservation:** Bare `--dump-c89` on mud/gol/lisp/json → md5s match QUICK_REF baselines. DO NOT overwrite.
- [ ] **Step 4 — Commit checkpoint:** `build: F-S5 gate sweep verified`

**STOP HERE — do not proceed to F-S6 unless all gates pass.**

---

### Task F-S6: Documentation + Final Commit

**Files:**
- Update: all 18 `examples/z98/*/NOTES.md`
- Update: `docs/sf/QUICK_REF.md`
- Update: `sf/docs/tech_docs/08_c89_emission.md`, `09_pipeline_orchestration.md`, `01_import_resolution.md`, `00_shared_infra.md`

**Pre-requisite:** F-S5 DONE.

- [ ] **Step 1 — NOTES.md (18 files):** Replace zig1 dump + gcc recipe blocks with multi-module recipe: `mkdir -p /tmp/out`, `zig1 --dump-c89 --output-dir /tmp/out <entry>`, `gcc -m32 -std=c89 ... -I sf/src/include -c /tmp/out/*.c`, link with runtime. Preserve special cases: mud (+net_runtime.c), json_parser (legacy runtime), 3 BROKEN status N/A, non-main.zig entry names.
- [ ] **Step 2 — QUICK_REF.md:** Add "Multi-Module Build" section after byte-identical gate. Update corpus-gate gcc invocation to per-file loop. Keep stdout md5 baselines.
- [ ] **Step 3 — Tech docs:** Update 08 (BufferedWriter fd, shared header writer, guards), 09 (output_dir live, phase-8 per-module loop), 01 (dep .h include chain), 00_shared_infra (multi-module recipe). Annotate with `[updated: 2026-08-01]`.
- [ ] **Step 4 — Final commit:** `feat: implement multi-module C89 emission`

---

## Execution Notes

- **Execution order:** F-S1 → F-S2 → F-S3 → F-S4 → F-S5 → F-S6. Sequential. Each stage MUST complete its gate before the next stage begins. NO SKIPPING.
- **Stage-specific subagents:** One subagent per F-S stage. Fresh context. Each subagent reads its pre-requisite I-reports before implementing.
- **Gate enforcement:** After each stage, verify gates CLEAN. If any gate fails, STOP. Fix the current stage before proceeding. Do NOT accumulate unverified changes across stages.
- **Dirty state prevention:** If an early stage fails compilation, do NOT start editing the next stage's files. Fix the compilation error in the current stage's scope only.
- **Single commit per stage:** Each F-S task produces one checkpoint commit with its task label. F-S6 produces the final commit.
- **QUICK_REF.md consultation:** Every subagent MUST read `docs/sf/QUICK_REF.md` before any build/compile/run command. All recipes (build, compile+run, md5 check) come from QUICK_REF.
- **fastedit/edit only:** Source edits via `edit` or `fastedit`. Read target region before each edit. Edit bottom-to-top. No sed/python/bulk transforms. Per AGENTS.md §X.7.
- **Z98 string literal rule:** Always `var msg: []const u8 = "text";` before passing to PAL functions.
- **Compression FORBIDDEN during execution** — per operator standing order.
- **Plan says A, do A.** If ambiguity, STOP. No out-of-plan fixes.
