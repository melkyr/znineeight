# anon_init_if_arm — RED (class-C branch-join anon-init)

## Form
Anonymous tagged-union init in **both arms of an if-expression** assigned to a typed var:
```zig
var c: Command = if (cond) .{ .Go = @intCast(i32, 9) } else .{ .Quit = {} };
```
where `Command = union(enum) { Quit: void, Go: i32 }`, then read back `.Go` via switch.

## Expected
`9`.

## Empirical result on HEAD `0abe2efa` (Task 4 Step 1b, 2026-07-08)
**RED — gcc fails to compile.** dump rc=0 (C emitted), but gcc errors:
```
/tmp/anon_init_if_arm.c:47:12: error: 'zT_5' undeclared (first use in this function); did you mean 'zT_9'?
/tmp/anon_init_if_arm.c:51:12: error: 'zT_7' undeclared (first use in this function); did you mean 'zT_9'?
```

The if-arm anonymous inits (`.{ .Go = 9 }` / `.{ .Quit = {} }`) resolve to `TYPE_VOID` (no expected
type at the branch-join arm), so the anon-init temps (`zT_5`, `zT_7`) are never properly declared /
emitted; the join assignment `zT_4 = zT_5;` references an undeclared temp. Neither arm writes
`.payload.Go._0` (0 payload writes in the dump).

## Root cause / fix layer
This is a **class-C** site in the site-map (`.superpowers/sdd/anon-init-sitemap-report.md`):
`semanticAnalyzerResolveIfExpr` (~`semantic_analyzer.zig:754-768`) resolves the arms with no expected
type available, so anon `.{}` inits fall to `TYPE_VOID`. Task 4 Step 4 wires the class-C branch-join
sites to propagate the `expected_type_stack` top (the `var c: Command` declared type) into each arm.

## Cross-links
- Task 4 (`.opencode/plans/2026-07-08-tagged-union-payload-store.md`): expected_type_stack root fix;
  Step 4 handles class-C (if-arm / switch prong / orelse / array element).
- Contrast: `repro/anon_init_var_decl` (typed var-decl anon-init) already works (green guard).
