# Strict-Zig Brace Migration — Design Spec

**Date:** 2026-08-18
**Status:** Approved by operator (ruling 2026-08-18)
**Branch:** zig1_start

## Problem

The self-hosted compiler `zig1` rejects the `if (cond) stmt; else …` construct (semicolon before `else`), which its own bootstrap `zig0` accepts. Because `zig1`'s own source (`sf/src/*.zig`) uses this construct, **self-compile is blocked** at `type_resolver.zig:981`.

Per the Zig language reference grammar (verified against ziglang.org master, Appendix → Grammar):

```
IfStatement
    <- IfPrefix BlockExpr (KEYWORD_else Payload? Statement / !KEYWORD_else)
     / IfPrefix !BlockExprPrefix AssignExpr (SEMICOLON / KEYWORD_else Payload? Statement)
WhileStatement / ForStatement: same shape
```

- `if (cond) stmt;` — **valid** (AssignExpr body + `;`)
- `if (cond) stmt else stmt;` — **valid** (AssignExpr body + `else`, no `;`)
- `if (cond) stmt; else stmt;` — **INVALID** (`;` before `else`)

The same rule applies to `while` and `for` statements.

## Root cause

`zig0` (C++98 bootstrap, immutable) is **lenient**: its `parseStatement` (parser.cpp:1971-1979) returns a bare expression without requiring `;`, so it accepts the invalid `;`-before-`else` form. `zig1` is **proper Zig**: it already rejects that form (`error[2000]`). The defect is therefore in `sf/src`'s **source**, not in `zig1`.

## Exact scope (measured)

The invalid `;`-before-`else` construct appears in exactly **3 sites**, all inside the self-compile closure:

| Site | Construct |
|---|---|
| `sf/src/type_resolver.zig:980-981` | `if (kind == add) arr_len = lhs + rhs;` / `else arr_len = lhs - rhs;` |
| `sf/src/type_resolver.zig:987-990` | `if (kind == mul) arr_len = lhs * rhs;` / `else if (kind == div) …;` / `else arr_len = lhs % rhs;` |
| `sf/src/diagnostics.zig:295-296` | `if (level == 0) self.error_count += 1;` / `else if (level == 1) …;` |

All other brace-less control-flow in the tree (1138 brace-less `if`, 353 `while`, 60 `for`, lisp's no-`;` `else if` chains) is **valid Zig** and requires **no change**.

## Design

### D1: Migrate the 3 invalid sites to braced form

Convert each `;`-before-`else` construct to the idiomatic braced form, which is valid in both `zig0` and `zig1` and preserves emitted C byte-for-byte (empirically verified: braces around a single-statement body are byte-identical).

Example (type_resolver.zig:980-981):
```zig
if (sz_node.kind == AstKind.add) { arr_len = lhs + rhs; }
else { arr_len = lhs - rhs; }
```

### D2: No compiler change for the migration

`zig1` already accepts the braced form. `zig0` accepts it too (valid Zig ⊆ zig0's accepted set). Byte-identity of the 4 MD5 gates is preserved by construction (verified empirically: `if (c) x = 1;` and `if (c) { x = 1; }` emit identical C).

### D3 (M8): Clearer zig1 diagnostic for the invalid form

After the migration, `zig1` should emit a **clear, actionable diagnostic** when it encounters the invalid `;`-before-`else` form (currently a generic `error[2000]: expected expression`). This makes `zig1` properly strict and self-documenting, without accepting invalid Zig.

## Constraints

- `sf/build/out_release/` is WEDGED — NEVER touch/ls/build into it; use `timeout`.
- Compiler under test: `/tmp/fx_subfolder/zig1`. Build via `bash sf/scripts/build_release.sh` (gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`); reinstall std after every rebuild (`cp sf/src/std*.zig /tmp/fx_subfolder/lib/`).
- Z98 dialect: NO `anytype`, NO `@Type`.
- Byte-identity is the hard gate unless an operator ruling re-baselines. Baselines: gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3` (re-baselined by F4), mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus (263 dirs, per-module recipe): OK=254/FAIL=5/ICE=0/CRASH=0/GG=4. 21-example matrix 21/21; test_analyzer "5 passed, 4 failed".
- `zig0` bootstrap is immutable — NOT to be changed.
- The `*%` operator gap at `util/hash.zig:18` (no lexer token) is a **separate** pre-existing blocker, out of scope.

## Success criteria

1. The 3 invalid sites are migrated to braced form.
2. Self-compile passes the previously-blocked `type_resolver.zig:981` construct (the `*%` gap at hash.zig:18 becomes the next blocker).
3. All 4 MD5 gates byte-identical.
4. Corpus 263, matrix 21/21, test_analyzer unchanged.
5. (M8) `zig1` emits a clear diagnostic for the invalid `;`-before-`else` form.
