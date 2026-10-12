# Fidelity-Gap Fix: Enum/Tagged-Union Switch + Labeled-Stmt Runtime Correctness — Design

**Date:** 2026-08-25
**Status:** Approved design (Plan 1 of two)

## Problem

The self-emission fidelity gap makes self-compiled `zig1_5` unusable: it cannot tokenize/parse its own source (27,664 `error[2000]` self-dumping `sf/src/main.zig`). Root cause triple-verified across Tasks 1-4 of the 2026-08-25 investigation plan:

**Enum-value stmt-switch case-label drop.** A `switch` over an enum-typed discriminant whose case items are *qualified* enum literals (`TokenKind.plus =>`) emits `switch (x) { default: goto z_bb_N; }` with ZERO `case` labels. Runtime: every prong unreachable → wrong value (fixture prints `0` instead of `2`) or `error[2000] invalid token in expression`.

### Mechanism

1. **Parsing**: qualified `TokenKind.plus` parses as `field_access` (ident_expr `TokenKind` + postfix `.plus`), NOT `enum_literal`. Only the anonymous `.plus` form (via `parserParseEnumLiteral`, parser.zig:760-766) yields `AstKind.enum_literal`.
2. **Semantic**: `semanticAnalyzerResolveEnumLiteral` (semantic_analyzer.zig:1032) resolves `enum_literal`/`undefined_literal` case items and populates `enum_value_table[node_idx] = member_value` (semantic_analyzer.zig:1307-1311). Qualified `field_access` case items are never resolved.
3. **Lowering**: the stmt-switch case-collection loop (`lower.zig:3946-3976` in `lowerExprImpl`; `lower.zig:4777-4806` in `lowerStmt`) accepts only `int_literal`/`char_literal`/`enum_literal`/`error_literal`; anything else hits `else { continue; }` (:3969-3971 / :4800-4802) → case dropped → `cases_count=0`.
4. **Emission**: `c89_emit.zig:5668-5709` emits exactly `cases_count` `case` labels + `default: goto z_bb_<else_bb>` → bare `switch { default: goto z_bb_N; }`.

**Two lowering sites** carry the same bug: the expr-switch path (`lowerExprImpl` swt_ex) and the stmt-switch path (`lowerStmt` swt_ex). Both must be fixed.

### Known-good / known-bad shapes

- Anonymous enum-literal cases (`.plus =>`): `enum_literal` → collected → WORKS.
- Qualified enum-literal cases (`Kind.plus =>`): `field_access` → dropped → **BROKEN** (the bug).
- Tagged-union switch: `lower.zig:3917-3921` loads `TU_FIELD_TAG` into a u32 temp, then switches on it; case items are `.tag` anonymous enum literals → `enum_literal` → collected → WORKS today (payload capture at :4006-4034). Needs verification fixtures.
- Labeled statements: `label: { }` and `label: while/for`, `break :label`, `continue :label` (lower.zig:4408-4414, :4315-4318). Fidelity in nested switch/loop contexts needs verification fixtures.

## Design Decisions

### Decision 1 — Verification criterion: RUNTIME behavior, not byte-identity vs zig0

zig0's emission is "lifted and transformed" — its C architecture differs from zig1's (manglers, goto-block style, module layout). Byte-comparing zig1 vs zig0 output is not the correctness bar.

**Correctness bar**: each fixture is a runnable program that prints observable output (e.g. an enum-to-int value, a tagged-union payload, a loop counter). The fixture is GREEN if the emitted program, compiled + run, prints the expected value; RED if it prints a wrong value, errors, or crashes. This is "debug-like for correctness" — exercise the construct the way the compiler itself uses it, and confirm the observable runtime result.

### Decision 2 — Fix locus: investigate first (I-ENUMFIX), then fix (F-ENUMFIX)

The cleanest fix locus is not predetermined. Candidates:
- **(a)** Add a `field_access` branch to both case-collection loops that resolves the qualified enum literal to its member value (via the switch-cond enum/tagged-union type registry).
- **(b)** Resolve qualified enum-literals in the semantic analyzer (extend the `enum_literal`/`undefined_literal` handling at semantic_analyzer.zig:1307-1311 to also resolve `field_access` case items) and populate `enum_value_table`, then have lowering accept `field_access` case items.

I-ENUMFIX pins which single locus (or both) is required and byte-safe; F-ENUMFIX applies it.

### Decision 3 — Extension shapes are R-first, fix-only-if-RED

Each extension shape gets a runtime-correctness fixture. If the fixture is GREEN (prints expected value), it is kept as a control. Only RED fixtures trigger an I/F follow-up. This bounds the plan to observed failures — no speculative fixing.

### Decision 4 — Scope

- Plan 1 fixes the enum-switch drop (F-ENUMFIX) and adds runtime-correctness fixtures for: enum switches (qualified + anonymous), tagged-union switches (payload access + tag-to-int), labeled statements, and nested combinations (for-inside-if-inside-switch-on-enum; switch-in-switch; enum inside; enum-to-int print).
- Plan 1 does NOT touch the sf/src_sh/ bootstrap-freedom work (Plan 2).
- No `sf/src` changes outside the F-ENUMFIX locus.

## Success Criteria

1. `repro/mi_matrix/emission_enum_switch_xmod` (existing RED fixture, commit `b9bc3f1d`) flips GREEN: run prints `2`.
2. All extension fixtures run and print their expected values (GREEN) or are documented RED with a fix.
3. 4 MD5 gates byte-identical: gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`.
4. 21-example matrix 21/21.
5. Self-compile re-count: 0 gcc errors (no regression).
6. `zig1_5` self-compiled binary correctly parses the previously-failing operators (`+ - * / == != < <= > >= = and or`).
