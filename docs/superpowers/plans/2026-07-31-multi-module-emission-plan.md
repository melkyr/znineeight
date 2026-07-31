# Multi-Module C89 Emission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Research and implement per-module `.c`/`.h` emission in zig1's C89 backend, matching the design spec and zig0's output pattern.

**Architecture:** One I-task (research + report) followed by one F-task (implementation). I-task studies the emitter loop, module ownership, cross-module include ordering, and build script generation. F-task produces the code changes.

**Tech Stack:** zig1 binary at `sf/build/out_release/zig1`, z98-compatible Z98 for source edits, `docs/sf/LIR_C89_Emission_p2.md` as design oracle.

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

1. **Current emission loop.** How does `emitModule` (c89_emit.zig:1605) iterate? What does `emitSpecialTypes` produce? What's the current `BufferedWriter` file model (single stdout)?

2. **Module ownership.** Which types/functions belong to which module? How does `module_registry.zig` track module boundaries? What's the `ModuleEntry.symbol_table` → module mapping?

3. **Include order.** How do we compute each module's direct imports? (import edges in module_registry → topological sort). What types are shared (slices, optionals, error unions) vs per-module (structs, enums)?

4. **File I/O.** How does zig0 produce multiple files? Does `BufferedWriter` support file handles? Can we open/close per-module output files?

5. **zig_special_types.h.** What types go in the shared header vs per-module `.h`? (P3 deep-dive: pointer_only_ids vs value_embedding_ids)

6. **main.zig.** What CLI flag is needed? (`--output-dir` / `-o`). How does the pipeline invoke per-module emission?

7. **zig0 comparison.** Verify zig0's per-module `.c` + shared `.h` pattern. What does zig0's `--header-priority-include` do?

**Steps:**
- [ ] **Step 1:** Read `c89_emit.zig` emission loop + `main.zig` pipeline orchestration
- [ ] **Step 2:** Read `module_registry.zig` for module ownership model
- [ ] **Step 3:** Study zig0's multi-file output (`find /tmp/z1 -name '*.c' | wc -l`, inspect includes)
- [ ] **Step 4:** GDB/fprintf on zig1 to trace `emitModule` call sequence `[gdb]`
- [ ] **Step 5:** Write IA-report with Option A/B/C, edit targets (file:line), blast radius
- [ ] **Step 6:** Commit empty checkpoint `bugfix: IA research report for multi-module emission`

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
