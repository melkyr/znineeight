# anon_init_orelse_rhs — RED (DEFERRED gap: class-C site 6c, operator decision 2026-07-09)

## Form
Anonymous tagged-union init as the RHS of an `orelse`:
```zig
var c: Command = maybe(0) orelse .{ .Go = 6 };
```
`Command = union(enum) { Quit: void, Go: i32 }`, `maybe(k) ?Command`.

## Expected
`6`.

## Empirical result on HEAD `5e2ccc9d` (after Task 4 Step 3, 2026-07-09)
**RED — gcc error:**
```
/tmp/or.c:76:12: error: incompatible types when assigning to type 'zT_C67C8F52_Command' from type 'int'
```
0 `.payload.Go._0` writes on the orelse-RHS path. The anon `.{ .Go = 6 }` resolves to `TYPE_VOID`.

## Why DEFERRED (not fixed in Task 4)
Unlike the other class-C sites (if-expr arm, switch prong) — which Task 4 Step 3 fixed automatically because
the enclosing var-decl's `pushExpectedType(decl_type)` stays on the stack top through recursive arm
resolution — the `orelse` RHS is NOT resolved at all today: `semanticAnalyzerResolveOrelseExpr`
(`semantic_analyzer.zig:742-752`) only resolves `child_0` (the optional) and returns `opt.payload`; it NEVER
calls `resolveExpr` on the RHS `child_1`. Wiring 6c therefore requires ADDING a new `resolveExpr(child_1)`
call (new sema behavior), not merely bracketing an existing resolve with push/pop.

Operator decision (2026-07-09): DEFER 6c as a documented gap — it needs new sema code, carries byte-identity
risk on existing orelse repros (`orelse_void`, `optstar_void_orelse`, `mi_matrix/*orelse*`), and NO current
corpus/gate program uses an anonymous `.{}` in an `orelse` RHS. To be handled in a future follow-on.

## Cross-links
- Task 4 (`.opencode/plans/2026-07-08-tagged-union-payload-store.md`): expected_type_stack; class-C site 6c.
- Step-2 contract report `.superpowers/sdd/tagged-union-task-4-report.md` §4 (site 6c deferral rationale).
