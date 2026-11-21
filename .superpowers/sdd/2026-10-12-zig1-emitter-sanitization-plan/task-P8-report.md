# Task P8 report — Builtin arity/descriptor table (D6 root-cause)

Branch `zig1_improvements`, BASE `21f9da99` (confirmed `git rev-parse HEAD` = `21f9da995ad87a2ed9f092c4e3265a3eab8538b6`). Requirements: `task-P8-brief.md` (binding, incl. controller pre-check facts). Shape: Investigate (written before source edits — this section) → Implement (one commit (a)) → full 8-item runtime battery + arity reproducers → this report completed (commit (b)).

**Status: STOP-present (class mover — operator judgment required on one builtin).** The central table lands as commit (a) and every gate is green EXCEPT the corpus-class byte-identity gate and the stdlib gate, both broken by ONE root cause: `@intCast`'s one-argument form (program + builtin presented below). `@ptrFromInt`/`@ptrCast` message texts byte-identical (old→new diffs empty), the introspection rejects byte-identical, correct-arity emission pins 0/8, markers unchanged. Per the brief's categorical rule ("any class mover = STOP-present the program and the builtin — the operator judges whether it is a legitimate D6-class reject or a false positive … Do not silently accept movers") the mover is presented here, not accepted silently and not unilateral-fixed.

## Investigate (written before source edits — 2026-10-15)

### 0. Scope resolution (from the brief, verbatim targets kept)

- Central per-builtin expected-arity (and kind) table in `sf/src/semantic_analyzer.zig`, consulted **before** the dispatch ladder (`semantic_analyzer.zig:4788+`, `node.kind == AstKind.builtin_call` arm); every `builtin_call` goes through it.
- Arity-mismatch shape = the established reject shape of the `@ptrFromInt` arm (`semantic_analyzer.zig:4797-4803`): `ERR_3000_TYPE_MISMATCH` via its enum expression, `TYPE_UNDEFINED`, continue resolving what exists for further diagnostics (the arm resolves arg0-if-present — that is the established shape, adopted uniformly); message pattern `@<name> requires exactly N argument(s): <signature>` (numeric N + `(s)`, the house count style — cf. the fn-call `expected N argument(s), found M` and the introspection wording), with the two existing message texts matched EXACTLY.
- Touch set: `sf/src/semantic_analyzer.zig` + tech docs `05_semantic_analysis.md` + `INDEX.md` only. No fixtures, no `progress.md`, no lowerer/emitter.

### 1. Census — every builtin the ladder/support-check knows, expected arity + current enforcement state (re-derived at HEAD `21f9da99`; table is the report's requirement #1, written before source edits)

