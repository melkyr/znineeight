# Self-Hosted zig1_5 Investigation — Design

**Date:** 2026-08-25
**Status:** Approved (operator scoping rulings 2026-08-25)

## Purpose

Two-part investigation on the self-hosted compiler chain `zig0 → zig1 → zig1_5`:

1. **Fidelity gap (Part 1):** The self-compiled binary `zig1_5` links but cannot compile. It mis-tokenizes operator/punctuation characters, so any non-trivial input fails with `error[2000]` cascades. Locate the mis-emission in zig1's C output for its own lexer and pin the emission site in `sf/src` — WITHOUT fixing it.
2. **Self-containment (Part 2):** Design an `sf/src_sh/` self-hosted tree so `zig1_5` depends only on `zig1` (no `zig0` C++ bootstrap, no `__bootstrap_*` runtime artifacts), externs migrated to `@cInclude`. Logic unchanged; only dependencies change. Produce a full design ready for a later fix session — WITHOUT implementing it.

## Background / Context

Toolchain:

- `zig0` — C++ bootstrap compiler (`sf/src/bootstrap/*.cpp`, ~40 files, g++ build). Built by `sf/scripts/build_release.sh` via `g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0`.
- `zig0 → zig1`: `zig0 --header-priority-include -o /tmp/fx_subfolder/zig1.c sf/src/main.zig` then `gcc -m32 ... zig1.c sf/src/include/zig_pal.c -o /tmp/fx_subfolder/zig1`. Monolithic C emission; links only `zig_pal.c`.
- `zig1 → zig1_5`: `scripts/self_compile/build_zig1_5.sh` — `zig1 --dump-c89 --output-dir /tmp/zig1_5/gen sf/src/main.zig` (per-module `.c`), `gcc -c *.c`, link with `zig_runtime.c + zig_pal.c + c_exit.c`.

### Part 1 — confirmed observable (measured 2026-08-25)

`/tmp/zig1_5/zig1_5_clean --dump-c89 examples/z98/fibonacci/main.zig` fails at the lexer/token layer:

- `fn fib(n: u32) u32 {` → `error[2000]: invalid token in expression` at the `:` (col 10), then `unexpected token` at `u32` (col 14).
- `if (n <= 1)` → fails at `<=`.
- `n - 1` / `+` → `expected expression`.

Keywords (`fn`, `if`, `return`), identifiers, parens, braces tokenize correctly. Operator/punctuation tokens (`:`, `<=`, `-`, `+`) do not.

**Suspect construct:** `lexerNextToken` (`sf/src/lexer.zig:47-166`) is a `switch (c)` over a `u8` with char-literal case labels (`':'`, `'<'`, `'+'`, …), plus nested `if (lexerMatch(self, '='))` char-comparison lookahead, plus `TokenKind` enum ordinals (`token.zig`, `enum u16`, 92 variants). zig0 emits this correctly (reference `zig1` works); zig1's self-emission of the same source is broken.

Reference C available at runtime via rebuilding `zig0`; buggy C is the existing `/tmp/zig1_5/gen/lexer_*.c`.

### Part 2 — dependency facts

- `zig1_5` links: self-emitted `*.o` + hand-written `sf/src/include/zig_runtime.c` + `zig_pal.c` + `sf/src/c_exit.c`.
- Bootstrap artifacts live in the runtime: `__bootstrap_*_from_*` conversion helpers (`zig_runtime.c`), `__bootstrap_print`/`__bootstrap_print_int` externs (`sf/src/extern_c.zig`, preamble emission `c89_emit.zig:6578-6586`; only referenced by `main_exp.zig`/`test_a.zig`, not the compiler).
- `@cInclude` is fully supported by zig1 (lexer `c_include_builtin`, parser `parserParseCInclude`, `AstKind.c_include`, dedup `cinclude.zig`, `#include` emission `c89_emit.zig:2204-2219`) but unused in `sf/src` (dead file `extern_c_z98.zig`).
- Extern declarations in `sf/src` use `extern "c" fn` (`pal.zig:5-14`, `extern_c.zig`).

## Part 1 — Fidelity gap investigation (read-only + one repro fixture)

**Goal:** locate the mis-emission; deliver mechanism, emission site (`file:line`), minimal repro, recommended fix locus. No fix.

**Method:** (1) rebuild zig0 as reference emitter; (2) diff zig0's (correct) vs zig1's (buggy) emission of `lexerNextToken`; (3) intrusive `fprintf` on a temp copy of the buggy `lexer_*.c` to confirm which char → which wrong token kind; (4) trace the divergent emission to its `sf/src/lower.zig` / `c89_emit.zig` source site; (5) minimal repro fixture in `repro/mi_matrix/`.

## Part 2 — Self-containment design (read-only)

**Goal:** full `sf/src_sh/` design (exact file list + `@cInclude` migration map) so `zig1_5` becomes zig1-only-dependent; drop zig0 and `__bootstrap_*`. No implementation.

**Method:** (1) map zig0→zig1 dependency surface (`bootstrap/*.cpp` pipeline, monolithic emission, `zig_pal.c` link, `--header-priority-include`); (2) compute runtime-function delta (symbols zig1 emission references vs zig0 emission); (3) classify each delta symbol bootstrap vs runtime vs libc; (4) design `sf/src_sh/` + `@cInclude` headers + minimal non-bootstrap runtime.

## Acceptance Criteria

- Part 1: written finding with emission site `file:line`, byte-identical RED repro fixture, recommended fix locus. No `sf/src` edits.
- Part 2: dependency delta table + full `sf/src_sh/` file list + `@cInclude` migration map + minimal runtime design. No `sf/src` edits.
- 4 MD5 gates remain byte-identical (no GREEN program emission changes).
- Ledger + mnemoria entry per completed task.

## Non-Goals

- No `sf/src` source fixes in either part (fixes are later F-sessions consuming these findings).
- No build-script changes to `build_zig1_5.sh`.
- No migration of the compiler's own source to `sf/src_sh/` yet — design only.
