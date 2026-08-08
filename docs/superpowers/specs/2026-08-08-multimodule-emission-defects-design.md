# Multi-Module Emission Defects + Arena Self-Compile Fixes Design Spec

**Date:** 2026-08-08
**Status:** Approved by operator. Amended after R1 + I1-I5 findings + operator rulings (m0368, m0379, m0381). Ready for plan.

## 1. Goal

Fix the confirmed compiler defects so all 21 z98 examples compile end-to-end (dump → gcc → run) via `--dump-c89 --output-dir DIR`: D1 @ptrToInt void, D3 cross-module enum-member resolution, D6 cross-module tagged-union `==` SEGV. Resize the static arenas to enable zig1 self-compile within the 16 MB hardware limit. Document D2 (extern arena symbols) and D4 (plat_ console stubs) as deferred to the std-lib plan.

## 2. Problem Statement

A full 21-example compilation matrix (MEM4, `.superpowers/sdd/MEM4-full-example-matrix.md`) found 16/21 work end-to-end; 5 don't pass the full cycle. R1 repros + I1-I5 investigations (reports in `.superpowers/sdd/`) corrected and confirmed the defect list:

| # | Defect | Confirmed status | Examples affected | Symptom |
|---|---|---|---|---|
| D1 | `@ptrToInt` returns void | **CONFIRMED** — sema `:1289-1292` dead code under `ec.len >= 2`; single-arg falls through returning arg type | lisp_interpreter (dump rc=2) | `error[3000]: cannot declare variable of type void` |
| D2 | Modules silently dropped | **FALSE — does NOT reproduce.** All modules emit in all probed graph shapes. Real gap: extern `arena_alloc_default` (class (b) runtime-library) | json_parser | gcc link: undefined reference to arena_alloc_default |
| D3 | Missing type forward-decls | **CONFIRMED, different trigger** — sema/lowering gap: cross-module plain-enum member → TYPE_VOID. NOT header fwd-decl | json_parser_workaround (6× zT_xx undeclared) | gcc compile: `'zT_NN' undeclared` |
| D4 | Missing platform stubs | **CONFIRMED** — 12 socket symbols exist; 5 console/platform missing; zig0 fails identically (runtime gap) | rogue_mud | gcc link: plat_is_windows, plat_console_* |
| D6 | Cross-module tagged-union `==` | **CONFIRMED (I3 separate finding)** — SEGVs the compiler | (repro R2) | compiler crash |

The single-file emission path is solid (14/14 single-file examples pass). The gaps are in the multi-module path.

Additionally, zig1 self-compile is blocked by the static module arena (allocator.zig:75) which OOMs during `phase_ImportResolution`. MEM3 verdict: the earlier "zig1 3× zig0 memory" was an **ASan artifact** — ASan-free zig1 beats zig0 on all 12 examples. The true blocker is architectural: static arena caps. I5: per-module reset infeasible (module arena is a program-lifetime cross-module store; OOM fires in phase-1 import before emission); resize to perm 4MB / module 8MB / scratch 2MB → projected self-compile RSS ~12-14MB within 16MB.

## 3. Architecture

**Phase 1 — R (repros):** R1 (4 repros + rogue_mud NOTES.md, **DONE** commit ba9e6a93). R2 (1 new repro: cross-module tagged-union `==` SEGV).

**Phase 2 — I (investigation):** I1-I5 (**DONE**, reports in `.superpowers/sdd/`). I6 (tagged-union SEGV investigation). Each updates the relevant tech doc. Combined STOP (R2 + I6) for operator ruling before any fix.

**Phase 3 — F (fixes):** F1 (@ptrToInt), F2 (document D2 deferred + extern-link repro), F3 (enum-member), F4 (document D4 deferred), F5 (arena resize), F6 (tagged-union SEGV), F7 (gate sweep + full matrix).

## 4. Tasks

### 4.1 R (repros)

**R1 — DONE** (commit ba9e6a93): 4 repros + rogue_mud NOTES.md. Findings reshaped the plan (see §2).

**R2 — `tagged_union_cmp_xmod/`:** `lib.zig` defines `pub const Shape = union(enum) { Circle: i32, Square: i32, Triangle: i32 };`; `main.zig` compares `s == lib_mod.Shape.Circle` cross-module. Expected: **SEGV** (compiler crash, rc 139). zig0 oracle clean (post-fix reference). Classification: DUMP FAIL / compiler crash.

### 4.2 I (investigation)

**I1-I5 — DONE** (reports: `I-ptrtoint-void-report.md`, `I-orphan-module-report.md`, `I-missing-fwd-report.md`, `I-platstub-gap-report.md`, `I-arena-sizing-report.md`). Findings summarized in §2.

**I6 — cross-module tagged-union `==` SEGV:** reproduce + isolate (gdb or narrowing: same-module control, cross-module without `==`, cross-module with `==`); locate the crash locus in sema/lower (likely the same `:459` else branch that resolves PLAIN enums to VOID, dereferencing something absent cross-module for tagged-union members); determine whether the fix is the same Option-A dispatch as F3 (shared code) or distinct; assess blast radius; update `08_c89_emission.md`. Report: `.superpowers/sdd/I-taggedunion-cmp-report.md`.

### 4.3 F (fixes)

**F1: Fix @ptrToInt.** Prerequisite: REBUILD zig1 (current binary stale vs parser.zig VARCVINT markers). Hoist the ptrtoint check above the `ec.len >= 2` dispatch in `semantic_analyzer.zig`, return TYPE_USIZE. Mirror lowerer (lower.zig:2626-2634, already correct). Gate: `ptr_to_int_void_xmod` green; lisp_interpreter dump rc=0; **lisp MD5 re-baselines** (lisp_interpreter_curr uses @ptrToInt) — runtime proof required (AMENDMENT B); gol/mud/json byte-identical. Tech doc: `03_type_resolution.md`.

