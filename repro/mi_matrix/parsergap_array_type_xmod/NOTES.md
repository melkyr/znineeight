# parsergap_array_type_xmod — RED: `expected '{' after array type` (DEFERRED to future plan)

## What it tests
A bare array type used as a **const value** (type alias):

```zig
const Buf = [10]u8;
```

`parserParsePrimaryExpr` (`sf/src/parser.zig:318`) sends every leading `[` token
(in expression position) to `parserParseArrayLiteral` (`parser.zig:752`), which
parses the array type via `parserParseBracketType` and then **requires a `{`** body
(`parser.zig:755-758`). A `[N]T` type with no `{` literal fails:

```
parser.zig:756: expected '{' after array type
```

Self-compile hit this at `sf/src/lower.zig:2283`: that line contains both the
`|_|` discard-capture (see `parsergap_discard_if_xmod`) and several
`var x: []const u8 = "…"` / `var x: [10]u8 = undefined;` array/slice-typed
declarations; after the if-capture parse failure the parser recovers into the
block in a confused expression context, hits the `[` of the array/slice types, and
emits `expected '{' after array type` (observed ×2 on that line). The minimal
**independent** trigger is the const type-alias above: `[10]u8` in expression
position with no `{` following.

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1` at HEAD 4efd4c73)

```
/tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` ×2**, exact diagnostic:

```
main.zig:3:12: error[2000]: expected '{' after array type
main.zig:3:18: error[2000]: unexpected token
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").

## Control (array type as var-decl annotation) — GREEN
Replace the const alias with a typed var (the form at lower.zig:2280/2283):

```zig
var b: [10]u8 = undefined;
```

- **dump rc=0**, `.c` emitted; gcc rc=0; run rc=0, prints `3`.

⇒ `[10]u8` parses fine through `parserParseType` → `parserParseBracketType`
(var-decl annotations, fn params, struct fields); it fails ONLY when `[` appears in
**expression/primary position** (const value / type alias) where
`parserParseArrayLiteral` demands an immediate `{`.

## Isolated trigger
- `var b: [10]u8 = undefined;` (annotation via `parserParseType`): **dump rc=0, GREEN**.
- `var s: []const u8 = "abc";` (slice annotation): **dump rc=0, GREEN**.
- `[10]u8{1, 2, 3}` (array literal, `{` present): **dump rc=0, GREEN**.
- `const Buf = [10]u8;` (array type as const value): **dump rc=2, RED**.
- `const S = []const u8;` (slice type as const value): **dump rc=2, RED**
  (`expected '{' after array type`).

## Parser locus (sf/src/parser.zig)
- **Dispatch:** `parserParsePrimaryExpr` (`parser.zig:318`) → `parserParseArrayLiteral`
  for any expression-position `[`.
- **Rejecting site:** `parserParseArrayLiteral` (`parser.zig:752-759`) — after
  `parserParseBracketType` parses `[10]u8`, it requires the next token to be `{`
  and otherwise emits `expected '{' after array type` + `error.UnexpectedToken`.
- **Type path (works):** `parserParseType` (`parser.zig:935`) → `parserParseBracketType`
  (`parser.zig:980`) produces `AstKind.array_type` / `slice_type` without a `{` check.

## Post-fix expectation (for the future plan)
Give `parserParseArrayLiteral` (`parser.zig:752`) a no-`{` branch: after
`parserParseBracketType`, if the next token is NOT `{`, return the bracket type node
(`array_type`/`slice_type`) directly instead of erroring — i.e. allow a bare array
type as an expression (so `const Buf = [10]u8;` and type aliases in general parse).
The recovery cascade at lower.zig:2283 then also disappears once
`parsergap_discard_if_xmod` is fixed. After the fix: **frontend GREEN** (rc=0, `.c`
emitted, gcc rc=0, run rc=0 printing `3`), matching the var-annotation control above.
