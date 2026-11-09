# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D16**.

Open: **D15**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

---

## D15 — Switch expressions must use expected-type-first coercion, not a blanket peer-type reject

**Status:** OPEN — re-opened 2026-11-07. Interim fix `280a3b12` correctly rejects
unannotated mixed `int`/`bool` prongs but also false-rejects valid switches whose
result type is known from context (optional, error-union, nullable). Task 9j
investigates Zig 0.17.1 parity; Task 9k applies the expected-type-aware fix.

**Defect.** With an expected result type, each switch prong must coerce to that
type; optional/error-union/null/noreturn prongs are valid. Peer type resolution
applies only when no expected type is known. The current MIX branch rejects
before consulting `topExpectedType`, so these valid corpus cases now fail
`error[3000]` with no `.c`: `eu_err_switch`, `eunum_err_switch`,
`euopt_err_switch`, `euopt_val_switch`, `euoptptr_err_switch`,
`opt_null_switch`, `opteu_err_switch`, `opteu_null_switch`,
`optnum_null_switch`, `optopt_null_switch`, `optopt_val_switch`,
`optptr_null_switch`.

**Expected contract.**
- Expected type known: `switch (x) { 0 => value0, else => value1 }` accepts when
  each prong is assignable to the expected type (including `?T`, `E!T`, `??T`,
  `?*T`, slices, `noreturn`, `undefined` neutral).
- No expected type: peer-resolve prongs; incompatible prongs still reject once
  with a level-0 type mismatch and 0 `.c`.
- Unannotated mixed `int`/`bool` remains invalid.
- Statement switches and missing-`else` behavior unchanged.

**Root cause.** `sf/src/semantic_analyzer.zig` `semanticAnalyzerResolveSwitchExpr`
MIX branch rejects before the expected-type path; the if-expression path
(`semanticAnalyzerResolveIfExpr`, `topExpectedType`) already has the correct
expected-first shape. Task 9j must compare against Zig 0.17.1 before any fix.

**Workaround.** Annotate the switch result explicitly, or split into an
if-expression with the expected type. Do not assume a blanket MIX reject is
correct for annotated contexts.

**Reference points.** `semanticAnalyzerResolveSwitchExpr`,
`semanticAnalyzerResolveIfExpr`, `topExpectedType`, `typeRegistryIsAssignable`;
Task 9i interim fix `280a3b12`; `repro/mi_matrix/known_excluded/switch_value_mixed_type_repro/`;
Task 9j/9k and `.superpowers/sdd/2026-10-29-phase35-defects-plan/`.


