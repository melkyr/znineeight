# Parser-Gaps Corrections & Self-Compile Blocker — Design Specification

**Version:** 1.0
**Date:** 2026-08-17
**Status:** Approved. Ready for plan.

## 1. Goal

Correct the execution gaps identified in the whole-branch review of the parser-gaps plan (`5ad5f948..003956d2`), and pin + fix the self-compile blocker. Six items:

1. **many_ptr registration** — `symbol_registrator.zig:284` covers `array_type|slice_type` but not `many_ptr_type`, while the parser's no-`{` branch accepts it → `const P = [*]u8;` still hits spurious `error[3000] cannot declare variable of type void` at use.
2. **A-F3 strict diagnostic** — the loop-top mirror (parser.zig:401-407) silently accepts `f(1 2)` (missing comma) and unterminated `f(1`/`f(` where the original code errored. Operator: this trade-off was NOT ruled; restore strict diagnostics while keeping trailing-comma support.
3. **B-F1 specifier validation** — `lowerPrintFmt` (lower.zig:549-556) captures any char between `{` and `}` as the specifier with no validation. Operator ruling: **invalid Zig specifier = compile error** (allowed set: `d`/`c`/`s`; empty `{}` → `d`).
4. **B-F2 Site B** — the LDS ident scan (lower.zig:2066-2086) forward-scans and breaks on the FIRST (outermost) name match with no scope filter, unlike `findLocalTemp` (lower.zig:1188-1196) which backward-scans with a scope-depth filter. Operator ruling: **Site B in scope** (full blast radius, heavy gates). Plus: scope-gate the function-wide `capture_shadow` remap (lower.zig:793, :1899).
5. **Self-compile blocker** — `error[2000]` attributed to `type_resolver.zig:981` (marker-trace approximation; the evaluator cannot emit `error[2000]` — it is a parser diagnostic). The actual parser-rejected construct is UNPINNED. Must pin + repro + fix.
6. **EXPECTED_FAIL historical json pointer** — add `066c9997… → fc357296…` forward-pointer to the historical sections (consistency with QUICK_REF).

**Investigation-first cadence (operator ruling):** low-confidence items get a proper I task first (report → STOP → ruling → F). Confident items go straight to F after their repro. All repros are created first (RED baselines) so every fix has a gate.

## 2. Architecture

```
Phase R — repros (RED baselines, one per issue, committed):
  R1 many_ptr:        repro/mi_matrix/parsergap_many_ptr_xmod  (error[3000] at use)
  R2 strict comma:    repro/mi_matrix/parsergap_strict_comma_xmod (missing comma + unterminated)
  R3 specifier:       repro/mi_matrix/parsergap_specifier_xmod  (space/x specifier)
  R4 shadow local:    repro/mi_matrix/parsergap_shadow_local_xmod (general shadowed local)
  R5 self-compile:    pin the real error[2000] construct -> minimal repro

Phase I — investigations (low-confidence items; report -> STOP -> ruling -> F):
  I-SPECIFIER (F3):   exact validation locus + error code + diag/source_file_id threading
  I-SITEB (F4):       shadow-resolution blast radius across corpus + fix shape + gate plan
  I-SELFBLOK (F5):    pin the actual parser-rejected construct behind type_resolver.zig:981

Phase STOP — one batched ruling (R findings + I findings together).

Phase F — fixes (per ruling):
  F1 many_ptr (confident, 1 line)          F2 A-F3 strict (confident, A-I3 design)
  F3 specifier validation (per I-SPECIFIER) F4 Site B (per I-SITEB)
  F5 self-compile (per I-SELFBLOK)         F6 EXPECTED_FAIL pointer (docs, in GATE)

Phase GATE — 4 MD5s, corpus, matrix, test_analyzer, self-compile re-check,
             EXPECTED_FAIL/QUICK_REF reconciliation. Final whole-branch review.
```

Confidence classification:
- **Confident (direct F after repro):** F1 (many_ptr — single-line, all downstream machinery already handles `many_ptr_type`), F2 (A-F3 strict — A-I3 report already specified the exact second-`rparen`-break variant), F6 (docs pointer).
- **Low confidence (I task first):** F3 (specifier validation — error-reporting from the lowerer is a new capability: `ctx.diag` exists at lower.zig:83 but `source_file_id` is not in SemanticContext), F4 (Site B — blast radius over all shadowed locals is unquantified), F5 (self-compile — the root construct is un-pinned by definition).

## 3. Phase R — Repro Tasks

### R1. `parsergap_many_ptr_xmod`
`const P = [*]u8;` then a `var q: P = ...;` (or use of `P` in an annotation). Expected RED: `error[3000] cannot declare variable of type void`. Control: `const A = [10]u8;` (GREEN, post-A-F2) + `const S = []const u8;` (GREEN).

