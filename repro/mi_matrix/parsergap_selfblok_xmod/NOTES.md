# parsergap_selfblok_xmod — RED: brace-less `if … ; else …` (self-compile blocker)

## What it tests
The construct that blocks self-compile — a **brace-less `if`** whose then-body is a
single expression statement terminated by `;`, immediately followed by `else`:

```zig
if (cond) z = 1;
else z = 2;
```

`parserParseIfStmt` (`sf/src/parser.zig:1516-1537`) parses a brace-less then-body via
`parserParseExprPrec` (line 1519), then consumes a trailing `;` (line 1535-1537)
**before** the `else` dispatch (line 1525). The `;` is absorbed into the if_stmt, so a
following `else` token reaches the statement loop at statement-start position and is
rejected as "expected expression / unexpected token".

## Pinned self-compile blocker (2026-08-17, `/tmp/fx_subfolder/zig1`)

Command (run from repo root; `--markers` floods stderr with marker noise):

```
mkdir -p /tmp/sc
cd /workspace/znineeight
timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig 2>/tmp/sc.err >/dev/null; echo rc=$?
grep -v "error\[9999\]" /tmp/sc.err | head -40
```

This run: **rc=2** (frontend error, completed; no error[9999] lines at all in this run).
Filtered `grep -a "error\[2000\]"` output (54 hits), FIRST non-9999 error[2000]:

```
sf/src/type_resolver.zig:981:24: error[2000]: expected expression
                        if (sz_node.kind == AstKind.add) arr_len = lhs + rhs;
                        ^^^^
sf/src/type_resolver.zig:981:24: error[2000]: unexpected token
sf/src/type_resolver.zig:982:20: error[2000]: expected expression
...
```

- **file:line = `sf/src/type_resolver.zig:981:24`** (the `else` on line 981; the caret is
  drawn over the enclosing if-statement at line 980).
- **Offending source lines** (`sf/src/type_resolver.zig:980-981`):

```zig
if (sz_node.kind == AstKind.add) arr_len = lhs + rhs;
else arr_len = lhs - rhs;
```

- Error cascade covers the rest of the `array_type` branch (981, 982, 983, 988, 989,
  990, 991, 996, 1013, 1015, 1016, 1020) then continues into later modules
  (util/hash.zig:18, c89_emit.zig:411, lexer.zig:236, diagnostics.zig:295, …).
- 2 `error[0]` unterminated-string-literal hits at `c89_emit.zig:1881/1882` are later
  recovery noise, not the root.
- Prior attribution `type_resolver.zig:981` (const-array-size evaluator) was a
  marker-trace approximation; the true root is the **parser** rejecting the brace-less
  if/else on that line.

## Measured baseline — RED (2026-08-17, `/tmp/fx_subfolder/zig1`)

```
/tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err
```

- **dump rc=2** (frontend error; no crash)
- **`error[2000]` ×2**, exact diagnostic:

```
main.zig:8:4: error[2000]: expected expression
    if (x > y) z = 1;
    ^^^^
main.zig:8:4: error[2000]: unexpected token
main.zig:10:0: error[2000]: expected expression
main.zig:10:0: error[2000]: unexpected token
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").

## Control (same construct, valid form) — GREEN

Wrap the brace-less then-body in braces (the form the rest of `sf/src` uses):

```zig
if (x > y) { z = 1; }
else z = 2;
```

- **dump rc=0**, `.c` emitted (10848 bytes); gcc rc=0; run rc=0, prints `1`.

## Isolated trigger variants (same file pattern, run 2026-08-17)

| Construct | rc | .c bytes |
|---|---|---|
| `if (c) z = 1;` (no else) | 0 | 10848 | GREEN |
| `if (c) z = 1; else { z = 2; }` | 2 | 0 | RED |
| `if (c) z = 1; else if (c2) z = 2; else z = 3;` | 2 | 0 | RED |
| `if (c) { z = 1; } else z = 2;` | 0 | 10848 | GREEN (control) |

⇒ Brace-less if WITH else is the trigger; the `;` then-body terminator makes
`parserParseIfStmt` swallow the if and orphan the `else`. Brace-less if without else is
fine; brace-less else-after-if only works when the then-body is a `{…}` block.

## Reduction steps
1. Self-compile run → filtered FIRST non-9999 `error[2000]` at `type_resolver.zig:981:24`.
2. Inspected lines 980-981 → identified brace-less `if/else`.
3. Wrote minimal fixture: `var` decls + brace-less if/else + `std.io.printInt` sink.
4. Confirmed RED (rc=2, error[2000], 0-byte .c) — matches self-compile diagnostic.
5. Control (braces around then-body) → GREEN rc=0, runs, prints 1.
6. Variants confirm `;` + else interaction is the trigger.

## Parser locus (sf/src/parser.zig)
- `parserParseIfStmt` (parser.zig:1490-1545):
  - line 1519: brace-less then-body via `parserParseExprPrec`.
  - line 1525: `else` dispatch **before** `;` handling — should fire but the next token
    is `;`, not `else`.
  - line 1535-1537: trailing `;` consumed → if_stmt ends; `else` becomes orphaned.
- Rejecting site: the statement loop sees `else` at statement-start → `error[2000]
  expected expression` + `error.UnexpectedToken`.

## Post-fix expectation (input to I-SELFBLOK)
`parserParseIfStmt` must not swallow the `;` before checking for `else`: peek for
`kw_else` immediately after the brace-less then-expression (before the `;` consumption),
or defer `;` absorption until after the else dispatch. After the fix: `if (c) z = 1;
else z = 2;` parses as one if_stmt with else — frontend GREEN (rc=0, .c emitted), and
the self-compile cascade at `type_resolver.zig:981` clears, unpinning the next blocker.
