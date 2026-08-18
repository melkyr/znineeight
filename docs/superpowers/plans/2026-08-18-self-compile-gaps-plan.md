# Self-Compile Gaps (Wrap/Sat Operators + Multi-Line Source Bug + Switch-Prong) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unblock self-compile past 3 pre-existing blockers: (a) add the full wrapping/saturating operator family (`+% -% *% +| -| *| <<|` + compound-assign + prefix `-%`), (b) migrate one invalid-Zig multi-line string source bug, (c) accept value-less `return`/`break`/`continue` in switch prongs.

**Architecture:** Repros → read-only investigations → one consolidated STOP ruling → F fix placeholders → GATE → final whole-branch review. Gap 2 is a source migration (no repro/I needed — locus + fix already known and byte-identical).

**Tech Stack:** Z98 self-hosted compiler `zig1` (Z98 source, emits C89); zig0 C++98 bootstrap (immutable); gcc C89 link. No external deps.

## Global Constraints

- Z98 dialect: NO `anytype`, NO `@Type`. Use `fastedit` only (no sed/python/awk).
- `sf/build/out_release/` WEDGED — NEVER touch/ls/build into it; always use `timeout`.
- Compiler under test = `/tmp/fx_subfolder/zig1`. Build via `bash sf/scripts/build_release.sh`, gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===` (wipes /tmp/fx_subfolder; reinstall std after every rebuild: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`).
- Byte-identity is the hard gate. Baselines (single-file `--dump-c89 | md5sum`, lisp from repo root): gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus (264 dirs, per-module recipe `--dump-c89 --output-dir DIR` then gcc each .c): OK=254/FAIL=6/ICE=0/CRASH=0/GG=4 expected. 21-example matrix 21/21; test_analyzer_bin "5 passed, 4 failed".
- `zig0` bootstrap is immutable — NOT to be changed.
- Verification MUST scan the WHOLE tree for the defect class, never stop at the first error (M4 lesson).
- Gap 2 is source-only; `\\`-multiline-string support is OUT of scope (operator ruling 2026-08-18).
- NO scope creep beyond the operator family + source migration + switch-prong fix.

---

### Task R1: repro wrapping/saturating operator family (parsergap_wrap_arith_xmod)

**Files:**
- Create: `repro/mi_matrix/parsergap_wrap_arith_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec D1 (full operator family).
- Produces: committed RED evidence that the operator family is rejected.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/parsergap_wrap_arith_xmod/main.zig`:
```zig
const std = @import("std");
pub fn main() void {
    var a: u8 = 200;
    var b: u8 = 2;
    var x: u8 = 0;
    x = a +% b;
    x = a -% b;
    x = a *% b;
    x = a +| b;
    x = a -| b;
    x = a *| b;
    x = a <<| b;
    x = -%a;
    x +%= b;
    x -%= b;
    x *%= b;
    x +|= b;
    x -|= b;
    x *|= b;
    x <<|= b;
    std.io.printInt(x);
}
```
NOTES.md documents: (a) RED — `zig1 --dump-c89 main.zig` → rc=2 `error[2000]` at the FIRST operator (`+%` at `x = a +% b;`), 0-byte `.c`; (b) control GREEN — `+%`→`+` compiles, gcc rc=0, run prints value; (c) the full 15-form operator table (8 binary + prefix `-%` + 7 compound-assign); (d) note that parse stops at the first error, so the remaining 14 forms are enumerated per-form in I-ARITH via a minimal probe battery.

- [ ] **Step 2: Run RED baseline** — `cd repro/mi_matrix/parsergap_wrap_arith_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?` → record rc=2 + error[2000] + 0-byte x.c.
- [ ] **Step 3: Run control GREEN** — temporary `+`-substituted variant (in /tmp, not committed): dump rc=0, gcc rc=0, run rc=0. Record output value.
- [ ] **Step 4: Commit** — `git add repro/mi_matrix/parsergap_wrap_arith_xmod && git commit -m "repro: wrapping/saturating operator family rejected (parsergap_wrap_arith_xmod)"`. Report to `.superpowers/sdd/task-R1-report.md`.

---

### Task R3: repro switch-prong value-less return (parsergap_switch_comma_xmod)

**Files:**
- Create: `repro/mi_matrix/parsergap_switch_comma_xmod/{main.zig, NOTES.md}`

**Interfaces:**
- Consumes: spec D3 (switch-prong value-less return).
- Produces: committed RED evidence.

- [ ] **Step 1: Create the fixture**

