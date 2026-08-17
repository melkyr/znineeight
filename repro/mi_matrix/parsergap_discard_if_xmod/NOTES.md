# parsergap_discard_if_xmod — RED: `if (opt) |_|` discard-capture rejected (DEFERRED to future plan)

## What it tests
A minimal statement-position `if` with a **discard capture** `|_|`:

```zig
if (opt) |_| {
    r = 1;
} else {
    r = 2;
}
```

The construct the Z98 self-hosted compiler uses at `sf/src/cinclude.zig:23`:

```zig
if (hash_mod.u32ToU32MapGet(&seen, name_id)) |_| {
    // skip duplicate
} else { ... }
```

`parserParseIfStmt` (`sf/src/parser.zig:1499`) parses the capture name with
`parserExpect(self, TokenKind.identifier)`, but `_` lexes as `TokenKind.underscore`
(`sf/src/lexer.zig:422`) — so the expect fails. The switch-prong path
(`parser.zig:893`) and `parserParseVarDecl` (`parser.zig:1337`) already special-case
`underscore`; the if-stmt capture path does not.

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1` at HEAD 4efd4c73)

```
/tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` ×10**, exact diagnostic:

```
main.zig:13:14: error[2000]: expected identifier but found token
    var r: i32 = 0;
              ^
main.zig:13:14: error[2000]: unexpected token
    var r: i32 = 0;
              ^
main.zig:15:4: error[2000]: expected expression
        r = 1;
    ^
main.zig:15:4: error[2000]: unexpected token
        r = 1;
    ^
main.zig:15:6: error[2000]: expected expression
        r = 1;
      ^^^^
main.zig:15:6: error[2000]: unexpected token
        r = 1;
      ^^^^
main.zig:17:4: error[2000]: expected expression
        r = 2;
    ^
main.zig:17:4: error[2000]: unexpected token
        r = 2;
    ^
main.zig:19:0: error[2000]: expected expression
    std.io.printInt(r);
^
main.zig:19:0: error[2000]: unexpected token
    std.io.printInt(r);
^
```

- Line 13 is `if (opt) |_| {`; the reported `13:14` is the `_` token. The source
  snippet the diagnostics print is stale (off-by-one line cache) — the error
  positions, not the snippets, are authoritative.
- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").

## Control (same fixture, named capture `|cap|`) — GREEN
Replace `|_|` with `|cap|` (statement-position named capture, the F-PARSERGAP path):

- **dump rc=0**, `.c` emitted; `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign
  -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x`
  rc=0; run rc=0, prints `1` (opt non-null → then-branch).

## Isolated trigger
- `if (opt) |cap| { r = 1; } else { r = 2; }` (named capture): **dump rc=0, GREEN**.
- `if (opt) |_| { r = 1; } else { r = 2; }` (discard capture): **dump rc=2, RED**.

⇒ The trigger is EXACTLY the discard capture name `_` in the if-stmt capture; the
named-capture control is green.

## Parser locus (sf/src/parser.zig)
- **Rejecting site:** `parserParseIfStmt` capture parse at `parser.zig:1499`
  (`parserExpect(self, TokenKind.identifier)`) after advancing over the leading
  `pipe` (`parser.zig:1497-1498`). `_` lexes as `TokenKind.underscore`, so the
  expect fails with `error[2000] expected identifier but found token`.
- **Lexer:** `_` → `TokenKind.underscore` (`sf/src/lexer.zig:422`).
- **Working analogues that DO accept `_`:** switch-prong capture `parser.zig:893-897`,
  var-decl name `parser.zig:1337`.
- **Same defect in the value path:** `parserParseIfExpr` capture (`parser.zig:790`) also
  uses `parserExpect(identifier)` and would reject `|_|` in value position the same way.

## Post-fix expectation (for the future plan)
In `parserParseIfStmt` (and `parserParseIfExpr`), accept `TokenKind.underscore` for the
capture name like the switch-prong path does (`parser.zig:893`):

```zig
if (parserPeek(self).kind == TokenKind.underscore) {
    name_tok = try parserExpect(self, TokenKind.underscore);
} else {
    name_tok = try parserExpect(self, TokenKind.identifier);
}
```

After the fix: **frontend GREEN** (rc=0, `.c` emitted, gcc rc=0, run rc=0 printing `1`),
matching the named-capture control above. No sema/ast/lower changes required (the
capture is discarded; sema already resolves `if_capture` payloads).
