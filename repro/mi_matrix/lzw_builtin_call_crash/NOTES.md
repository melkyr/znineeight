# lzw_builtin_call_crash — RED  [Task P1-4, 2026-08-04]

## What it tests
Guards the analyzer `analyzeExpr` builtin_call crash (regression commit `532420cb`,
last-good `7bc6e4d1`). A single-file, no-import reproduction of the
`examples/z98/lzw/main.zig:17` crash: an `@intCast` builtin inside an `if` condition.

## Root cause
`builtin_call.child_0` holds the builtin's **string name_id**, not an AST node index
(parser.zig:611 `astStoreAddNode(..., AstKind.builtin_call, ..., id, 0, 0, payload)`).
`analyzeExpr`'s generic child fallback (analyzer.zig:504-506) recursed into `child_0/1/2`
as node indices for every kind. When the name_id numerically collides with the enclosing
`if_stmt`'s node index, it forms a cycle (`if_stmt → bool_and → cmp_ne → builtin_call →
child_0=if_stmt → …`) → infinite recursion → stack overflow. Full analysis in
`.superpowers/sdd/I-lzw-regression-report.md`.

## Expected classification
- **Pre-fix (HEAD `5e8806fa`): CRASH** — `--dump-c89` rc=139 (SIGSEGV), 0 `.c` emitted.
  Bypassed by `--no-null-check --no-lifetime-check --no-leak-check` (rc=0, 1 `.c`).
- **Post-fix: OK** — dump rc=0, gcc-clean, links, runs (stdin EOF → getchar returns -1 →
  prints `invalid`).

## Fix
`analyzeExpr` now handles `builtin_call` by walking its ARGUMENTS via
`astStoreGetExtraChildren(ctx.store, node.payload)` (mirroring the `fn_call` branch),
never recursing into `child_0` (the name_id). analyzer.zig:495-502.
