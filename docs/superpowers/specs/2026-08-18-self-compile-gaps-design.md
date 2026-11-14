# Self-Compile Gaps (Wrap/Sat Operators + Multi-Line Source Bug + Switch-Prong) — Design Spec

**Date:** 2026-08-18
**Status:** Approved by operator (rulings 2026-08-18)
**Branch:** zig1_start

## Problem

Self-compile (`zig1` compiling `sf/src/main.zig`) is blocked by 3 pre-existing gaps. Two are genuine compiler non-conformances (zig1 rejects valid Zig); one is a source bug in the compiler's own code (zig1 is correct to reject it). All 3 were recorded as self-compile blockers at HEAD `908d502e`:

1. **`*%` wrapping-multiply** at `sf/src/util/hash.zig:18` — `hash = hash *% 16777619;`. No lexer token for `*%`.
2. **Multi-line string literal** at `sf/src/c89_emit.zig:1881-1882` — a literal newline inside `"..."` quotes.
3. **Switch-prong value-less `return`** at `sf/src/lexer.zig:236` — `else => return,`.

## Zig-spec verification (ziglang.org master, verified 2026-08-18)

### Gap 1: wrapping/saturating operators

From the langref "Table of Operators" and "Runtime Integer Values" sections, Zig provides wrapping and saturating arithmetic operators on all targets:

| Class | Operators | Compound-assign |
|---|---|---|
| Wrapping | `+%` `-%` `*%` | `+%=` `-%=` `*%=` |
| Saturating | `+|` `-|` `*|` `<<|` | `+|=` `-|=` `*|=` `<<|=` |
| Wrapping negation (prefix) | `-%a` | — |

`zig1` currently supports only the plain operators `+ - * / % << >> & | ^` and their `=`-assign forms. **All 15 wrapping/saturating forms are missing** — a lexer/parser gap, not a source issue. Note `-%` is ambiguous: **prefix** (wrapping negation, e.g. `-%a`) vs **binary** (wrapping subtraction, e.g. `a -% b`); the parser must disambiguate by context.

### Gap 2: multiline strings — CORRECTED UNDERSTANDING

The langref "Multiline String Literals" section is explicit:

> To start a multiline string literal, use the `\\` token. Just like a comment, the string literal goes until the end of the line. The end of the line is not included in the string literal. However, if the next line begins with `\\` then a newline is appended and the string literal continues.

So a **literal newline inside `"..."` is INVALID Zig** (a regular string literal does not span lines). `c89_emit.zig:1881-1882`:
```zig
var fwdnl2: []const u8 = "
"; pal.markerWrite(fwdnl2);
```
is therefore a **source bug** — the lexer is *correct* to report `ERR_1000 unterminated string`. The intended value is `"\n"` (a newline byte), which must be written with the escape. This is **NOT** a compiler gap. (The optional `\\`-prefixed multiline-string feature is a separate conformant feature; the operator ruled it **out of scope** for this plan.)

### Gap 3: switch-prong value-less return/break/continue

`switch` prongs accept any expression, including value-less `return`, `break`, and `continue` (`else => return,` is valid Zig). `zig1`'s `parserParseReturnExpr` (`parser.zig:1659-1664`) only skips the value when the next token is `;`, so `return,` in a switch prong mis-parses (`error[2000]`).

## Root causes

| Gap | Root cause | Fix class |
|---|---|---|
| 1 | Lexer has no `*%`/`+|`/etc. lookahead branches; parser infix table has no entries; no AstKind/LIR/emit handling | **Compiler fix** (conformant) |
| 2 | Source uses literal newline inside `"..."` | **Source migration** (1 line) |
| 3 | `parserParseReturnExpr`/`BreakExpr`/`ContinueExpr` only treat `;` as "no value" | **Compiler fix** (conformant) |

## Design

### D1 (Gap 1): Add the full wrapping/saturating operator family

Add all 15 forms to the lexer/parser/AST/lowerer/LIR/emitter:

- **Lexer** (`lexer.zig:73` `+`, `:77` `-`, `:81` `*`, `:111` `<<`): lookahead for `%`/`|` after `+ - *` and for `|` after `<<` → new `TokenKind` entries (`token.zig:28-57`).
- **Parser infix table** (`parser.zig:236-281`): new binary AstKinds (`add_wrap`, `sub_wrap`, `mul_wrap`, `add_sat`, `sub_sat`, `mul_sat`, `shl_sat`). Prefix `-%` handled in the primary-expression/prefix parser, disambiguated from binary `-%` by context.
- **AST** (`ast.zig`): new node kinds for each operator (mirroring existing `add`/`sub`/`mul`/`shl`).
- **Lowerer/LIR**: new LIR insts (mirroring existing arithmetic insts).
- **Emitter** (`c89_emit.zig`): wrapping ops emit plain C `+ - *` (unsigned C arithmetic wraps by definition); saturating ops emit explicit min/max clamping; saturating `<<|` emits clamped shift.
- **Compound-assign** forms (`+%=` etc.) route through the existing compound-assign lowering with the new op kinds.

### D2 (Gap 2): Source migration

`c89_emit.zig:1881-1882` → the escaped single-line form:
```zig
var fwdnl2: []const u8 = "\n"; pal.markerWrite(fwdnl2);
```
The string value (`\n`) is unchanged → emitted C identical → **4 MD5 gates byte-identical, no re-baseline**. No lexer change.

### D3 (Gap 3): Switch-prong value-less return/break/continue

`parserParseReturnExpr`/`parserParseBreakExpr`/`parserParseContinueExpr` treat `,`/`}` (and `;`) as "no value" terminators. Mirrors the existing `;` check; byte-identity preserved for all currently-valid inputs (they already parse; the change only admits previously-rejected prong bodies).

## Constraints

- `sf/build/out_release/` is WEDGED — NEVER touch/ls/build into it; use `timeout`.
- Compiler under test: `/tmp/fx_subfolder/zig1`. Build via `bash sf/scripts/build_release.sh` (gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`); reinstall std after every rebuild.
- Z98 dialect: NO `anytype`, NO `@Type`. Use `fastedit` only (no sed/python).
- Byte-identity is the hard gate unless an operator ruling re-baselines. Baselines: gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3` (repo-root CWD), mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus 264 dirs (per-module recipe): OK=254/FAIL=6/ICE=0/CRASH=0/GG=4. 21-example matrix 21/21; test_analyzer "5 passed, 4 failed".
- `zig0` bootstrap is immutable — NOT to be changed.
- Verification MUST scan the WHOLE tree for the defect class (M4 lesson), never stop at the first error.
- Gap 2 is source-only; `\\`-multiline-string support is explicitly OUT of scope (operator ruling 2026-08-18).

## Success criteria

1. Self-compile passes the 3 currently-blocking constructs (`hash.zig:18`, `c89_emit.zig:1881`, `lexer.zig:236`); the next blocker (if any) is recorded, not fixed.
2. All 15 wrapping/saturating operator forms parse and run correctly (battery GREEN).
3. All 4 MD5 gates byte-identical (no re-baseline).
4. Corpus 264, matrix 21/21, test_analyzer unchanged.
5. Tree-wide scan confirms no same-class construct remains unsupported.
