# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D16**.

Open: **D15**, **D16**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

---

## D15 — Switch expressions must use expected-type-first coercion, not a blanket peer-type reject

**Status:** OPEN — re-opened 2026-11-07. Interim fix `280a3b12` correctly rejects
unannotated mixed `int`/`bool` prongs but also false-rejects valid switches whose
result type is known from context (optional, error-union, nullable). Task 9j
completed the Zig 0.17.1 parity investigation; Task 9k applies expected-type-first
to value-result switches only under operator option (d). Statement-switch and
assignment/void parity move to D16.

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

---

## D16 — Switch/assignment parity gap: statement-mixed switches, assignment-expression typing, and deferred Zig parity

**Status:** OPEN — deferred by operator 2026-11-09. Not fixed in Phase 3.5.
Task 9k fixes the D15 value-result switch defect under option (d); this entry
records the remaining parity gap so it is not mistaken for a D15 regression.

**Defect.** Z98 and Zig diverge where an assignment or assignment-ended block is
used as a switch prong or block tail:

- Z98 `semanticAnalyzerResolveAssign` returns the LHS type
  (`sf/src/semantic_analyzer.zig:4725`, `:4729`); Zig has no assignment
  expression and an assignment-ending block is `void`.
- Z98 therefore accepts mixed statement switches via `sw_is_stmt_expr`
  (`:5039-5044`), while Zig rejects `switch { 0 => 1, else => true }`.
- Global assignment-void is not safe as a two-line sema change: it changes
  compound-assignment temp typing (`sf/src/lower.zig:6105`) and async frame
  sizing (`sf/src/async_analysis.zig:396`), including async frame constants.
- Adjacent parity gaps: Zig prunes untaken prongs for a comptime-known selector
  while the D15 spec rule rejects the untaken mismatch; Z98 has no `anyerror`
  type; `const y: ?i32 = { g = 1; };` remains a warning-level false accept.

**Evidence.**
- Task 9j: real Zig 0.17.1, 119 probes. 12/12 valid corpus switches and 35/35
  expected-type cells accept under Zig/pre-D15 and reject under interim D15;
  5/5 mixed value negatives reject under Zig/current, accept pre-D15;
  `stmt_mixed_int_bool`/`stmt_mixed_int_void` reject under Zig, accept current;
  comptime-known mixed selector accepts under Zig, rejects under spec/current;
  `anyerror!i32` is a pre-existing Z98 keyword limitation.
- Task 9l: 28 Zig probes, full 1278-entry corpus, 185 switch entries.
  Global assignment-void: 27 emission diffs before fixes, 2 after compound-assign,
  1 after async frame sizing; `mud_server` frame 712→720 and `z9torr`
  12808→12688 in variant A. Switch-only option (c): 12/12 D15 cases, 34/35
  reproduced statement entries, statement-switch emission byte-identical,
  19 expected value-switch coercion shifts, one genuine `stdlib_tls_alpn_xmod`
  fixture migration. 38-vs-35 statement-entry count difference is documented;
  three entries remain unaccounted. `z15/z16` typed optional/error-union
  assignment-block false accepts remain warning-only.
- Task 9k candidate: expected-first reaches 12/12, 35/35, 5/5 and rejects mixed
  statements, but removing `sw_is_stmt_expr` regresses 38 in-tree statement
  switches. Candidate is uncommitted and not part of this plan.

**Resolution chosen.** Option (d): keep `sw_is_stmt_expr`; Task 9k fixes only
value-result switches. Statement-mixed, assignment-void, comptime-prong pruning,
and `anyerror` remain documented here. Full parity needs a separate plan, not a
Phase 3.5 patch.

**Workaround.** Add explicit type annotations; avoid assignment-ended blocks in
typed optional/error-union positions; do not rely on mixed statement switches.

**Reference points.** `semanticAnalyzerResolveAssign`,
`semanticAnalyzerResolveSwitchExpr`, `semanticAnalyzerResolveIfExpr`,
`topExpectedType`, `typeRegistryIsAssignable`; `sf/src/lower.zig:6105`;
`sf/src/async_analysis.zig:396`; Task 9i `280a3b12`; Task 9j/9l reports;
`repro/mi_matrix/known_excluded/d15_parity/`,
`repro/mi_matrix/known_excluded/d15_assignment_void/`.