`repro/mi_matrix/parsergap_switch_comma_xmod/main.zig` (mirrors `lexerSkipWSC`'s shape):
```zig
const std = @import("std");
pub fn main() void {
    var c: u8 = 0;
    switch (c) {
        ' ' => { c = 1; },
        else => return,
    }
    std.io.printInt(c);
}
```
NOTES.md documents: (a) RED — rc=2 `error[2000]` (expected expression / unexpected token at `return`/`,`), 0-byte `.c`; (b) control GREEN — `else => {}` → rc=0, run prints `0`; (c) post-fix expectation (GREEN).

- [ ] **Step 2: Run RED baseline** — `cd repro/mi_matrix/parsergap_switch_comma_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?` → record rc=2 + error[2000] + 0-byte x.c.
- [ ] **Step 3: Run control GREEN** — temporary braced variant (in /tmp, not committed): rc=0, run prints `0`.
- [ ] **Step 4: Commit** — `git add repro/mi_matrix/parsergap_switch_comma_xmod && git commit -m "repro: value-less return in switch prong rejected (parsergap_switch_comma_xmod)"`. Report to `.superpowers/sdd/task-R3-report.md`.

---

### Task I-ARITH: investigate full wrapping/saturating operator family (read-only)

**Files:**
- None (report only): `.superpowers/sdd/task-I-ARITH-report.md`

**Interfaces:**
- Consumes: spec D1; R1 fixture.
- Produces: exact fix locus + blast radius for the full family, to fill F1 at STOP.

- [ ] **Step 1: Enumerate all 15 forms via a minimal probe battery** (in /tmp, never committed): one tiny program per form — `+% -% *% +| -| *| <<|` (binary), `-%a` (prefix), `+%= -%= *%= +|= -|= *|= <<|=` (compound-assign). For each, record the exact error[2000]/error class → confirm all 15 are RED and none accidentally parse as a different operator.
- [ ] **Step 2: Pin the fix locus per layer**
  - Lexer (`lexer.zig:73` `+`, `:77` `-`, `:81` `*`, `:111` `<<`): confirm each needs a `%`/`|` lookahead → new `TokenKind` entries. Verify `-` lookahead can't collide with `-=`/`->`.
  - Parser infix table (`parser.zig:236-281`): confirm where the 7 binary new-kinds register + precedence. Determine prefix `-%` handling + the prefix-vs-binary `-%` disambiguation rule (context: binary-operator position vs operand position).
  - AST (`ast.zig`), lowerer (`lower.zig`), LIR (`lir.zig`), emitter (`c89_emit.zig`): map each operator to existing arithmetic LIR/emit patterns.
- [ ] **Step 3: Emitter strategy** — confirm wrapping ops can emit plain C `+ - *` (unsigned wraps by definition; `u8`→`unsigned char` promotes to `int` — verify width/truncation semantics for the emitted types), and design saturating emit (`+|`/`-|`/`*|`/`<<|` → explicit min/max clamp, and `<<|` clamped shift). State the exact C emitted for each op on `u8`/`u32`.
- [ ] **Step 4: Byte-identity impact** — grep the 4 gate sources + corpus: any wrapping/saturating operator present? (Expected: none except `hash.zig:18` `*%`.) State whether adding the ops changes any existing emitted C (it should not — new tokens only fire on previously-erroring input).
- [ ] **Step 5: Report** — write `.superpowers/sdd/task-I-ARITH-report.md` with the per-form battery table, per-layer locus, emitter C sketches, byte-identity conclusion, and recommended F1 split (e.g. wrap+binary first vs all-at-once).

---

### Task I-SWITCH: investigate switch-prong value-less return (read-only)

**Files:**
- None (report only): `.superpowers/sdd/task-I-SWITCH-report.md`

**Interfaces:**
- Consumes: spec D3; R3 fixture.
- Produces: exact mechanism + minimal parser fix, to fill F3 at STOP.

- [ ] **Step 1: Confirm the mechanism** — `parserParseReturnExpr` (`parser.zig:1659-1664`) skips the value only when `parserPeek == semicolon`; so `return,` tries `parserParseExprPrec` on the comma → `error[2000]`. Verify `parserParseBreakExpr` (`:1673`) and `parserParseContinueExpr` (`:1690`) share the same `;`-only check. Check whether switch-prong trailing comma is already accepted at `:831-833` (it is) so the failure is the value-less `return` parse, not the comma.
- [ ] **Step 2: Design the minimal fix** — the terminator set for "no value" must include `,`/`}`/`;`/`eof` (mirror the fn-call/switch-prong loops). Verify byte-identity for all currently-valid inputs (they already parse; the change only admits previously-rejected prong bodies). State exact new condition.
- [ ] **Step 3: Blast radius** — grep gates + corpus for value-less `return`/`break`/`continue` in switch prongs. (Expected: only `lexer.zig:236`; confirm none in the 4 gate sources or corpus.)
- [ ] **Step 4: Report** — write `.superpowers/sdd/task-I-SWITCH-report.md`.

---

### Task STOP: consolidated ruling

- [ ] Present I-ARITH + I-SWITCH findings to the operator (batched).
- [ ] Operator rules: (a) F1 wrap-op implementation split (full-family all-at-once vs wrap-first-then-sat), (b) saturating-emit strategy (if any spec question), (c) prefix `-%` handling, (d) F3 fix shape.
- [ ] Record rulings in a plan AMENDMENT section.


### AMENDMENT (2026-08-18, operator rulings after consolidated STOP)

- **R1 plan-note (d) correction:** "parse stops at first error" is factually wrong — zig1 flags ALL 15 forms in a single run and each fails isolated (R1 NOTES.md documents observed reality). The I-ARITH probe battery confirms per-form RED; no plan-behavior change.
- **F1 split (operator):** wrapping family FIRST (`+% -% *%` + compound `+%= -%= *%=` + prefix `-%` = 7 forms) as commit 1, then saturating family (`+| -| *| <<|` + compound `+|= -|= *|= <<|=` = 8 forms) as commit 2. Both within Task F1.
- **Signed operands (operator + Zig-spec verification):** Zig langref (master) confirms all wrap/sat operators apply to Integers — both signed AND unsigned. Signed wrap = "Twos-complement wrapping behavior" (langref example: `-%@as(i8, -128) == -128`; wrap demo uses i32). Signed saturating clamps to signed min/max. Therefore F1 MUST support signed operands; the emission layer (c89_emit.zig) is where signed semantics are realized. Emitter strategy: wrapping ops on unsigned emit plain C `+ - *`; wrapping on signed emits via unsigned-width cast arithmetic + cast back (two's-complement defined on all zig1 targets); saturating emits explicit min/max clamp ternaries; `<<|` emits clamped shift. Signed emission must be correct even though no gate/corpus currently exercises it (only `hash.zig:18` `*%` on u32).
- **F1 build hazard (I-ARITH):** `dump_ast.zig:12` and `dump_tokens.zig:43` are exhaustive switches without `else` — new TokenKind/AstKind entries require added cases or else-branches or the F1 build fails. `main.zig:383-384` comptime-fold gate hardcodes AstKind values 33..42/62/64 — new kinds won't fold (inert for F1 targets; extend for full-family correctness is optional).
- **F3 scope (operator):** RETURN-ONLY. I-SWITCH proved `break`/`continue` have NO `;`-check and ALREADY parse GREEN in switch prongs — only value-less `return` is broken. Plan Task F3's "return/break/continue" wording is amended to return-only. Fix: `parserParseReturnExpr` (parser.zig:1662) skips the value when the next token is in `{semicolon, comma, rbrace, eof}` (currently `;`-only). Byte-identity holds by construction; downstream `resolveReturnStmt`/lower already guard `child_0==0`.

---

### Task F2: source migration multi-line string (c89_emit.zig:1881) — no repro/I

**Files:**
- Modify: `sf/src/c89_emit.zig:1881-1882`

**Interfaces:**
- Consumes: spec D2.
- Produces: `c89_emit.zig:1881` compiles; self-compile passes the construct.

- [ ] **Step 1: Reproduce the blocker (baseline)**

`timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig 2>/tmp/sc.err >/dev/null; grep -a "error[" /tmp/sc.err | grep -av "error[9999]"` → the c89_emit.zig:1881 error[0]/unterminated-string construct present in filtered output.

- [ ] **Step 2: Migrate** (re-read the region before editing; use fastedit)

`c89_emit.zig:1881-1882`:
```zig
var fwdnl2: []const u8 = "\n"; pal.markerWrite(fwdnl2);
```
(String value `\n` unchanged → emitted C identical.)

- [ ] **Step 3: Build + verify**

`bash sf/scripts/build_release.sh` → gate; reinstall std. Self-compile filtered stderr no longer shows `c89_emit.zig:1881`. Tree-wide scan confirms no other literal-newline-in-`"..."` site remains in `sf/src` + `examples/z98`.

- [ ] **Step 4: Byte-identity gates** — 4 MD5s byte-identical (baselines above). MEASURE, don't assume.
- [ ] **Step 5: Commit** — `git add sf/src/c89_emit.zig && git commit -m "fix: migrate multi-line string literal to escaped \\n form (self-compile gaps F2)"`. Report to `.superpowers/sdd/task-F2-report.md`.

---

### Task F1 / F3 (placeholders — filled by STOP ruling)

- **F1**: implement the full wrapping/saturating operator family per I-ARITH + ruling. RED→GREEN on R1 battery + per-form probes; 4 MD5s byte-identical; corpus unchanged; self-compile passes `hash.zig:18`; tree-wide scan.
- **F3**: switch-prong value-less `return`/`break`/`continue` per I-SWITCH + ruling. RED→GREEN on R3; 4 MD5s byte-identical; corpus unchanged; self-compile passes `lexer.zig:236`; tree-wide scan.

---

### Task GATE: final sweep + reconciliation

- [ ] Corpus 266 dirs (264 + R1 + R3): expect OK=254/FAIL=6/GG=4 unchanged (repros stay FAIL-by-design or flip OK per ruling). MEASURE.
- [ ] 4 MD5s byte-identical; matrix 21/21; test_analyzer "5 passed, 4 failed".
- [ ] Self-compile: all 3 constructs pass; record next blocker (if any) — do NOT fix.
- [ ] Docs: EXPECTED_FAIL version bump + closeout record; QUICK_REF baseline line. Corpus heading update if dir count changes.
- [ ] Commit docs-only. Report to `.superpowers/sdd/task-GATE-report.md`.

---

### Task M-FINAL: final whole-branch review

- [ ] review-package base `908d502e`..HEAD → dispatch final code reviewer (requesting-code-review template) with the package + ledger of Minor findings.
- [ ] Fix wave if any Important/Critical; re-review.
- [ ] Operator accepts → READY TO MERGE.