### R2. `parsergap_strict_comma_xmod`
Two cases in one fixture: `f(1 2)` (missing comma) and `f(1` (unterminated). Expected RED today is **SILENT SUCCESS** (the A-F3 regression); the fixture must document that the *expected* post-fix behavior is `error[2000]`. Control: `f(1,2,)` trailing comma (GREEN, stays working).

### R3. `parsergap_specifier_xmod`
`std.io.print("{} {}" ...)` (space specifier) and `std.io.print("{x}" ...)` (invalid char). Expected RED today: **silent degrade** (u8 → decimal); fixture documents that the *expected* post-fix behavior is a compile error per operator ruling. Control: `{d}`, `{c}`, `{}` all GREEN.

### R4. `parsergap_shadow_local_xmod`
A general shadowed local (NOT for-index — the Site B root cause): e.g. an outer `var x` + inner block `var x`, then a use that must resolve INNER but the LDS scan resolves OUTER. Must be a construct that today mis-resolves (RED for correctness; document expected post-fix GREEN).

### R5. Self-compile blocker pin
Read-only investigation folded into the repro step: reproduce `error[2000]` flood on self-compile, filter out `error[9999]` noise, identify the FIRST non-9999 root error, and reduce it to a minimal standalone fixture. If the root is a known gap (cinclude.zig:23 `|_|` etc.), use the smallest existing/new repro. RED baseline recorded; the fixture is the I-SELFBLOK input.

## 4. Phase I — Investigation Tasks (low confidence)

### I-SPECIFIER (F3 locus)
- Determine the exact validation point and error-reporting mechanism for an invalid print specifier.
- `ctx.diag` is available (SemanticContext, lower.zig:83) but `source_file_id` is NOT in SemanticContext — enumerate what must be threaded (field + init-site) and whether a node-index-based span is usable, or whether the validation belongs in the semantic analyzer instead (which already has `diag` + `source_file_id`).
- Specify the exact error code (existing ERR_* enum vs new) and message, and confirm all 4 gate MD5s stay byte-identical (no gate uses invalid specifiers).
- Output: exact fix design + gate impact + any blast radius.

### I-SITEB (F4 locus)
- Enumerate all local-name shadowing patterns in the corpus + examples + self-compile closure that hit the LDS forward-scan (lower.zig:2066-2086).
- Determine the exact fix shape: reverse the scan to innermost + apply the `local_decl_scopes[li] <= self.scope_depth` filter (mirror `findLocalTemp` lower.zig:1188-1196), and whether the block can simply delegate to a shared helper.
- Quantify the `capture_shadow` remap blast radius (lower.zig:793, :1899 — function-wide remap) and specify the scope-gate.
- Output: fix design + corpus/gate impact projection + which gates (if any) re-baseline.

### I-SELFBLOK (F5 locus)
- Using the R5 pinned fixture, trace the exact parser rejection to its locus (candidate: a construct the parser does not yet accept in the self-compile closure).
- Confirm scope: parser-only vs cascade (the A-I2 lesson).
- Output: exact fix design + gate impact + byte-identity projection.

## 5. Phase F — Fix Tasks (written in full after the STOP, per rulings)

Placeholders, filled from the I reports:
- **F1** many_ptr registration (confident).
- **F2** A-F3 strict diagnostic restore (confident).
- **F3** specifier validation per I-SPECIFIER.
- **F4** Site B LDS innermost scan + capture_shadow scope-gate per I-SITEB.
- **F5** self-compile blocker fix per I-SELFBLOK.
- **F6** EXPECTED_FAIL historical json pointer (folded into GATE).

## 6. Phase GATE

- 4 MD5 gates: gol `9cf758d96f25d41980379564a5501bc8`, lisp `524d2872daefb2677c8ddc1ac8f34cf5`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081` (re-baseline only if F4/F5 shift it, with runtime-identity proof).
- Corpus (258 dirs): OK=252/FAIL=2/ICE=0/CRASH=0/GG=4 expected; new repros flip FAIL→OK as fixed.
- 21-example matrix 21/21; test_analyzer_bin "5 passed, 4 failed"; days_in_month + json_parser runtime correct.
- Self-compile re-check: must pass the previously-failing construct; record progress.
- Docs: EXPECTED_FAIL version bump + closeout entry, QUICK_REF corpus/MD5 lines, F6 pointer.

## 7. Global Constraints

- Z98 dialect: NO `anytype`, NO `@Type`. Use `fastedit`/`edit` ONLY (no sed/python). `sf/build/out_release/` WEDGED — never touch; always `timeout`. Compiler under test = `/tmp/fx_subfolder/zig1`.
- Byte-identity is the hard gate unless an operator ruling re-baselines (json already re-baselined to `fc357296…`).
- NO scope creep beyond the six items. Fixes implement ONLY what the ruling + I report specify.
- Every F task must pass its repro RED→GREEN + all gates before commit.
