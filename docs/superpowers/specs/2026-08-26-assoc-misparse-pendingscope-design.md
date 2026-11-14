# Assoc-Chain Misparse (Self-Compile) + pending_scope Nest-Safety — Design

**Date:** 2026-08-26
**Status:** APPROVED (operator-ruled)
**Branch:** zig1_start

## Goal

Two residuals of the (complete) labeled-break + self-compile crash plan:

- **R-1 (Phase A):** the self-compiled `zig1_5` mis-parses same-precedence left-associative chains (`a-b-c` → `a-(b-c)`, `a/b/c` → `a/(b/c)`), breaking `printInt` digit reversal (fibonacci prints `5\0` vs `55`). zig1 as the base compiles programs correctly; only the SELF-EMITTED parser reverses associativity — a self-emission fidelity gap.
- **I-1 (Phase B):** the B3b scope-chain fix uses a single `pending_scope: u32` slot that is not nest-safe (for-range-end captures orphan the loop capture).

## Scope Decisions (operator-ruled)

- **Full R/I/F for both.** Phase A (assoc) = R fixture + I trace + F fix. Phase B (pending_scope) = I pin + F fix.
- Correctness bar = RUNTIME behavior (program prints the expected value), NOT byte-identity vs zig0.
- 4 MD5 byte-identity gates are authoritative (current values: gol `eed963e0640a073ed4eebb292f136e05`, lisp `c3c5847798e4553b2e34950e085bb6c6` repo-root CWD, json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`). Both phases MUST keep them byte-identical (or obtain an explicit operator re-baseline ruling).

## Background (triple-verified prior work)

### R-1 assoc-chain misparse (self-compile only)

- The precedence-climbing loop `parserParseExprPrec` (parser.zig:179-228):
  - `if (has_info == 0) break; if (precToInt(info.prec) < precToInt(min_prec)) break;` (:197-198)
  - `var next_min: Prec = undefined; if (info.right_assoc) { next_min = info.prec; } else { next_min = precFromInt(precToInt(info.prec) + 1); }` (:202-207)
  - RHS parsed at `next_min` (:220); `lhs = parserAddBinary(self, tok, lhs, rhs)` (:224) — left-assoc for same-precedence ops because RHS min-prec is raised by 1.
- `OpInfo` struct = `{ prec: Prec, right_assoc: bool }` (parser.zig:1900-1903). `getInfixInfo(kind) ?OpInfo` (:1905+) returns `right_assoc = false` for additive/multiply/shift/etc. (left-assoc, :1927-1936) and `true` only for assignment/orelse/catch (:1914-1917).
- `Prec` enum(u8) none=0..postfix=14 (:1874-1890); `precToInt`/`precFromInt` (:1892-1898).
- **The self-compile symptom:** zig1 (built by zig0) parses `10-4-3` = `(10-4)-3` = 3 correctly. The self-compiled zig1_5 (built by zig1 compiling its own parser.zig) parses `10-4-3` as `10-(4-3)` = 9 (right-assoc). So zig1 mis-emits SOME construct in its own parser's precedence logic — the emitted `getInfixInfo`/`right_assoc` bool flips, or the `if (info.right_assoc)` branch inverts, or the `?OpInfo` unwrap mis-reads the struct. This is the same self-emission fidelity-gap class as F2 (name-vs-temp) and F1 (scope-chain).
- Recorded residual R-1 in EXPECTED_FAIL v48 + QUICK_REF (from GATE-FINAL, plan `e29d9a50`); proven pre-existing via the pre-plan binary `/tmp/zig1_5_fixed` (built at `5ec13efb`).

### I-1 pending_scope nest-safety

- B3b scope-chain (`a7a207f7`): `LirLowerer.pending_scope: u32` single slot (lower.zig:416, init TEMP_NONE :555). `scopeNodeForDepth` (:316-324) creates a child scope when `at_depth > scope_depth` and stores it in `pending_scope`. `pushScopeDepth` (:326-334) consumes it into `cur_scope`. `popScopeDepth` (:336-339) restores parent.
- **The hole:** in `for (start..end) |t|`, the range-END expression is lowered AFTER the capture `t` is added (creating a pending scope) but BEFORE the body scope push. A capture inside the end expr (e.g. `for (0..if (rt) |x| x else 0) |t|`) reuses/consumes the loop capture's pending scope → `t` orphaned from the chain → resolver falls through to raw `load_local`. Runtime stays correct (fallback), no gate/corpus fixture triggers it, but it is a genuine nest-safety hole.
- B3b reviewer flagged I-1 (Important) at B3b review; a naive reorder of the for-range lower sites risks MD5 temp-ordering.

## Architecture

- **Phase A (assoc):** R fixture reproduces the reversal via a left-assoc chain with observable output; I diff traces the self-emitted `parser_*.c` `getInfixInfo`/`right_assoc`/precedence-climb against the reference `/tmp/ref_zig1.c`/`/tmp/fx_subfolder/parser.c`; F fixes the single mis-emitted construct.
- **Phase B (pending_scope):** I pins a nest-safe design (scope-node stack, or create-child-scope-on-demand with proper depth linkage, or restructure the for-range capture ordering without disturbing temp order); F applies it byte-identically.

## Components / Data Flow

- R-ASSOC fixture: a main that computes `10 - 4 - 3` (and `/`, `+`, `*`) and prints; reference emits 3, self-compiled emits 9 (RED).
- I-ASSOC: compare self-emitted `parser_<hash>.c` `getInfixInfo`/`parserParseExprPrec` bodies vs `/tmp/fx_subfolder/parser.c` (the emission that built the working zig1) and/or `/tmp/ref_zig1.c`; normalize mangler noise; pin the divergent construct + source anchor file:line.
- F-ASSOC: single-locus fix in the source construct that mis-emits (likely a `bool`/`if`/struct-emission defect in c89_emit.zig, or a parser.zig construct that lowers wrong). Rebuild zig1 + zig1_5; self-compiled must parse `10-4-3`=3 and printInt digits correctly.
- I-PENDSCOPE: pin the nest-safe design; preserve MD5 temp-ordering (no naive reorder).
- F-PENDSCOPE: apply byte-identically; 4 MD5s unchanged; matrix 21/21.

## Error Handling / Testing

- Fixtures runtime-driven (print expected value; RED = wrong output). 4 MD5 gates, matrix 21/21, self-compile re-count, Z98 dialect, `timeout 120` on all compiler invocations.

## Out of Scope

- Any additional self-emission fidelity gaps revealed during Phase A beyond the first pinned locus (STOP-present).
- The `sf/src_sh/` self-containment implementation (deferred; own plan on disk).
- Tagged-union qualified-label+capture gap (prior Task-1 M1 hazard; documented).