**F2: Document D2 deferred to std-lib.** Create `extern_runtime_symbol_xmod/` repro (module uses `extern "c" fn arena_alloc_default`, link fails unless legacy runtime linked) — classified OK-by-gate/latent, serves as std-lib spec. Update json_parser + json_parser_workaround NOTES.md (deferred section) + EXPECTED_FAIL.md. **No compiler changes.** This is NOT the runtime port — operator ruled D2 deferred to the std zig1 library.

**F3: Fix cross-module enum-member resolution.** Option A: add `enum_type` member case to the generic base-type dispatch in sema (`:281` module branch or `:459` else) + lower (`:2016`), mirroring the same-module ident_expr path emitting `.enum_const`. Gate: `zT_missing_fwd_xmod` green; json_parser_workaround 6× zT_xx resolved; 4 MD5s byte-identical. Tech doc: `08_c89_emission.md`.

**F4: Document D4 plat-stub gap deferred to std-lib.** Update plat_stubs_missing_xmod NOTES.md + EXPECTED_FAIL.md + rogue_mud NOTES.md + QUICK_REF.md. **No compiler changes.**

**F5: Arena resize.** Resize allocator.zig buffers: perm 4MB / module 8MB / scratch 2MB. Update main.zig memory limits (DEV_MAX_MEM/RELEASE_MAX_MEM → 16MB, `--max-mem 16M`). **No per-module reset** (I5 rejected as infeasible). Gate: self-compile dump passes import phase (no `OOM: used=...`); 4 MD5s byte-identical (arena size doesn't change codegen); test_analyzer_bin PASS. Tech doc: `00_shared_infra.md`.

**F6: Fix cross-module tagged-union `==` SEGV.** Per I6 ruling. Mirror the same-module tagged-union member path for cross-module (if I6 determines it's the same Option-A dispatch as F3, handle the tagged-union member case F3's enum_type case doesn't). Gate: `tagged_union_cmp_xmod` green (dump/gcc/run rc=0, prints 1); F3 repros no regression; 4 MD5s OK. Tech doc: `08_c89_emission.md`.

**F7: Gate sweep + full matrix reconciliation.** Full 21-example matrix; verify F1/F3/F6 bring lisp_interpreter, json_parser_workaround, tagged_union_cmp_xmod to OK (json_parser + rogue_mud remain deferred at link); 4 MD5 gates (post-F1 lisp re-baseline); test_analyzer_bin PASS; EXPECTED_FAIL.md v28 + QUICK_REF.md + tech docs + rogue_mud NOTES.md consistent.

## 5. Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — ⭐ SUBAGENT CHEAT-SHEET (lines 1-60). Copy exact commands; do not improvise flags.
- **Compiler under test:** `sf/build/out_release/zig1`. F1 prerequisite: REBUILD first (stale vs parser.zig). Multi-module recipe: `mkdir -p DIR && zig1 --dump-c89 --output-dir DIR main.zig`.
- **gcc compile recipe:** `-m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c *.c` then link with `zig_runtime.c zig_pal.c`. mud_server/rogue_mud also link `net_runtime.c`.
- **RUNTIME gates mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 and print expected output. Compile-only gates FORBIDDEN.
- **4 MD5 gates** byte-identical UNLESS operator-approved re-baseline with runtime proof (F-5 AMENDMENT B): mud `6c0a83f117f176f6875ce2c18c761890`, gol `0d8f0092c22c04375482a198691a3957`, lisp `fad411835b9e0aaea165260fbdc6857c`, json `c403f0799dbc5c56d548eee07bb9eebd`. F1 re-baselines lisp (approved).
- **Corpus:** 230 repros, OK=223/FAIL=3/gg=4 (231 dirs). FAIL must not increase. New repros are OK-by-compile/runtime-gap-tracked (NOT added to FAIL).
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task updates the corresponding `sf/docs/tech_docs/*.md` — corrected line refs, `[updated: 2026-08-08]`.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python/bulk transforms.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present.
- **I-tasks report then STOP for combined operator ruling.** F-tasks do NOT start until the ruling.
- **D2 + D4 are NOT compiler bugs** — runtime-library gaps, deferred to the std zig1 library plan (operator ruling m0379). Documented via F2/F4. The `extern_runtime_symbol_xmod` + `plat_stubs_missing_xmod` repros are OK-by-gate/latent.
- **D6 MUST arrive fixed** at the end of this plan (operator ruling m0381).
- **rogue_mud NOTES.md** has the full single-module + multi-module build recipe, plus current expected failure mode. Long-lived status document.

## 6. Out of Scope

- **std-lib implementation** (arena_alloc_default + plat_ console stubs) — deferred (operator ruling m0379), fed by the I2 + I4 catalogs + `extern_runtime_symbol_xmod` + `plat_stubs_missing_xmod` repros
- **Single-module emission fixes** — the single-file path is solid at 14/14
- **Per-module arena reset** — rejected by I5 (module arena is program-lifetime cross-module store)
- **rogue_mud full end-to-end gameplay** — only compile-to-link is in scope; plat_ gap blocks linking, documented
- **0-FAIL corpus goal** — blocked by 2 std-lib-deferred FAILs + 1 C89 fundamental
- **Self-compile full cycle** (zig1 → zig1.c → gcc → zig2) — F5 only targets passing the import phase
