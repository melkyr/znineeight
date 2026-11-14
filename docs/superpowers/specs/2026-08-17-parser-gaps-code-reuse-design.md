# Parser Gaps, Example Quirks & Code-Reuse Audit — Design Specification

**Version:** 1.0
**Date:** 2026-08-17
**Status:** Approved. Ready for plan.

## 1. Goal

Three independent workstreams on the Z98 self-hosted compiler (`zig1`):

1. **Fix 3 parser gaps** that block self-compile completion (deferred from the memory-optimization plan closure `de630979`): discard-capture `if (x) |_|`, bare array type as expression, and trailing comma in fn-call args.
2. **Resolve 2 example quirks** (`days_in_month` u8 `{}` raw-byte output; `json_parser` missing object-field commas) — root cause decides whether the fix lives in example source or the compiler.
3. **Audit each compiler module cluster for code reuse** — duplicated logic and helper-consolidation opportunities (the past plan reduced memory; this phase increases code reuse).

**Investigation-first cadence (operator ruling):** all I (investigate) tasks run and report first; a single consolidated STOP gathers the operator's rulings; then F (fix) tasks — the parser F tasks enter the plan as placeholders and are written in full after the STOP.

## 2. Architecture

```
Workstream A — 3 parser gaps (I + F per gap):
  repro already committed under repro/mi_matrix/ (parsergap_discard_if_xmod,
  parsergap_array_type_xmod, parsergap_trailing_comma_xmod, commit 583a081e).
  A-I* verify locus + design fix (parser-only vs cascade) → A-F* implement.

Workstream B — 2 example quirks (I + F per quirk):
  B-I* determine root cause (example source vs compiler) → B-F* fix per ruling.

Workstream C — 7 code-reuse audits (I only; audit reports feed a later consolidation plan):
  C-I* per cluster: catalog duplicated logic + helper-consolidation + duplicate
  allocs, ranked. Audit reports only — NO source changes in I tasks.

Cadence: 12 I tasks → ONE consolidated STOP → operator rulings → F tasks written
and executed → gate sweep.
```

## 3. Workstream A — Parser Gaps

All three repros are RED (frontend `error[2000]`, 0 `.c` emitted), each with a control proving the isolate. The A-I tasks must re-verify the locus against current HEAD (line numbers shifted after F-PARSERGAP `b33f412a`), confirm the fix is confined to `parser.zig` (or enumerate the sema/lower cascade — the F-PARSERGAP lesson), and confirm byte-identity for unaffected inputs.

### A1. Discard capture `if (x) |_|`
- **Repro:** `repro/mi_matrix/parsergap_discard_if_xmod/` — stmt-position `if (opt) |_| { … } else { … }`.
- **Known locus:** `parserParseIfStmt` capture parse uses `parserExpect(TokenKind.identifier)` (`parser.zig:1499`), but `_` lexes as `TokenKind.underscore` (`lexer.zig:422`). Working analogues already accept `_`: switch-prong (`parser.zig:893`), var-decl name (`parser.zig:1337`). Same defect present in value-position `parserParseIfExpr` capture (`parser.zig:790`).
- **Sketch fix:** accept `underscore` for the capture name in both if-stmt and if-expr paths, mirroring the switch-prong pattern.
- **Self-compile hit:** `sf/src/cinclude.zig:23`.

### A2. Bare array type as expression (`const Buf = [10]u8`)
- **Repro:** `repro/mi_matrix/parsergap_array_type_xmod/` — type alias as const value.
- **Known locus:** `parserParsePrimaryExpr` (`parser.zig:318`) sends expression-position `[` to `parserParseArrayLiteral` (`parser.zig:752`), which requires a `{` body after `parserParseBracketType` (`parser.zig:755-758`).
- **Sketch fix:** no-`{` branch in `parserParseArrayLiteral`: after the bracket type, if next token is not `{`, return the bracket-type node (`array_type`/`slice_type`) directly.
- **Cascade note:** lower.zig:2283's array-type error is a recovery cascade off the A1 discard-capture failure; A2's independent trigger is `[N]T` in primary position.

### A3. Trailing comma in fn-call args
- **Repro:** `repro/mi_matrix/parsergap_trailing_comma_xmod/` — 9-arg call with trailing comma.
- **Known locus:** `parserParseFnCall` arg loop (`parser.zig:401-407`) breaks only on `rparen` after an arg; a trailing comma is consumed then the loop re-parses an arg at the `rparen`, hitting `parserParsePrimaryExpr` fallthrough → `error[2000] expected expression`.
- **Sketch fix:** mirror the array/tuple-literal pattern — advance over an optional trailing comma, then break when next token is `rparen`.
- **Self-compile hit:** `sf/src/main.zig:749-759`.

