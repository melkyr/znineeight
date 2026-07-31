# Multi-Module C89 Emission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Research and implement per-module `.c`/`.h` emission in zig1's C89 backend, matching the design spec and zig0's output pattern.

**Architecture:** One I-task (research + report) followed by one F-task (implementation). I-task reads the design oracle (`docs/sf/LIR_C89_Emission_p2.md`) AND the 6 as-built tech docs from the P1-P10 deep-dive (`sf/docs/tech_docs/`). F-task produces the code changes per I-report recommendations.

**Tech Stack:** zig1 binary at `sf/build/out_release/zig1`, z98-compatible Z98 for source edits.

## Required Reading

| Doc | Role | Key deep-dive evidence |
|-----|------|------------------------|
| `docs/sf/LIR_C89_Emission_p2.md` | Design oracle (spec) | Two-phase output contract, instruction→C89 mapping, name mangling scheme |
| `sf/docs/tech_docs/08_c89_emission.md` | As-built (empirical) | Per my P8 deep-dive: actual emission loop at c89_emit.zig:1605-1611, emitSpecialTypes+emitModule call sequence, E2A/E2B type-pass markers, MARKER_* comment sites (:2299/2551/3130), typedef topo order evidence, @cInclude collection at `main.zig:625`, preamble double-include, main-wrapper emission (:1198 etc.) |
| `sf/docs/tech_docs/09_pipeline_orchestration.md` | As-built (empirical) | Per my P10 deep-dive: runCompiler phase sequencing, CLI flag table (:64-84 main.zig parseArgs), arena peaks, DepGraph lifecycle, `--dump-c89` gating at `main.zig:604` |
| `sf/docs/tech_docs/03_type_resolution.md` | As-built (empirical) | Per my P3 deep-dive: pointer_only_ids classification (which types go to shared .h vs per-module .h), TypeId→kind mapping, value_embedding_ids sets |
| `sf/docs/tech_docs/01_import_resolution.md` | As-built (empirical) | Per my P1 deep-dive: module graph per example, import_edges (`module_registry.zig:244-250`), ModuleEntry struct, module state transitions |
| `sf/docs/tech_docs/07_lir_lowering.md` | As-built (empirical) | Per my P7 deep-dive: FNL per-fn marker at `lower.zig:4108`, LirInst variant distribution per example, temp hoisting D3HT |

## Global Constraints

- **Source changes allowed** — this plan MODIFIES `sf/src/c89_emit.zig`, `sf/src/main.zig`, and related files
- **Byte-identical gate suspended** — multi-module output changes the emission format (new hashes expected, behavior preserved)
- **Corpus gate:** 184 repros, OK=176 FAIL=8 ICE=0 CRASH=0 (gcc exit-code classifier)
- **Runtime gate:** all 18 Z98 examples build + link + run correctly
- **fastedit/edit only for source edits** — per AGENTS.md §X.7
- **Commit per task**
- **Follow QUICK_REF.md for build/run commands**
- **Plan says A, you do A** — STOP on ambiguity, present to operator

---

### Task I-A: Research multi-module emission strategy

**Files:**
- Read: `sf/src/c89_emit.zig`, `sf/src/main.zig`, `sf/src/module_registry.zig`
- Create: `.superpowers/sdd/IA-report.md` (research report)

**Research questions:**

1. **Current emission loop.** How does `emitModule` (c89_emit.zig:1605) iterate? What does `emitSpecialTypes` produce? What's the current `BufferedWriter` file model (single stdout)? **Cross-ref:** `08_c89_emission.md` §6.5 (2-phase output evidence), §6.1 (typedef topo order).

2. **Module ownership.** Which types/functions belong to which module? How does `module_registry.zig` track module boundaries? What's the `ModuleEntry.symbol_table` → module mapping? **Cross-ref:** `01_import_resolution.md` §6.1 (module graph tables), `03_type_resolution.md` §6.1 (TypeId→module mapping).

