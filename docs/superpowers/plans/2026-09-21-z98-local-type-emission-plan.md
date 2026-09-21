# Z98 Function-Local / Inline Type Emission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make function-local / inline named types (`const E = enum {…};` / `struct` / `union` / `error{…}` declared inside a function or as an inline type expression) emit valid C, or cleanly reject — never emit C that fails to compile.

**Architecture:** Two tasks. **B1 (I)** investigates the registration/emission path for function-local and inline named types and decides emit-properly vs clean-reject, covering `enum`, `struct`, `union`, and error-set declarations, and documents the divergence. **B2 (F)** implements the B1 design with fixtures, gates, and a seed rotation.

**Tech Stack:** the self-hosted Z98 compiler (`sf/src`), the seed build model, `gcc -m32`, the `repro/mi_matrix` corpus.

**Spec:** `docs/superpowers/specs/2026-09-20-z98-manual-phase0-design.md` (AMENDMENT 17 records this plan's origin).

## Global Constraints

- Only the tasks in this plan may touch `sf/src`; each fix ships a `repro/mi_matrix/` fixture + standalone `repro/` + a `scripts/stdlib/expected_dirs.txt` pin + a seed rotation + tech-doc updates (AGENTS §1.1.1) + `EXPECTED_FAIL.md`/`QUICK_REF.md` updates.
- Run the QUICK_REF gate battery verbatim; **STOP and present on any unexpected gate movement**.
- Official Zig is the authority for validity; the C++ bootstrap is *not* authoritative.
- `edit`/`fastedit` only; no dead code; no duplicated logic.

---

### Task B1 (I): Investigate function-local / inline named-type emission

**Files:**
- Read (no edits): `sf/src/semantic_analyzer.zig`, `sf/src/symbol_registrator.zig`, `sf/src/type_registry.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`.
- Create: the findings report (SDD workspace; not committed).

**Context:** a function-local or inline named type emits invalid C. `fn f() void { const E = enum(u8){A=1,B}; var e: E = E.A; }` dumps rc=0 but gcc fails `unknown type name 'zT_…_type'`. Root: `semanticAnalyzerResolveExpr`'s `enum_decl`/`struct_decl`/`union_decl`/`error_set_decl` arm (`sf/src/semantic_analyzer.zig:2699-2702`) returns `TYPE_TYPE` without registering a named type, and `lower.zig:6585` lowers the initializer as a value local of `TYPE_TYPE`, which the emitter mangles. Module-level named types are registered by `symbol_registrator.zig` (only walks module `ast_root` children), so function-local decls never register. This reproduces on the base commit `f7f5df61` (pre-existing).

- [ ] **Step 1: Reproduce** for `enum`, `struct`, `union`, and error-set declarations in function-local and inline positions; capture the exact emitted-C failure for each.
- [ ] **Step 2: Locate the gaps** — where local named types are (or are not) registered and emitted, and why `TYPE_TYPE` leaks into lowering.
- [ ] **Step 3: Establish official-Zig validity** for each kind (function-local `const T = struct/enum/union/error{…}` and inline type expressions) and **document the divergence**: official Zig allows local types; the C++ bootstrap (`src/bootstrap/type_checker.cpp:3827`) rejects them.
- [ ] **Step 4: Decide and specify** — emit properly (register a synthesized name_id + payload + emit the typedef) vs clean-reject, per kind; the exact algorithm and edit sites; blast radius (fixed point/seed, gates, fixtures).
- [ ] **Step 5: Recommend the B2 verification plan** — fixtures (positive + any reject controls), gates, runtime guard.
- [ ] **Step 6: Report.** **No `sf/src` edits, no source commit.**

---

### Task B2 (F): Emit or cleanly reject function-local / inline named types

**Files (confirm against the B1 report):** `sf/src/semantic_analyzer.zig`, `sf/src/symbol_registrator.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`; `repro/mi_matrix/` fixtures; `repro/`; tech docs; seed rotation iff the fixed point moves.

- [ ] **Steps 1–7:** implement per B1; verify each kind emits valid C (or cleanly rejects); leave the reproductions; run the QUICK_REF gate battery verbatim (STOP on unexpected gate movement); rotate the seed iff the fixed point moves; update tech docs; commit `fix(types): support function-local named types` (or the B1-recommended message).

---
