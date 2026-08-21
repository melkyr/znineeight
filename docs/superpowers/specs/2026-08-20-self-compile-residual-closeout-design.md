# Self-Compile Residual Closeout — Design

**Date:** 2026-08-20
**Branch:** `zig1_start`
**Status:** Approved (operator rulings inline)

## Goal

Close the remaining **425** self-compile C-emission errors (3 residual classes) so `bash scripts/self_compile/build_zig1_5.sh` reaches rc=0 and both `zig1_5_asan` + `zig1_5_clean` smoke on hello.

## Background

The emission-fix plan (`2026-08-20-self-compile-emission-fix-plan.md`) reduced self-compile gcc errors **1195 → 425** across F-A..F-E (AMENDMENT 6). Two of five root causes (B local-dedup-cap, D void-call) are at **0 — fully closed**. Three residuals remain because the prior fixtures were *minimal* (single import graph) and did not exercise the full 40-module import graph:

| residual | count | mechanism (verified at HEAD `8d9af49d`) |
|---|---|---|
| **A₂** `zG_` undeclared | **182** | Type-storage globals (e.g. `zG_8143F551_AstKind`, `zG_EAC3E484_TokenKind`) are *defined* in multiple modules (`main_9472B9CB.c:18`, `front_resolution_D5E9117C.c:5`, `analyzer_2FA863C8.c`) but the `extern` declaration lives only in the owner's header (`front_resolution_D5E9117C.h`, `main_9472B9CB.h`). A referencing module that does not include the owner's header (e.g. `analyzer_2FA863C8.c` includes only `analyzer_2FA863C8.h`) references the global with no declaration visible → "undeclared". F-A fixed the *name collision* (`_1`/`_2` suffix) but left **definition multiplicity + missing extern propagation**. |
| **C₂** sibling-payload | **48** assign + **9** no-member | Sibling-variant payload conflation persists at scale (F-C grew the local-decl arrays; the payload-*type* conflation in multi-variant tagged unions remains). |
| **E₂** `zT_` undeclared | **137** | Void-temp producers: **69** lexer call-arg (`lexerMakeToken(…, zT_7)`), **38** switch-arm capture (root C), **30** pal/global (root A). |

Root causes B and D: **0** remaining — do NOT touch.

## Architecture

A **R → I → F → GATE** pipeline. One R fixture per residual (A₂, C₂, E₂); I pins each upstream fix; F applies it with a **self-compile re-count == 0** gate (not merely "fixture GREEN").

**Fixture fidelity rule (the core correction):** every fixture MUST reproduce the exact self-compile emitted-C failure shape — a **3+ module import chain** where the failure is the at-scale mechanism, and the gcc error text is identical to the self-compile error. "Fixture GREEN" must imply "class gone at scale".

## Residual fix targets

- **A₂**: single-owner definition + `extern` propagation to every referencing module's header chain. The type-storage global is emitted once (in the type's owner module) and every module that references it must see an `extern` (via the module's own emitted header include chain). Discriminator = the I-A `types_items[type_id].name_id == name_id` predicate already in `nameManglerMangleGlobal`; the missing piece is *where the definition is emitted* and *who gets the extern*.
- **C₂**: sibling-payload conflation at scale — the `.payload`-typed field access in multi-variant unions (the F-C work covered the local-decl arrays; this is the residual payload-type mismatch).
- **E₂**: void-temp producers — lexer call-argument void temp (the 69-strong producer) + switch-arm capture (root C, should collapse when C₂ lands) + pal/global (root A, should collapse when A₂ lands). The lexer producer is a distinct, independently-fixable site.

## Global Constraints

- **Emission-only.** Zero memory / determinism / runtime work. Fix scope limited to `sf/src/c89_emit.zig`, `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig` (the same files the emission-fix plan touched) — no other files without an operator ruling.
- **Hard byte-identity gate:** 4 MD5s byte-identical — gol `9cf758d96f25d41980379564a5501bc8`, lisp `851c9ed307bc8dc9ac5920a323d371e1` (repo-root CWD, re-baselined AMENDMENT 5), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4` (+5 `emission_*_xmod` fixtures = 292 dirs). Matrix 21/21.
- **Runtime-priority override:** if a fix changes an MD5 but the emitted C is still correct AND runtime-identical, STOP and report + propose a re-baseline. If MD5 changes with any runtime/correctness doubt, STOP without proposing.
- **Fixture fidelity rule (binding):** each fixture is a 3+ module import chain; its gcc error text matches the self-compile error; a F-task gate is the **self-compile re-count of its class == 0**, not just fixture GREEN.
- **`sf/build/out_release/` WEDGED — never touch.** All runs `timeout 120`. `--output-dir` must pre-exist.
- **Build:** `bash sf/scripts/build_release.sh` → `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; reinstall std (`cp sf/src/std.zig std_io.zig std_arena.zig std_net.zig /tmp/fx_subfolder/lib/`).
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7). **Z98 constraints** (AGENTS.md §1.3). **STOP on any issue/confusion. Commit messages verbatim.**

## Success Gate

`bash scripts/self_compile/build_zig1_5.sh` → rc=0, `=== [zig1_5] Done: /tmp/zig1_5 ===`, both `zig1_5_asan` + `zig1_5_clean` produced; smoke both on `examples/z98/hello/main.zig` (rc=0, `.c` emitted); 4 MD5s + corpus 287 + matrix 21/21 unchanged (subject to runtime-priority override). Class re-counts: A₂ == 0, C₂ == 0, E₂ == 0.

## Out of Scope

- Memory (AST-spill / 16 MB target) — separate deferred plan.
- Determinism (T3) / runtime-match (T4) / memory-measurement (T5) / report (T6) of the correctness plan — resume only after `zig1_5` builds.
- Any parser/sema/lowering fix outside the 3 residual classes.