## 4. Workstream B — Example Quirks

Root-cause-decides: the B-I task determines whether the defect is in the example source (`examples/z98/*`) or the compiler; the B-F task then edits whichever the ruling names.

### B1. `days_in_month` — u8 `{}` prints raw bytes
- `examples/z98/days_in_month/main.zig` prints `std.io.print("  Month {}: {} days\n", .{ month, days })` where `month`/`days` are `u8`. Output shows raw byte chars (NOTES: "month name null bytes cause display corruption").
- **Question for B-I1:** is `{}` with a `u8` argument handled by the enhanced print lowering as a raw char (compiler defect), or must the example cast/use `printInt` (source fix)?

### B2. `json_parser` — object fields missing commas
- `examples/z98/json_parser/main.zig` `printValue` `.Object` arm has `if (i < obj.len - 1) std.io.print(",");` inside `for (obj) |item, i|`, yet NOTES records "missing commas between object fields" in output.
- **Question for B-I2:** is the `for`-loop index/compare mis-lowered (compiler defect), or is the source condition wrong (source fix)?
- **Gate impact:** `json_parser` is a hard MD5 gate (`066c9997…`). Any B2 fix that changes emitted C requires an operator re-baseline ruling.

## 5. Workstream C — Code-Reuse Audits (7 clusters)

Read-only audit reports (`.superpowers/sdd/`), NO source changes. Each cluster audit catalogs, with `file:line` evidence:
- **Duplicated logic** — repeated parse/analysis/emission/resolve patterns that could share one helper.
- **Helper-consolidation opportunities** — near-identical local helpers across modules that could be consolidated into `util/` (or an existing module).
- **Duplicate allocations** — repeated alloc/grow/reset patterns and double-buffering.
- **Ranking** — by reuse benefit ÷ refactor risk; byte-identity risk noted per candidate.

### Clusters
- **C1 — Frontend/parse:** `lexer.zig`, `parser.zig`, `token.zig`, `ast.zig`
- **C2 — Module/import:** `import_resolver.zig`, `module_registry.zig`, `source_manager.zig`, `string_interner.zig`
- **C3 — Semantic:** `semantic_analyzer.zig`, `analyzer.zig`, `semantic.zig`, `coercion.zig`, `const_alias_prepass.zig`
- **C4 — Type system:** `type_resolver.zig`, `type_registry.zig`, `resolved_type_table.zig`, `symbol_table.zig`, `symbol_registrator.zig`
- **C5 — Lowering:** `lower.zig`, `lir.zig`, `comptime_eval.zig`, `constraint_checker.zig`, `state_map.zig`
- **C6 — Emission:** `c89_emit.zig`, `name_mangler.zig`, `c89_types.zig`, `assign_helper.zig`, `print_decomposition.zig`, `cinclude.zig`
- **C7 — Infra/util:** `allocator.zig`, `growable_array.zig`, `diagnostics.zig`, `config.zig`, `panic.zig`, `util/*.zig`

## 6. Cadence, STOP and Gate

1. **Execute all 12 I tasks** (3A + 2B + 7C). Each produces a report at `.superpowers/sdd/task-*-report.md`; I tasks are read-only (no source changes, no commits).
2. **ONE consolidated STOP** — the controller presents all I findings and the operator rules: fix approaches for A1-A3 + B1-B2, which C consolidations to pursue (and in what order), and any MD5 re-baseline.
3. **Fill + execute F tasks** — A-F1..A-F3, B-F1..B-F2 (parser F tasks enter the plan as placeholders), plus the C-F consolidation tasks the ruling approves.
4. **Gate sweep** — 4 MD5 gates byte-identical (unless re-baselined), corpus 255 `OK=249/FAIL=2/ICE=0/CRASH=0/GG=4`, 21-example matrix 21/21, `test_analyzer_bin` 5/4, self-compile progress re-checked.

## 7. Out of Scope

- Memory-pool sizing / BSS trim (deferred Task 12 F-RESIZE) — future plan.
- Task 14 F-GATE docs reconciliation of the memory-optimization plan — future plan.
- Actually implementing C consolidation refactors — deferred to a subsequent plan after the audits and operator ruling.
- Any example/compiler behavior beyond A1-A3, B1-B2, and the 7 audits.
