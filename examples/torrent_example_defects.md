# z9play / examples — open compiler defects

Tracks only **open** compiler defects found while building the example programs.
Fixed defects and closed investigations were removed at Phase 2.5 Task 6
(2026-10-29); their history lives in git and the SDD reports. IDs are stable —
deleted numbers are not reused. Next free slot: **D16**.

Open: **D16**.

_(Add new entries at the next free slot as they are found; entries are doc-only
unless a compiler fix is separately authorized.)_

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
- Task 9k: expected-first reaches 12/12, 35/35, 5/5 while keeping
  `sw_is_stmt_expr`, so mixed statement switches remain accepted (this gap) and
  statement-switch emission stays byte-identical.

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


