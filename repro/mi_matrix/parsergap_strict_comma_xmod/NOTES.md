# parsergap_strict_comma_xmod — RED: fn-call missing-comma `f(1 2)` SILENTLY accepted (A-F3)

## What it tests
A fn-call argument list missing the separating comma is **silently accepted** and
compiles into the same program as the valid 2-arg call:

```zig
var r1 = f(1 2);        // malformed — no comma between args
```

The loop-top mirror at `parser.zig:401-407` advances the comma **optionally**
(`parser.zig:405`: `if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);`),
so after parsing argument `1` the parser never demands a `,` — it falls into the
`while` loop, parses `2` as a second argument, and emits a normal 2-arg fn_call.
The A-F3 diagnostic fix (F2) must make this a hard error. This RED baseline is the
gate for F2 (restore strict comma diagnostics at the fn-call loop-top).

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1`, repo HEAD `c8d08939`)

Run from the repro dir (CWD = repro dir; bare `@import("std")` resolves via the
installed lib at `/tmp/fx_subfolder/lib`):

```
cd repro/mi_matrix/parsergap_strict_comma_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```

- **rc=0** (SILENT — no diagnostic, no crash)
- **`/tmp/x.err` is 0 bytes** (empty stderr)
- **`/tmp/x.c` = 10495 bytes** (`.c` emitted — the malformed call fully compiles)
- **gcc on the emitted C: rc=0** (links clean)
- **run: rc=0, prints `3`** — `f(1 2)` behaves exactly like `f(1,2)`.

```
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x   # gcc rc=0
timeout 30 /tmp/x                                                                                                                          # prints: 3run rc=0
```

⇒ Full silent regression: malformed `f(1 2)` not only passes the frontend, it
compiles AND runs and prints `3`. Classified **FAIL-by-silence** (a valid-looking
frontend gap — must be classified FAIL, never OK).

## Unterminated variant `f(1` — NOT silent today
Second fixture variant (code kept here as a comment block; the file itself was not
committed so the dir contains exactly `main.zig` + `NOTES.md`):

```zig
const std = @import("std");
fn f(a: i32, b: i32) i32 { return a + b; }
pub fn main() void {
    var r1 = f(1;
    std.io.printInt(r1);
}
```

Run (same command shape, source at `/tmp/unterminated.zig`):
`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 /tmp/unterminated.zig > /tmp/u.c 2>/tmp/u.err; echo rc=$?`

- **rc=2** (frontend error; no crash)
- `/tmp/u.err`:

```
/tmp/unterminated.zig:4:16: error[2000]: expected expression
pub fn main() void {
                ^
/tmp/unterminated.zig:4:16: error[2000]: unexpected token
pub fn main() void {
                ^
/tmp/unterminated.zig:6:0: error[2000]: expected expression
    std.io.printInt(r1);
^
/tmp/unterminated.zig:6:0: error[2000]: unexpected token
    std.io.printInt(r1);
^
```

- **`/tmp/u.c` = 0 bytes** (no `.c` emitted)

⇒ The unterminated case errors today (`error[2000]` cascade, rc=2). Only the
**missing-comma** case is the silent regression.

## Controls (must stay GREEN — the F2 fix must not break them)
- **Valid call `f(1,2)`**: `var r1 = f(1,2);`
  → **dump rc=0**, `.c` emitted (**10495 B**), gcc rc=0, run rc=0, prints `3`.
- **Trailing comma `f(1,2,)`**: `var r1 = f(1,2,);`
  → **dump rc=0**, `.c` emitted (**10495 B**), no stderr.
- **Byte-identical proof**: the emitted `.c` for `f(1 2)`, `f(1,2)`, and `f(1,2,)`
  are all byte-identical (`cmp` clean) — the parser literally drops the missing
  comma and builds the same 2-arg call AST.

## Expected post-fix behavior (per F2)
- `f(1 2)` → **rc=2**, `error[2000] expected ','` (RED restored).
- `f(1` → **rc=2** (error; already errors today — behavior must be preserved).
- `f(1,2,)` → **rc=0**, stays GREEN (trailing comma legal).

## Locus (for F2)
`sf/src/parser.zig:401-407` — fn-call loop-top mirror. Line 405
`if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);` makes the
comma optional. F2 must require a `,` between args: after parsing an argument, if
the next token is not `rparen` (and not an `eof`), demand `comma` and emit
`error[2000] expected ','` otherwise — while still accepting the trailing comma
(`f(1,2,)`) case per the GREEN control.
