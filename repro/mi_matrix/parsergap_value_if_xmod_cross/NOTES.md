# parsergap_value_if_xmod_cross — RED: cross-module `if (opt) |cap|` rejected in VALUE position (defect F-PARSERGAP)

## What it tests
The CROSS-MODULE variant of F-PARSERGAP: an optional value crosses a module boundary
(`lib.get_opt() -> ?i32`) and is captured via `|cap|` inside a value-position `if` in
`main`:

```zig
// lib.zig
pub fn get_opt() ?i32 { return 42; }

// main.zig
var x: i32 = if (lib.get_opt()) |cap| cap else -1;
```

The optional-capture `|cap|` in VALUE position is the trigger; the single-module repro
`parsergap_value_if_xmod` proves the same construct in the same module is RED. This
fixture proves the defect crosses the module boundary — the optional originates in
`lib.zig` (a separate import) and is captured in `main.zig`. The value-position `if`
with a capture is valid Zig (mirrors `sf/src/main.zig:680`); the parser simply has no
optional-capture handling in `parserParseIfExpr` (`sf/src/parser.zig:782-800`), while the
statement-position path (`parserParseIfStmt`) handles `|cap|` correctly.

The fixture is self-contained: bare `@import("std")` (resolved via installed canonical
lib at `/tmp/fx_subfolder/lib/`) + bare `@import("lib.zig")` (same-directory sibling).

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1` at HEAD, run from repro dir)

```
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` ×4**, exact diagnostic:

```
main.zig:5:36: error[2000]: expected expression
pub fn main() void {
                                    ^
main.zig:5:36: error[2000]: unexpected token
pub fn main() void {
                                    ^
main.zig:7:0: error[2000]: expected expression
    std.io.print_int(x);
^
main.zig:7:0: error[2000]: unexpected token
    std.io.print_int(x);
^
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").
- Error locus is `main.zig:5:36` = the `|cap|` capture token in the value-position `if`
  in `main`; the optional-returning call `lib.get_opt()` parses fine (lib module resolves).

## Post-fix expectation
With the F-PARSERGAP grammar fix (pipe-check + capture payload in `parserParseIfExpr`,
`sf/src/parser.zig:782-800`), this fixture must:
- **dump rc=0** (`.c` emitted for both `lib.zig` and `main.zig` modules), then
  `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c
  sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x` rc=0,
- **run rc=0, prints `42`** (the optional value from `lib.get_opt()` crosses the module
  boundary, is captured, and lands in `x`).

## Isolated trigger (from single-module repro `parsergap_value_if_xmod/NOTES.md`)
- `var x = if (o) 5 else 0;` (value-position `if`, NO capture): GREEN.
- `if (o) |cap| r = cap;` (statement-position `if`, WITH capture): GREEN.
- `var x = if (o) |cap| cap else 0;` (value-position `if`, WITH capture): RED.
- Cross-module variant here: `var x = if (lib.get_opt()) |cap| cap else -1;` → RED (this fixture).
