# parsergap_value_if_xmod — RED: `if (opt) |cap|` rejected in VALUE position (defect F-PARSERGAP)

## What it tests
A minimal value-position `if` with an optional capture `|cap|` — the construct the Z98
self-hosted compiler uses at `sf/src/main.zig:680`:

```zig
var gv_tid: u32 = if (gv_rt) |grt| grt else type_mod.TYPE_UNDEFINED;
```

`parserParseIfExpr` (`sf/src/parser.zig:782`) has NO optional-capture handling: after the
`)` it parses the then-body directly with `parserParseExprPrec(Prec.none)` (line 787), so a
leading `|cap|` (a `pipe` token = binary bit_or, not a primary) falls through to
`parserParsePrimaryExpr` (`parser.zig:326-328`) and dies with `error[2000] expected expression`.
The SAME construct in STATEMENT position works because `parserParseIfStmt` (`parser.zig:1486-1495`)
explicitly checks for a leading `pipe`, parses `|name|` into an `AstKind.if_capture` node, and
passes it as the `if_stmt` node's `payload`.

The fixture is self-contained: bare `@import("std")` (resolved via installed canonical lib at
`/tmp/fx_subfolder/lib/`) + one function doing `var x = if (o) |cap| cap else 0;`.

## Measured baseline — RED (2026-08-16, `/tmp/fx_subfolder/zig1` at HEAD)

```
/tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` ×4**, exact diagnostic:

```
repro/mi_matrix/parsergap_value_if_xmod/main.zig:4:24: error[2000]: expected expression
fn take_cap(o: ?i32) i32 {
                        ^
repro/mi_matrix/parsergap_value_if_xmod/main.zig:4:24: error[2000]: unexpected token
fn take_cap(o: ?i32) i32 {
                        ^
repro/mi_matrix/parsergap_value_if_xmod/main.zig:6:0: error[2000]: expected expression
    return x;
^
repro/mi_matrix/parsergap_value_if_xmod/main.zig:6:0: error[2000]: unexpected token
    return x;
^
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").

## Control (same fixture, statement position) — GREEN
Replace the value-position line with `if (o) |cap| r = cap;` (stmt position):

- **dump rc=0**, `.c` emitted; `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign
  -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x`
  rc=0; run rc=0.

## Isolated trigger
- `var x = if (o) 5 else 0;` (value-position `if`, NO capture): **dump rc=0, GREEN**.
- `if (o) |cap| r = cap;` (statement-position `if`, WITH capture): **dump rc=0, GREEN**.
- `var x = if (o) |cap| cap else 0;` (value-position `if`, WITH capture): **dump rc=2, RED**.

⇒ The trigger is EXACTLY the optional-capture `|cap|` in VALUE position; neither component
alone reproduces.

## Parser locus (sf/src/parser.zig)
- **Rejecting site:** `parserParseIfExpr` (line 782): then-body parsed at `parser.zig:787` via
  `parserParseExprPrec(Prec.none)` with no leading-`pipe` check; the `pipe` reaches
  `parserParsePrimaryExpr` fallthrough (`parser.zig:326-328`) → `error[2000] expected expression`.
  The `if_expr` node built at `parser.zig:798-799` hardcodes `payload = 0` (no capture slot).
- **Working stmt path:** `parserParseIfStmt` (line 1463), capture parse at `parser.zig:1486-1495`
  → `AstKind.if_capture` node stored as `if_stmt` payload (`parser.zig:1525-1526`).
- **Dispatch:** value-position `if` enters via `parserParseExprPrec`→`parserParsePrimaryExpr`
  (`parser.zig:316`), reached from var-init `parserParseVarDecl:1344`, return, fn-call args, etc.
- **Node shapes (sf/src/ast.zig):** `if_stmt`=68 {cond, then, else, payload=capture};
  `if_expr`=69 {cond, then, else, payload=0}; `if_capture`=70 {payload=name ID}
  (comment `ast.zig:315`).
- **Sema already prepared:** `semanticAnalyzerResolveIfHeader` (`semantic_analyzer.zig:1716-1724`)
  registers the capture local from `node.payload`; called from BOTH
  `semanticAnalyzerResolveIfExpr:934` and the `if_stmt` path `semantic_analyzer.zig:1533`.
  Lowerer `if_expr` (`lower.zig:3310`) resolves the capture name via the symbol registrator.

## Grammar-fix scope (for F-PARSERGAP-Inv)
PURELY in `parserParseIfExpr` (`parser.zig:782-800`):
1. After the `rparen`, mirror `parserParseIfStmt`'s pipe check (`parser.zig:1486-1495`):
   if peek == `pipe`, advance, expect identifier, expect `pipe`, store
   `AstKind.if_capture` node.
2. Pass the capture node as the `payload` arg of the `astStoreAddNode(if_expr, …)` at
   `parser.zig:798-799` (replace hardcoded `0`).
No sema/ast/lower changes required. (Optional: also accept `lbrace` then-body like
`parser.zig:1498-1502` if value-blocks are desired; NOT required by `main.zig:680`.)
