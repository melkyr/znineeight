# labeled_stmt_unhandled — FAIL (frontend gap, error[3020])  [I-task: rogue_mud build attempt, 2026-08-07]

## What it tests
A labeled statement — `game_loop: while (true) { ... }` — i.e. a label
prefixing a statement (here a `while` loop), with a `break :game_loop`
referencing the label. This is the ONLY new distinct compiler gap hit by
`examples/z98/rogue_mud/` on the current tree.

## Origin (rogue_mud)
Discovered attempting to build `examples/z98/rogue_mud/main.zig` with the
current zig1 (`/tmp/zigaps/zig1`, bootstrap 2026-08-07). Dump fails at
type resolution with 2 identical `error[3020]` diagnostics — one per labeled
statement in the program:
- `examples/z98/rogue_mud/main.zig:92` — `game_loop: while (true) { ... }`
  (the outer game loop of `main`).
- `examples/z98/rogue_mud/lib/scenario.zig:59` — `bsp_loop: while (stack.len > 0) { ... }`
  (the BSP split loop of `generateDungeon`).
Both are the same distinct failure (AST kind `labeled_stmt`); the reported
diagnostic locations (`main.zig:32:2`, `scenario.zig:159:8`) are BOGUS —
they point at unrelated source lines (see "Diagnostic-location bug" below).

## The compiler gap
`sema`'s statement dispatcher `semanticAnalyzerResolveStmtIter`
(`sf/src/semantic_analyzer.zig:1599-1778`) has no `labeled_stmt` case. A
`labeled_stmt` node (AstKind 82) falls into the generic `else` at
`:1773-1777`, which forwards it to `semanticAnalyzerResolveExpr`; that
function's dispatch (kind list at `:1360-1423`) also has no `labeled_stmt`
case, so it hits the unhandled-else at `:1424-1429` and emits
`error[3020]: internal error: unhandled node kind in type resolution`.
The correct behavior is to treat the label like a transparent prefix and
push the wrapped child (the `while_stmt`) onto the stmt work stack.

## Diagnostic-location bug (secondary, same repro)
The `error[3020]` diagnostic is emitted with `node_idx` passed as BOTH the
start and end span (`semantic_analyzer.zig:1428`:
`diagnosticCollectorAdd(..., node_idx, node_idx, ...)`), so the reported
file:line never matches the labeled statement — it points at arbitrary
earlier source. Not a separate repro: only reachable through this unhandled
node path, and this repro already exercises it.

## Measured result (2026-08-07, /tmp/zigaps/zig1)
- dump rc=2, stderr: `error[3020]: internal error: unhandled node kind in
  type resolution` (markers: `ST:N<node> ST:K82` — kind 82 = `labeled_stmt`).
- 0 `.c` emitted (frontend type-resolution failure).
- gcc not reached.
- Classification: **FAIL** (real compiler gap — not a green-guard; NOT an ICE
  — rc=2 and `error[3020]` is outside the ICE regex).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/…/out.c repro` accepts the labeled loop (rc=0,
emits C) — labeled statements are valid Z98, so this is a genuine compiler
gap, not a correct rejection.

## Expected classification
FAIL until `semanticAnalyzerResolveStmtIter` gains a `labeled_stmt` arm
that unwraps to its child (mirroring the `defer_stmt`/`while_stmt` pattern).