**Universe.** The support-check (`semanticAnalyzerBuiltinFlags`, `semantic_analyzer.zig:379-422`) knows exactly **37** names (32 interned name-id compares + 5 string compares `@enumToInt`/`@cVaStart`/`@cVaArg`/`@cVaEnd`/`@panic`; the interner dedups (`string_interner.zig:137-141` `mem_eql` → same id), so id and string compares are equivalent for the same text — the split is Task 6c historical fidelity). `@import`/`@cInclude` are NOT `builtin_call` (the parser builds `import_expr`/`c_include` nodes, `parser.zig:786/:815`) — out of the universe. **Kind** (P8's "and kind") = the existing kind bits plus the introspection class: **type-value cast** (8) / **introspection** (5) / **plain** (24); supported = table membership (bit 1).

**Expected arity source** = Language Spec §4 (`docs/reference/Language_Spec_Z98.md:303-346`) as implemented by the ladder; `@cVaStart`/`@cVaEnd` carry no spec signature — the implemented surface (`@cVaStart(&vl)` / `@cVaEnd(&vl)`, ladder `ec_n >= 1` generic arms + lowerer `lower.zig:6200-6240` + `repro/mi_matrix/fn_varargs_body`) fixes their arity at **1**; `@cVaArg(&vl, T)` = **2** (ladder `:4910-4917`).

| # | builtin | expected arity | kind | current enforcement state | current wrong-arity behavior (observed/derived) |
|---|---------|----------------|------|---------------------------|------------------------------------------------|
| 1 | `@ptrCast(T, expr)` | 2 | type-value cast | **CHECKED** — arm `ec_n != 2` (`:4905-4911`), `ERR_3049`, msg `@ptrCast requires exactly two arguments: @ptrCast(T, expr)`, resolves arg0, `TYPE_UNDEFINED` | reject `error[3049]` (exact text pinned) |
| 2 | `@volatileCast(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (≥2 ignores extras; 1 → generic arm result=arg0; 0 → `TYPE_VOID`) |
| 3 | `@intToPtr(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (same class) |
| 4 | `@intCast(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (same class) |
| 5 | `@floatCast(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (same class) |
| 6 | `@intToFloat(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (same class) |
| 7 | `@intToEnum(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (same class) |
| 8 | `@as(T, expr)` | 2 | type-value cast | unchecked | wrong-accept (same class) |
| 9 | `@ptrToInt(expr)` | 1 | plain | unchecked (`:4855-4857` resolves ≤1) | wrong-accept (0 → `TYPE_USIZE` w/o arg; ≥2 ignores extras) |
| 10 | `@intFromPtr(expr)` | 1 | plain | unchecked (`:4855-4857`) | wrong-accept (same) |
| 11 | `@ptrFromInt(expr)` | 1 | plain | **CHECKED** — arm `ec_n != 1` (`:4797-4803`), `ERR_3000_TYPE_MISMATCH` enum expr, msg `@ptrFromInt requires exactly one argument: @ptrFromInt(expr)`, resolves arg0, `TYPE_UNDEFINED` | reject `error[19]` (exact text pinned; see §2.4 on the `error[19]` rendering) |
| 12 | `@fieldParentPtr(T, "field", expr)` | 3 | plain | unchecked (`:4822` `if (ec_n >= 3)`) | wrong-accept (≠3 → silent `TYPE_VOID` / extras ignored) |
| 13 | `@bitCast(T, expr)` | 2 | plain | unchecked (`:4835` `if (ec_n >= 2)`) | wrong-accept (≠2 → `TYPE_VOID` / extras ignored) |
| 14 | `@sizeOf(T)` | 1 | introspection | **CHECKED** — `semanticAnalyzerCheckIntrospectionBuiltin` (`:1457-1475`), `ERR_3074`, dynamic msg `expected 1 argument(s), found M`, `MarkNodeOnce`, result stays `TYPE_INT_LIT` | reject `error[3074]` (house wording; out-of-touch-set docs pin it — §2.3) |
| 15 | `@alignOf(T)` | 1 | introspection | **CHECKED** (same) | reject `error[3074]` |
| 16 | `@offsetOf(T, "field")` | 2 | introspection | **CHECKED** (same) | reject `error[3074]` |
| 17 | `@bitSizeOf(T)` | 1 | introspection | **CHECKED** (same) | reject `error[3074]` |
| 18 | `@bitOffsetOf(T, "field")` | 2 | introspection | **CHECKED** (same) | reject `error[3074]` |
| 19 | `@putChar(c)` | 1 | plain | unchecked (`:4864` resolves ≤1) | wrong-accept |
| 20 | `@stdoutWrite(ptr, len)` | 2 | plain | unchecked (`:4867` resolves ≤2) | wrong-accept |
| 21 | `@stderrWrite(ptr, len)` | 2 | plain | unchecked (`:4867`) | wrong-accept |
| 22 | `@getChar()` | 0 | plain | unchecked (`:4861` resolves nothing) | wrong-accept (extra args ignored) |
| 23 | `@exit(code)` | 1 | plain | unchecked (`:4858`) | wrong-accept |
| 24 | `@sleepMs(ms)` | 1 | plain | unchecked (`:4864`) | wrong-accept |
| 25 | `@isWindows()` | 0 | plain | unchecked (`:4870`) | wrong-accept (extra args ignored) |
| 26 | `@consoleClear()` | 0 | plain | unchecked (`:4872`) | wrong-accept (extra args ignored) |
| 27 | `@consoleGotoxy(x, y)` | 2 | plain | unchecked (`:4874`) | wrong-accept |
| 28 | `@consoleSetColor(fg, bg)` | 2 | plain | unchecked (`:4874`) | wrong-accept |
| 29 | `@panic(msg)` | 1 | plain | unchecked (`:4862`) | wrong-accept |
| 30 | `@cVaStart(&vl)` | 1 | plain | unchecked (generic arms `:4933/:4945`) | wrong-accept |
| 31 | `@cVaArg(&vl, T)` | 2 | plain | unchecked (`:4910` `if (ec_n >= 2)`) | wrong-accept (≠2 → `TYPE_VOID` / extras ignored) |
| 32 | `@cVaEnd(&vl)` | 1 | plain | unchecked (generic arms) | wrong-accept |
| 33 | `@asyncFrameSize(fn)` | 1 | plain | unchecked (`:4877` `if (ec_n >= 1)`) | wrong-accept |
| 34 | `@asyncInit(ctx, buf, fn, args)` | 4 | plain | unchecked (`:4902` resolves ≤4) | wrong-accept |
| 35 | `@asyncResume(frame, arg)` | 2 | plain | unchecked (`:4895`) | wrong-accept |
| 36 | `@asyncSuspend(data)` | 1 | plain | unchecked (`:4899`) | wrong-accept |
| 37 | `@enumToInt(expr)` | 1 | plain | unchecked (`:4938` `ec_n >= 1` arm) | wrong-accept |

**Tally: 7 checked / 30 unchecked** (the brief's "~20 unchecked" — honest census is 30; the two `ec_n != N` arms the controller facts name are rows 1 and 11; rows 14-18 carry an additional check the controller facts did not name — §2.3).

### 2. Investigation findings (decisions the edit plan executes)

**2.1 Central table supersedes `semanticAnalyzerBuiltinFlags` (the same authority).** Post-Task-6c the name set is spelled ONCE (`:379-422`, the flags chain) but the ARITY truth is spelled a third time, ad-hoc, inside the ladder arms (`ResolveBuiltinArgs(..., n)` counts, the two `ec_n != N` checks, the `ec_n >= k` soft guards, and the introspection helper's `ib_is_offset`→count derivation). P8's table is the single descriptor: per name — kind bits (type-value cast / supported, the existing bit contract so `semanticAnalyzerIsTypeValueCast`/`semanticAnalyzerIsBuiltinSupported` read it unchanged) + expected arity + arity-diagnostic class + the mismatch code + the mismatch message. One lookup chain (id compares first, then the five string compares — Task 6c membership/order fidelity preserved exactly). No second spelling anywhere.

**2.2 The two existing checked arms keep their exact diagnostics** (key gate: message texts byte-identical): rows 1 and 11 carry their full message text and their exact code expression (`@intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3049_PTRCAST_REQUIRES_TWO_ARGS))` / `@intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3000_TYPE_MISMATCH))` — reuse of the SAME expressions is what keeps the rendering byte-identical), and the mismatch resolve shape stays the established arm shape (resolve arg0-if-present, then `TYPE_UNDEFINED`). The ladder's two mismatch arms are deleted (their checks are subsumed — single decision source; the correct-arity arms remain verbatim).

**2.3 The introspection five (rows 14-18) are CHECKED — via a shape the brief's controller facts did not name — and keep their exact diagnostics.** `semanticAnalyzerCheckIntrospectionBuiltin` (`:1463-1475`) enforces arity with `ERR_3074_COMPTIME_BUILTIN_UNRESOLVED` + the **dynamic** house message `expected N argument(s), found M` + `diagnosticCollectorMarkNodeOnce` dedup + the arm's unconditional `TYPE_INT_LIT` result — a different reject shape from the established one. This is pinned **outside the touch set**: `repro/vol2_defects/D09_bare_union_offsetof/NOTES.md:92` ("missing/extra arguments and `@sizeOf` extra args reject 3074"), `repro/mi_matrix/EXPECTED_FAIL.md:2386` ("arity rejects `error[3074]`"), `repro/union_offset_reject.z98:4` (fixture comment "3074 x2 (missing argument, unresolved type)"). Replacing their diagnostics with the generic shape would falsify those committed docs, which the touch set forbids editing → the in-bounds execution is "Existing checked arms keep their exact diagnostics" for all 7 checked rows. P8 treatment: the rows carry arity-kind `introspection`; the arity **decision** (the expected count — today derived from `ib_is_offset`) moves to the central table; the established introspection reject (the exact emission, moved verbatim into the pre-ladder checker for that kind) keeps its exact code/message/dedup/result (`TYPE_INT_LIT`). The helper's `ib_want` derivation + `ec_n != ib_want` block are subsumed (single decision source); `ib_is_offset` stays (it drives the field-name checks, not arity).

**2.4 `error[19]` rendering quirk (pre-existing, preserved).** `ErrorCode.ERR_3000_TYPE_MISMATCH` has no explicit tag (`diagnostics.zig:30` — the enum's auto ordinal is 19), so the established `@enumToInt(ERR_3000_TYPE_MISMATCH)` code renders as `error[19]` (observed baseline: `r1 … error[19]: @ptrFromInt requires exactly one argument: @ptrFromInt(expr)`), while `ERR_3049_… = 3049` renders `error[3049]`. Byte-identity requires reusing the same enum expressions in the table rows; the new generic rows therefore also render `error[19]` (the brief's "established reject shape (`ERR_3000_TYPE_MISMATCH`, …)" — same enum member, same rendering). Not a P8 fix (no unrelated fixes; the enum-tag quirk stays for the ledger).

**2.5 Mismatch resolve shape = the established arm shape (arg0-if-present).** Both existing arms resolve exactly arg0-if-present before `TYPE_UNDEFINED` (`:4801`, `:4909`); adopted uniformly so rows 1/11 are byte-identical **by construction** (not just by message text). "Continue resolving what exists for further diagnostics" = the established shape (resolving the present first argument surfaces its diagnostics, e.g. an undeclared identifier in arg0). (If the operator wants ALL present args resolved on mismatch — richer diagnostics on wrong-arity junk — that is a one-line widening; rows 1/11 then need a regression diff, so it was not taken unilaterally.)

**2.6 Baseline reproducer census (pre-edit, compiler `/tmp/p8_base/zig1_5_clean` = two-hop of HEAD, fixed point `3c0376fc62002297029f6ecc278a259c`):** the D6-class wrong-accept is real in 5 sampled unchecked builtins (`@exit(0, 1)`, `@putChar('a','b')`, `@isWindows(true)`, `@intCast(i32)`, `@getChar('x')` — all dump rc=0, .c emitted); the 2 checked rows reject with the exact pinned texts; the introspection sample `@sizeOf(u32, 9)` rejects `error[3074]: expected 1 argument(s), found 2`; correct-arity controls compile rc=0. Full command/output table in the Arity reproducers section (post-edit, with old→new diffs for rows 1/11/14-18).

### 3. Edit plan (precise; executed bottom-to-top per file, `edit`/`fastedit` only — AGENTS.md X.7)

All in `sf/src/semantic_analyzer.zig` (house style: two-arg `@intCast`, `var x: T = "literal"` string vars, no comments unless structural):

1. **Central descriptor (supersedes `semanticAnalyzerBuiltinFlags`, `:355-422`):** new `BuiltinDesc` struct (`flags: u8` bit0 type-value cast / bit1 supported, `arity: u8`, `arity_kind: u8` 0=generic 1=introspection, `code: u16`, `msg: []const u8`) + `semanticAnalyzerBuiltinDesc(self, name_id) BuiltinDesc` — the ONE name→descriptor chain (id compares first, then the five string compares; membership/order exactly Task 6c's). `semanticAnalyzerIsTypeValueCast`/`semanticAnalyzerIsBuiltinSupported` become thin `.flags` reads (their exact sets preserved). Rows 1/11 carry the exact message texts + exact code expressions (§2.2); generic rows carry `ERR_3000_TYPE_MISMATCH`'s enum expression + the full template message (e.g. `@exit requires exactly 1 argument(s): @exit(code)` — signatures from Spec §4; `@cVaStart(&vl)`/`@cVaArg(&vl, T)`/`@cVaEnd(&vl)` = the implemented surface); introspection rows carry their arity and the `introspection` kind (no static message — the house dynamic wording).
2. **`semanticAnalyzerCheckBuiltinArity(self, node_idx, name_id, ec_n) u8`** — consulted BEFORE the dispatch ladder for every `builtin_call` (after the existing unsupported gate). Returns 0 = arity ok; 1 = rejected (established shape: row code + row msg via `diagnosticCollectorAdd`, resolve arg0-if-present, caller sets `TYPE_UNDEFINED`); 2 = rejected introspection shape (`semanticAnalyzerRejectIntrospectionArity` — the helper's arity emission moved verbatim (itoa + `expected N argument(s), found M` + `semanticAnalyzerRejectIntrospection`/`MarkNodeOnce`), caller sets `TYPE_INT_LIT` — the arm's unconditional result preserved).
3. **`semanticAnalyzerCheckIntrospectionBuiltin` (`:1457+`):** delete the `ib_want` derivation + the `ec_n != ib_want` arity block (subsumed — it is only reachable at correct arity now); `ib_is_offset` + all field/type checks unchanged.
4. **Dispatch ladder (`:4788+`):** after `ec_n`, the arity check; on reject set the per-kind result and skip the ladder (the established arms' early-return behavior). Delete the two mismatch arms (`:4797-4803`, `:4905-4911`) — no duplicated arity logic; the correct-arity arms (`@ptrFromInt` inference `:4804-4821`, `@ptrCast` type-value-cast branch) remain verbatim.
5. **Tech docs** `[updated: 2026-10-12 — P8 …]` stamps: `05_semantic_analysis.md` (§`semanticAnalyzerIsTypeValueCast`/§`IsBuiltinSupported`/§`CheckIntrospectionBuiltin` + §Builtin dispatch gain the central-table/arity paragraphs; the introspection arity bullet notes the decision source moved to the table with the emission shape preserved), `INDEX.md` (`semanticAnalyzerBuiltinDesc`/`semanticAnalyzerCheckBuiltinArity` rows + updated rows).

### 4. Invariants — preservation map

| invariant | how preserved |
|---|---|
| correct-arity resolution (all ladder arms' result types, arg resolution, defer/async diagnostics) | untouched arms; arity check returns 0 on match → ladder verbatim |
| `@ptrFromInt`/`@ptrCast` wrong-arity diagnostics (code, message text, span, arg0-only resolve, `TYPE_UNDEFINED`) | rows carry exact texts + exact code expressions; shape = established arm shape (§2.2/§2.5); proven by old→new reproducer diffs |
| introspection wrong-arity diagnostics (3074, dynamic house wording, `MarkNodeOnce` dedup, `TYPE_INT_LIT`) | emission moved verbatim to the checker's introspection kind (§2.3); proven by old→new reproducer diff |
| unsupported-builtin path (`unsupported builtin function`) | untouched; arity check only runs for supported names (table members) |
| `-fsafe`/`-ffast` | sema-only change, mode-independent (D6 doc confirms no mode divergence) |
| emission on correct programs | no lowerer/emitter touch (P8 is front-end validation; "Sema is the decision side") |

No corner of the plan text required an improvisation at edit time; no mechanism outside `semantic_analyzer.zig` + the two tech docs is touched. The battery then produced ONE class mover (§Runtime battery item 2) → STOP-present (below).

## Implement (commit (a) `refactor(semantic_analyzer): P8 — central builtin arity/descriptor table consulted before the dispatch ladder (D6 root-cause)`)

The §3 edit plan executed as written (bottom-to-top per file, `edit` only):

- **`BuiltinDesc` + `semanticAnalyzerBuiltinDesc`** (`semantic_analyzer.zig:355+`): the central per-builtin table — kind bits (bit0 type-value cast / bit1 supported, the pre-P8 bit contract) + expected arity + arity-reject class (0 = established reject shape / 1 = established introspection reject shape) + mismatch `code` + mismatch `msg`. Supersedes `semanticAnalyzerBuiltinFlags` (deleted); `semanticAnalyzerIsTypeValueCast`/`semanticAnalyzerIsBuiltinSupported` are thin `.flags` reads (sets unchanged). 37 rows, id compares first then the five string compares (Task 6c membership/order preserved exactly). Rows `@ptrFromInt`/`@ptrCast` carry the exact pre-P8 message texts and their exact enum code expressions; introspection rows carry `arity_kind=1`; all other rows carry the template message (e.g. `@exit requires exactly 1 argument(s): @exit(code)`) + `ERR_3000_TYPE_MISMATCH`'s enum expression (which renders `error[19]` — §2.4 quirk, preserved).
- **`semanticAnalyzerCheckBuiltinArity`**: consulted before the dispatch ladder for every `builtin_call` (after the unsupported gate). 0 = ok → the ladder runs verbatim; 1 = established reject (row code+msg via `diagnosticCollectorAdd`, arg0-if-present resolved, `TYPE_UNDEFINED` at the call — rows 1/11 byte-identical by construction); 2 = introspection reject (`semanticAnalyzerRejectIntrospectionArity`, `TYPE_INT_LIT` at the call).
- **`semanticAnalyzerRejectIntrospectionArity`**: the `@sizeOf`-family arity emission moved VERBATIM out of `semanticAnalyzerCheckIntrospectionBuiltin` (itoa + `expected N argument(s), found M` + `ERR_3074` + `MarkNodeOnce`).
- **`semanticAnalyzerCheckIntrospectionBuiltin`**: `ib_want` derivation + `ec_n != ib_want` block deleted (subsumed); `ib_is_offset` + all type/field checks unchanged; signature drops `ec_n`.
- **Dispatch ladder**: `ec_n` → arity-check prelude (reject arms set the per-class result and skip the ladder); the two ad-hoc mismatch arms (`@ptrFromInt` `ec_n != 1`, `@ptrCast` `ec_n != 2`) deleted; all correct-arity arms verbatim (incl. `@ptrFromInt`'s expected-type inference and `@ptrCast`'s volatile-drop check).
- **Tech docs** `[updated: 2026-10-12 — P8 …]`: `05_semantic_analysis.md` (§IsTypeValueCast, §IsBuiltinSupported/NameEq, §CheckIntrospectionBuiltin arity bullet, §Builtin dispatch) + `INDEX.md` (H1 stamp + `semanticAnalyzerBuiltinDesc`/`semanticAnalyzerCheckBuiltinArity`/`semanticAnalyzerRejectIntrospectionArity` rows + predicate rows).

## Runtime battery (8 items; compiler `/tmp/p8_build/zig1_5_clean`, two-hop build of the committed tree)

### 1. Seed two-hop

`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p8_build` → `[seed] hop1 binary md5: 1501f571c5cd2fcaf2f291adacfc8965` / `[seed] hop2 binary md5: 1501f571c5cd2fcaf2f291adacfc8965` / `[seed] two-hop closure OK: hop1 == hop2 == 1501f571c5cd2fcaf2f291adacfc8965`. **hop1==hop2**; fixed point old `3c0376fc62002297029f6ecc278a259c` → **new `1501f571c5cd2fcaf2f291adacfc8965`** (moved as expected — `sf/src` moved; recorded; seed NOT rotated — Task C). (Baseline control: `build_from_seed.sh … /tmp/p8_base` at HEAD reproduces `3c0376fc62002297029f6ecc278a259c` = the brief's old fixed point.)

### 2. Corpus classify — **1 CLASS MOVER (STOP-present)**

`bash scripts/corpus/classify /tmp/p8_build/zig1_5_clean /tmp/p8_run/corpus.txt` → `wrote /tmp/p8_run/corpus.txt: 1124 dirs`; `md5sum` = `3e675229dba2a27234e22cccf97771f8` — **NOT** the frozen `518eca1a9b5d3e1cc5a48abce214abd8`. Baseline control (`classify /tmp/p8_base/zig1_5_clean /tmp/p8_run/corpus_base.txt`) reproduces `518eca1a9b5d3e1cc5a48abce214abd8` exactly (HEAD tree = frozen anchor). Tally: **1124 = 949 OK / 58 GREEN / 117 FAIL / 0 ICE / 0 CRASH** (anchor: 950/58/116/0/0). `diff` base→new is exactly one line:

```
806c806
< repro/mi_matrix/stdlib_intcast_loop_capture_xmod OK
---
> repro/mi_matrix/stdlib_intcast_loop_capture_xmod FAIL
```

Program + builtin + analysis: see **STOP-present** below. No other program in the 1124-dir universe moves (incl. all 26 example dirs — they classify unchanged and §5 runs frozen).

### 3. Goldens 5/5

dump+gcc (recipe task-0 §1.3, `gcc -m32 -std=c89 … zig_runtime.c zig_pal.c`) all rc=0 (0 `error:`). gol `timeout 120 ./gol` = `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `printf '(+ 1 2)\n' | timeout 60 ./lisp` = `b3d9f8974da24ddbf9d389f3d7d97322`; json (CWD `examples/z98/json_parser`) = `8bda3d5a1ec07d14a301bc343df32bf8`; mud session (`examples/z98/mud_server/demo/session.sh`) rc=0, server `66c8f0abb926cca7baf9a0d1692ab318`, client `93147d0f0bbd983a9d844fea8b7a6fa7`; both mud files `cmp`-IDENTICAL to `demo/canonical_expected.txt` / `demo/canonical_client_expected.txt` (`cmp server: IDENTICAL`, `cmp client: IDENTICAL`). **5/5 = frozen.**

### 4. mi_matrix 25 + oob

`bash scripts/stdlib/run_fixtures.sh /tmp/p8_build/zig1_5_clean <the 25 §1.8 anchor dirs (task-0 enumeration verbatim)>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`**. Trap `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc=0, `sh build_target.sh linux` build rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt`), `expected.rc=133`. **MATCH.**

### 5. examples 26/26 build + 26/26 run

Build (`-ffast -o`, `build_target.sh linux`): 26/26 dump=0 / `.c` counts identical to task-0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run (CWD = example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* fed `q\n`): 26/26 rc + stdout md5_16 IDENTICAL to §1.4 — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`. **26/26 frozen.**

### 6. stdlib — **284/1 (same root cause as item 2)**

`bash scripts/stdlib/verify_stdlib.sh /tmp/p8_build/zig1_5_clean` → `run_fixtures: 284 PASS / 1 FAIL over 285 dirs` / `failed: repro/mi_matrix/stdlib_intcast_loop_capture_xmod` / `STDLIB GATE FAILED`. The one FAIL is the SAME program as the corpus mover (the 1-arg `@intCast` form) — one root cause, two gate breaks.

### 7. The 8 `--dump-c89` pins (old → new; sequential from repo root)

| entry | mode | old (P9 record = HEAD) | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `bbc02913a10af9b0b5ed0f292f4e3407` | `bbc02913a10af9b0b5ed0f292f4e3407` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `93c5e3fdc5b80b2f3db020d995abbe3f` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `6da05d070acd414674b1b1ec947baa5c` | `6da05d070acd414674b1b1ec947baa5c` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `af3823fae0b29fa4d4ca58932538d631` | `af3823fae0b29fa4d4ca58932538d631` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — byte-identical** (also the `-fsafe`/`-ffast` identical gate on correct programs: each pair's old==new in both modes).

### 8. Markers telemetry

`/tmp/p8_build/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,437 lines / 38,384 B** = record **3,437 / 38,384** (unchanged; telemetry).

## Arity reproducers (tmp programs, report evidence only — NOT committed fixtures)

All in `/tmp/p8_repro/`; command `zig1_5_clean --dump-c89 /tmp/p8_repro/<f>.z98 > <f>.c 2> <f>.err` (rc=2 = clean reject, 0 `.c`). Old = `/tmp/p8_base/zig1_5_clean` (HEAD), new = `/tmp/p8_build/zig1_5_clean` (P8). The four pre-checked shapes diff **byte-identical** old→new (`diff` of the stderr texts empty):

| program | shape | old | new | verdict |
|---|---|---|---|---|
| `r1_d6_ptrfromint` | `var p: *u8 = @ptrFromInt(*u8, 7);` (D6) | rc=2 `error[19]: @ptrFromInt requires exactly one argument: @ptrFromInt(expr)` | rc=2, **stderr byte-identical** | pinned text kept |
| `r2_ptrcast_1arg` | `@ptrCast(*u8)` | rc=2 `error[3049]: @ptrCast requires exactly two arguments: @ptrCast(T, expr)` | rc=2, **stderr byte-identical** | pinned text kept |
| `r3_ptrcast_3arg` | `@ptrCast(*u8, &b, &b)` | rc=2 same `error[3049]` text | rc=2, **stderr byte-identical** | pinned text kept |
| `r8_sizeof_2arg` | `@sizeOf(u32, 9)` | rc=2 `error[3074]: expected 1 argument(s), found 2` | rc=2, **stderr byte-identical** | introspection shape kept |
| `r4_exit_2arg` | `@exit(0, 1);` | **rc=0 (wrong-accept, .c emitted)** | rc=2 `error[19]: @exit requires exactly 1 argument(s): @exit(code)` | new clean reject (D6-class) |
| `r5_putchar_2arg` | `@putChar('a', 'b');` | **rc=0 (wrong-accept)** | rc=2 `error[19]: @putChar requires exactly 1 argument(s): @putChar(c)` | new clean reject |
| `r6_iswindows_1arg` | `@isWindows(true)` | **rc=0 (wrong-accept)** | rc=2 `error[19]: @isWindows requires exactly 0 argument(s): @isWindows()` | new clean reject |
| `r7_intcast_1arg` | `@intCast(i32)` | **rc=0 (wrong-accept)** | P8: rc=2 `error[19]: @intCast requires exactly 2 argument(s): @intCast(T, expr)` — **fix round 1 (Amendment 6 A): rc=0, arity-accepted BY DESIGN** (the 1-arg form `@intCast(expr)`; 393 B `.c`, 0 diagnostics) | the 1-arg form is the accepted surface |
| `r9_getchar_1arg` | `@getChar('x')` | **rc=0 (wrong-accept)** | rc=2 `error[19]: @getChar requires exactly 0 argument(s): @getChar()` | new clean reject |
| `r10_intcast_0arg` | `@intCast()` (the @intCast D6 reject shape post-fix) | n/a — fix round 1 reproducer | rc=2 `error[19]: @intCast requires 1 or 2 argument(s): @intCast(T, expr) or @intCast(expr)` | new clean reject (D6-class, 0-arg) |
| `r11_intcast_3arg` | `@intCast(i32, 7, 8)` (the @intCast D6 reject shape post-fix) | n/a — fix round 1 reproducer | rc=2 same range message | new clean reject (D6-class, ≥3-arg) |

Correct-arity controls: `c1_control` (`@putChar('x'); @exit(0);`), `c2_control` (`@sizeOf(u32)` + `@intCast(i32, 7)`), `c3_control` (`@isWindows()` + `@getChar()`) — **all rc=0 both compilers, .c byte counts unchanged** (581/592/712) — no false-positive rejects on the correct forms. The battery (items 3-7) is the wide no-false-positive proof: goldens/examples/pins all frozen.

Note (established-shape consequence, same as pre-P8 `@ptrFromInt`/`@ptrCast` rejects): a wrong-arity call whose result feeds an inferred `var` (`var b = @isWindows(true);`) yields `TYPE_UNDEFINED`, so later uses of `b` add the pre-existing `error[20]: identifier 'b' is not declared` cascade (visible in r6/r9 — r7 pre-fix-round-1; r7 is arity-accepted as of fix round 1); typed declarations (`var p: *u8 = …`) show only the arity diagnostic (r1 byte-identical).

## STOP-present (class mover — program + builtin, operator judgment requested)

> **STOP-present: I found the intention is** a single fixed expected-arity per builtin derived from Spec §4, closing the wrong-accept class and producing a byte-identical corpus class file, **but this is impossible given** `@intCast`'s one-argument form is a **deliberate, fixture-pinned Z98 surface** (not a D6-class wrong-accept): the table's `@intCast` row (arity 2) false-positives the frozen positive fixture `repro/mi_matrix/stdlib_intcast_loop_capture_xmod`, and the touch set forbids re-baselining it.

**Program:** `repro/mi_matrix/stdlib_intcast_loop_capture_xmod/main.zig` — Task 7 positive runtime fixture, corpus class `OK` (now `FAIL`), **and** a stdlib-gate fixture with a committed golden (`cap=6 ren=8 cpy=3 loc=2 nest=2 sl=6`, `expected.rc=0`).

**Builtin:** `@intCast`, **one-argument form `@intCast(expr)`** (7 call sites in the fixture).

**Observed:**

- baseline `/tmp/p8_base/zig1_5_clean` (HEAD): dump rc=0, 387,667 B of C, 0 diagnostics; golden MATCH (class `OK`).
- P8 `/tmp/p8_build/zig1_5_clean`: dump rc=2, 0 `.c`, 7× `error[19]: @intCast requires exactly 2 argument(s): @intCast(T, expr)`; class `FAIL`; stdlib gate 284/1 (same fixture).

**Why this is almost certainly a FALSE POSITIVE (the brief's anticipated "overloaded and the table guessed wrong" class), not a D6-class reject:**

1. **The fixture documents the form as designed.** Its header: "A one-argument `@intCast(expr)` (official Zig 0.15.2 infers the target type from context) must lower its operand: Z98 sema's single-argument builtin fallback types the expression as the operand's own type, so the cast is an identity here." The Task 7 defect it fixes was that the 1-arg form emitted an undeclared `zT_N` (gcc error) — the FIX made 1-arg `@intCast` LOWER correctly; rejecting the call would un-accept the very surface Task 7 shipped.
2. **The brief's arity source of truth is "the language spec builtin list (§4) as implemented by the ladder."** The ladder's single-argument fallback (last-resort arm: `ec_n >= 1` → result = arg0's own type) IS the implemented 1-arg surface. Spec §4's `@intCast(T, expr)` row documents only the 2-arg spelling — the spec table is incomplete relative to the implemented surface here, and the "as implemented" clause resolves the conflict in favor of accepting 1 arg.
3. **Official Zig 0.15.2 parity** (the project's stated oracle): `@intCast(x)` is the Zig-0.15 form (result type inferred from context); the fixture's golden was cross-checked against a Zig 0.15.2 twin.
4. **Rejecting it violates P8's own primary gate** ("correct-arity programs: ZERO change — stdlib/mi_matrix/corpus class all frozen"): the fixture is a correct program under its contract, and it is frozen in TWO gates (corpus `OK` anchor + stdlib 285/0).

**What the ruling decides (recommendation included):**

- **Ruling A (recommended — false positive):** the `@intCast` row's expected arity becomes a **range 1..2** (accept `@intCast(expr)` and `@intCast(T, expr)`; still reject `@intCast()` and `@intCast(T, x, extra)` — the true D6-class wrong-accepts; my `r7` reproducer would become the 3-arg shape). Small table change (one row gains min/max); re-run the battery → 0 movers expected.
- **Ruling A′ (wider, if the operator reads the fallback as the designed 1-arg surface for ALL type-value casts):** rows `@floatCast`/`@intToFloat`/`@intToEnum`/`@volatileCast`/`@intToPtr`/`@as` also accept 1..2 (their 1-arg identity fallback is the same mechanism — no committed program depends on it; 0 other movers). `@ptrCast` stays exactly 2 (its pre-P8 check is byte-identity-gated).
- **Ruling B (legitimate D6-class reject):** the strict-2 table stands; then the fixture, its Task 7 contract, its committed golden and the stdlib `expected_dirs.txt` pin must be re-baselined/reclassified by the operator (outside my touch set — cannot be executed within bounds).

No other builtin in the 37-row table produced a mover or a gate break.

### Operator ruling + fix round 1 (Amendment 6: "A + (i)", 2026-10-15)

Operator ruled **A + (i)** on the STOP-present above. **(A)** the `@intCast` table row becomes an accepted-arity **range 1..2** — accept `@intCast(expr)` (1-arg; identity typing via the sema single-argument builtin fallback, the Task 7 lowering path) and `@intCast(T, expr)` (2-arg); reject 0 args and ≥3 args (the true D6 wrong-accept class). All other rows UNCHANGED — `@ptrCast` stays exactly 2 (byte-gated `ERR_3049` texts), all other type-value casts stay exactly 2, 1-arg plains stay exactly 1. Option A′ REJECTED (only `@intCast` has a 1-arg lowering path). **(i)** ONE-sentence Spec §4 truth-up documenting the accepted 1-arg form.

**Fix (commit (a) `fix(semantic_analyzer): P8 fix round 1 — @intCast accepted arity range 1..2 (Amendment 6 A+i)`):**

- `semantic_analyzer.zig` `BuiltinDesc`/`semanticAnalyzerBuiltinDesc`: the `@intCast` row is `arity = 2, arity_kind = 2` — `arity_kind` class 2 = accepted range `1..arity` (min 1, max `arity`); row message = the range wording `@intCast requires 1 or 2 argument(s): @intCast(T, expr) or @intCast(expr)` (the old "requires exactly 2" text was P8-new and NOT byte-gated).
- `semanticAnalyzerCheckBuiltinArity`: class-2 rows enforce `min ≤ ec_n ≤ max` (`1 ≤ ec_n ≤ 2` for this row); every other row keeps exact equality. A range mismatch takes the row's established class-0 shape (row code + message, arg0-if-present resolved, `TYPE_UNDEFINED`).
- `@ptrCast`/`@ptrFromInt`/introspection rows untouched — reproducers r1/r2/r3/r8 below prove the gated texts byte-identical.
- Spec: `docs/reference/Language_Spec_Z98.md` §4 — one sentence under the cast/conversion table + the `@intCast(T, expr)` cell extended to `@intCast(T, expr)` / `@intCast(expr)`.
- Tech docs: `sf/docs/tech_docs/05_semantic_analysis.md` §Builtin dispatch truth-up `[updated: 2026-10-15 — P8 fix round 1 …]` (the only doc line stating the `ec_n != arity` rule; `08_c89_emission.md`/`INDEX.md` do not name the per-row arity rule and are unchanged).

**Fix round 1 runtime battery — full 8 items (commands + observed; compiler `/tmp/p8f1_build/zig1_5_clean`, two-hop build of the fixed tree):**

1. **Seed two-hop.** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p8f1_build` → `[seed] hop1 binary md5: 7d1529c68562d5b2b2e3548129f08856` / `[seed] hop2 binary md5: 7d1529c68562d5b2b2e3548129f08856` / `[seed] two-hop closure OK: hop1 == hop2 == 7d1529c68562d5b2b2e3548129f08856`. **hop1==hop2**; fixed point old `1501f571c5cd2fcaf2f291adacfc8965` → **new `7d1529c68562d5b2b2e3548129f08856`** (moved as expected — `sf/src` moved; seed NOT rotated — Task C).
2. **Corpus classify — BYTE-IDENTICAL, 0 movers (load-bearing).** `bash scripts/corpus/classify /tmp/p8f1_build/zig1_5_clean /tmp/p8f1_run/corpus.txt` → `wrote /tmp/p8f1_run/corpus.txt: 1124 dirs`; `md5sum` = `518eca1a9b5d3e1cc5a48abce214abd8` == the frozen Appendix A anchor **exactly**; tally `1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`; `repro/mi_matrix/stdlib_intcast_loop_capture_xmod OK` (the mover returns to OK — gate restored, not patched).
3. **Goldens 5/5.** dump+gcc (§1.3 recipe) all rc=0 (0 `error:`); gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`; lisp `(+ 1 2)` `b3d9f8974da24ddbf9d389f3d7d97322`; json `8bda3d5a1ec07d14a301bc343df32bf8`; mud session rc=0, server `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7`, both `cmp`-IDENTICAL to `demo/canonical_expected.txt`/`demo/canonical_client_expected.txt`.
4. **mi_matrix 25 + oob.** `bash scripts/stdlib/run_fixtures.sh /tmp/p8f1_build/zig1_5_clean <the 25 §1.8 anchor dirs>` → `run_fixtures: 25 PASS / 0 FAIL over 25 dirs`. Trap `slice_index_field_store_oob_xmod` (`-fsafe`): dump/build rc=0, run **rc=133** (Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e` == empty `expected.txt`), `expected.rc=133` — **MATCH**.
5. **examples 26/26 build + 26/26 run.** Build (`-ffast -o`, `build_target.sh linux`): 26/26 dump=0 / `.c` counts identical to §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run (CWD = example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* `q\n`): 26/26 rc + stdout md5_16 IDENTICAL to §1.4 (days_in_month `8c0d394cbc6e7f36` … mud rc=124 `9545fe1d245293ef` … z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`, rogue×2 `3fb6709e7bbd8964`).
6. **stdlib — 285/0 RESTORED (load-bearing).** `bash scripts/stdlib/verify_stdlib.sh /tmp/p8f1_build/zig1_5_clean` → `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK`.
7. **The 8 `--dump-c89` pins (old = the P8/P9 record → new; sequential from repo root): all 8 identical → pin delta 0/8.** mud_server `-fsafe` `bbc02913a10af9b0b5ed0f292f4e3407` / `-ffast` `fa346108ed00d03a037c2f9331d3bdf8`; game_of_life `-fsafe` `93c5e3fdc5b80b2f3db020d995abbe3f` / `-ffast` `01a4e2265b33c97a8ca6ff3dfa551231`; lisp_interpreter_curr `-fsafe` `6da05d070acd414674b1b1ec947baa5c` / `-ffast` `e3970e33ac09c8dfaa316d2d69bf61ec`; json_parser `-fsafe` `af3823fae0b29fa4d4ca58932538d631` / `-ffast` `24e0e812e7dffa5a43750135405ffe3f`.
8. **Markers telemetry.** `/tmp/p8f1_build/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > /tmp/p8f1_run/mk_gol.c 2> /tmp/p8f1_run/mk_gol.bin` — dump rc=0; stderr **3,437 lines / 38,384 B** = record **3,437 / 38,384** (unchanged; telemetry).

**Arity reproducers (fix round 1, `/tmp/p8f1_repro/`, same recipe `zig1_5_clean --dump-c89 /tmp/p8f1_repro/<f>.z98 > <f>.c 2> <f>.err`):** r1/r2/r3/r8 gated texts byte-identical to the §Arity-reproducers table; r4/r5/r6/r9 unchanged; `r7_intcast_1arg` (`@intCast(i32)`) now **rc=0, arity-accepted BY DESIGN** (the 1-arg form; 393 B `.c`, 0 diagnostics); the `@intCast` D6 reject reproducers are now `r10_intcast_0arg` (`@intCast()`) and `r11_intcast_3arg` (`@intCast(i32, 7, 8)`) — both rc=2 / 0 `.c` / `error[19]: @intCast requires 1 or 2 argument(s): @intCast(T, expr) or @intCast(expr)` (class-0 shape); `r12_intcast_1arg_value` (`var x: i32 = @intCast(7);`) rc=0 / 393 B `.c` (the 1-arg value form lowers via Task 7); controls c1/c2/c3 rc=0 (523/393/433 B `.c`) — no false-positive rejects.

## Concerns

- **C1 (the STOP):** one class mover — `repro/mi_matrix/stdlib_intcast_loop_capture_xmod` `OK→FAIL` (1-arg `@intCast`) — presented above for operator judgment (false-positive recommendation Ruling A). Not silently accepted; not unilateral-fixed (the brief reserves the judgment). Until ruled, the corpus class file is `3e675229…` vs anchor `518eca1a…` and the stdlib gate is 284/1 (same fixture).
- **C2:** fixed point moved (expected): `3c0376fc62002297029f6ecc278a259c` → `1501f571c5cd2fcaf2f291adacfc8965`; seed NOT rotated (Task C closeout).
- **C3 (`error[19]` rendering, pre-existing):** `ErrorCode.ERR_3000_TYPE_MISMATCH` has no explicit tag (`diagnostics.zig:30`), so the established-shape code renders `error[19]` (true for pre-P8 `@ptrFromInt` rejects too — baseline r1 shows `error[19]`). The table reuses the same enum expression for byte-identity, so the new generic rejects also print `error[19]`. Fixing the enum tag (`= 3000`) is an unrelated fix (out of scope; named for the Task-C ledger).
- **C4 (resolve shape on mismatch, §2.5):** the established arm shape (arg0-if-present only) is used uniformly. If the operator prefers resolving ALL present args ("what exists" in the literal plural), that is a one-line widening in `semanticAnalyzerCheckBuiltinArity` + a re-diff of the r1/r2/r3 reproducers.
- **C5 (cVa signatures in messages):** `@cVaStart`/`@cVaEnd`/`@cVaArg` carry no Spec §4 signature text; the rows spell the implemented surface (`@cVaStart(&vl)`, `@cVaArg(&vl, T)`, `@cVaEnd(&vl)` — ladder/lowerer + `repro/mi_matrix/fn_varargs_body` usage). Arity 1/2/1 is confirmed by that usage and by the lowerer's `lower.zig:6200-6240` arg consumption.
- **C6 (1-arg form of the other type-value casts):** today's fallback accepts 1-arg `@floatCast`/`@as`/… as identity; the strict-2 rows now reject them (no committed program uses them — 0 movers). Whether that is a D6-class close or an @intCast-class false positive is folded into Ruling A′ above.