3. **Include order.** How do we compute each module's direct imports? (import edges in module_registry → topological sort). What types are shared (slices, optionals, error unions) vs per-module (structs, enums)? **Cross-ref:** `03_type_resolution.md` §6.4 (pointer-only classification, CLS:v/CLS:c sets).

4. **File I/O.** How does zig0 produce multiple files? Does `BufferedWriter` support file handles? Can we open/close per-module output files? **Cross-ref:** `09_pipeline_orchestration.md` §6.1 (arena peaks during C89 phase), QUICK_REF bootstrap recipe (35 `.c` files from zig0).

5. **zig_special_types.h.** What types go in the shared header vs per-module `.h`? **Cross-ref:** `03_type_resolution.md` §6.4 (value-emitted types = go in shared header; pointer-only = forward-declarable), `08_c89_emission.md` §6.1 (E2A pointer-only pass vs E2B value-embedding pass).

6. **main.zig.** What CLI flag is needed? (`--output-dir` / `-o`). How does the pipeline invoke per-module emission? **Cross-ref:** `09_pipeline_orchestration.md` §4 (CompilerCli struct fields), `08_c89_emission.md` §6.4 (fn body emission order = source order per module).

7. **zig0 comparison.** Verify zig0's per-module `.c` + shared `.h` pattern. What does zig0's `--header-priority-include` do? **Cross-ref:** QUICK_REF Bootstrap Build section (35 per-module `.c`).

**Steps:**
- [ ] **Step 1:** Read all 6 tech docs listed in Required Reading above (08/09/03/01/07 + design oracle). Each doc carries deep-dive evidence annotated `[gdb]`/`[fprintf]`/`[markers]` — the IA-report MUST cross-reference these findings with file:line.
- [ ] **Step 2:** Read `c89_emit.zig` emission loop (`emitModule` :1605-1611, `emitSpecialTypes`, `BufferedWriter`) + `main.zig` pipeline (`phase_C89Emission` :602-627, CLI parseArgs :631-762)
- [ ] **Step 3:** Read `module_registry.zig` for module ownership model (`ModuleEntry`, `import_edges`, `moduleRegistryGetModules`)
- [ ] **Step 4:** Study zig0's multi-file output pattern (`./sf/build/zig0 --header-priority-include -o /tmp/z1/zig1.c sf/src/main.zig` produces 35 `.c` files per the QUICK_REF bootstrap recipe). Inspect: shared `.h`, per-module `.c`, include structure.
- [ ] **Step 5:** GDB/fprintf on zig1 at `emitModule` entry to trace per-module call sequence `[gdb]` — cross-reference with P8's E2A/E2B marker evidence in `08_c89_emission.md:693-706`
- [ ] **Step 6:** Write IA-report with Option A/B/C, exact edit targets (file:line), blast radius (callers, gate impact, doc updates). Every claim must cite evidence from the tech docs.
- [ ] **Step 7:** Commit empty checkpoint `bugfix: IA research report for multi-module emission`

**Interfaces:**
- Produces: `IA-report.md` with exact edit targets for `c89_emit.zig`, `main.zig`, `module_registry.zig`

---

### Task F-A: Implement multi-module C89 emission

**Files:**
- Modify: `sf/src/c89_emit.zig` (multi-file emission, per-module BufferedWriter)
- Modify: `sf/src/main.zig` (CLI flag `--output-dir`, per-module display loop)

**Implementation per IA-report recommendations:**

- [ ] **Step 1:** Write failing test — assert output dir produces N `.c` files for a multi-module input
- [ ] **Step 2:** Implement per IA-report
- [ ] **Step 3-6:** Gates — unit → 18 examples (build each `.c` independently → link → run) → corpus 184/176/8/0/0
- [ ] **Step 7:** Update tech doc `08_c89_emission.md` + `09_pipeline_orchestration.md`
- [ ] **Step 8-9:** Report + commit `feat: FA implement multi-module C89 emission`
