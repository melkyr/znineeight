# parsergap_trailing_comma_xmod — RED: trailing comma in fn-call args rejected (DEFERRED to future plan)

## What it tests
A function call whose argument list ends in a trailing comma:

```zig
var result: i32 = c89EmitterInit(
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
);
```

The construct the Z98 self-hosted compiler uses at `sf/src/main.zig:749-759` — a
9-argument `c89EmitterInit(...)` call with a trailing comma after the last arg.

`parserParseFnCall` (`sf/src/parser.zig:394-407`) loops: parse an arg, then if the
next token is `rparen` break, else **expect a comma**. After a trailing comma the
next token IS `rparen`, so the loop does not break; it calls
`parserParseExprPrec(Prec.none)` at the `rparen`, which falls through
`parserParsePrimaryExpr` (`parser.zig:326-328`) → `error[2000] expected expression`.

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1` at HEAD 4efd4c73)

```
/tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` ×4**, exact diagnostic:

```
main.zig:18:4: error[2000]: expected expression
        9,
    ^
main.zig:18:4: error[2000]: unexpected token
        9,
    ^
main.zig:20:0: error[2000]: expected expression
    std.io.printInt(result);
^
main.zig:20:0: error[2000]: unexpected token
    std.io.printInt(result);
^
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").

## Control (same fixture, no trailing comma) — GREEN
Remove the trailing comma (line `        9,` → `        9`):

- **dump rc=0**, `.c` emitted; `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign
  -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x`
  rc=0; run rc=0, prints `45` (1+2+…+9).

## Isolated trigger
- `c89EmitterInit(1, 2, 3, 4, 5, 6, 7, 8, 9)` (no trailing comma): **dump rc=0, GREEN**.
- `c89EmitterInit(1, 2, 3, 4, 5, 6, 7, 8, 9,)` (trailing comma): **dump rc=2, RED**.

⇒ The trigger is EXACTLY the trailing comma after the last argument. (The arg-count
9 is not special — any arg count with a trailing comma reproduces.)

## Parser locus (sf/src/parser.zig)
- **Rejecting site:** `parserParseFnCall` arg loop (`parser.zig:401-407`) — it breaks
  only on `rparen` immediately after an arg, then expects a comma otherwise; a
  trailing comma is consumed by `parserExpect(comma)` (`parser.zig:406`) and the
  loop re-parses an arg at the `rparen`, hitting `parserParsePrimaryExpr` fallthrough
  (`parser.zig:326-328`) → `error[2000] expected expression`.
- **Working analogues that DO allow a trailing separator:** array literal
  `parser.zig:766`, anonymous/tuple literal `parser.zig:731`, switch-prong list
  `parser.zig:827-829` — each does `if (peek == comma) advance` inside the loop so a
  trailing comma before the closing delimiter is consumed.

## Post-fix expectation (for the future plan)
Mirror the array-literal/tuple-literal pattern in `parserParseFnCall`
(`parser.zig:401-407`): after `parserParseExprPrec`, advance over an optional
trailing comma, then break when the next token is `rparen`:

```zig
if (parserPeek(self).kind == TokenKind.rparen) break;
_ = try parserExpect(self, TokenKind.comma);
```

(Optionally restructure so a comma is only consumed when a real argument follows,
as the tuple/array loops do.) After the fix: **frontend GREEN** (rc=0, `.c` emitted,
gcc rc=0, run rc=0 printing `45`), matching the no-trailing-comma control above.
