# Phase 3.5 Task 9l — assignment/expression `void` audit

**Task:** 9l (investigation/test-only; no `sf/src` change, no Task 9m, no Task 9k change).
**Status:** COMPLETE — STOP for operator review before Task 9m/9k.
**Date:** 2026-11-09.
**Repo:** `/workspace/znineeight`, branch `zig1_improvements`, HEAD
`93068f57e1f44cbfe43503c9c11368634dc96dc8` (compiler source unchanged since
`e178063d`; `sf/src/semantic_analyzer.zig` still the `280a3b12` blob
`1fb55af6…`).
**Baseline discipline:** every build and corpus/emission run used a clean
detached worktree at `93068f57` (`/tmp/phase35-9l-clean`) or a `git archive` of
it. The uncommitted Task 9k candidate in the main worktree was never read,
built, modified, staged, or committed. The main worktree was not built.

---

## 1. Oracle and compilers

The Task 9j Zig 0.17.1 oracle was present and verified; no substitute was used.

| Item | Observed value |
|---|---|
| Binary | `/tmp/phase35-d15-i/zig-0.17.1/zig` |
| `zig version` | `0.17.1` |
| Binary SHA-256 | `58959f01285c05a74276f09327b551d42ed6006bf325a78dc661a024e314987b` |
| Archive SHA-256 | `3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a` |

Clean HEAD build:

```sh
git worktree add --detach /tmp/phase35-9l-clean 93068f57
cd /tmp/phase35-9l-clean
bash scripts/self_compile/build_next_gen.sh \
  /workspace/znineeight/zig1/zig1_5_clean /tmp/phase35-9l-work/build
```

Observed HEAD binary md5 `5011d08cd6419d2f8b2cab2af0977055` (sha256
`23befcded9c2adbf02741cdd22d9126e5603a219994fc3a49d7a8db2af8d6467`), identical
to the Task 9j current rebuild. Exact provenance is in
`repro/mi_matrix/known_excluded/d15_assignment_void/results/compilers.txt`.

Throwaway diagnostic variants (A–H) were built from `git archive HEAD` copies
in `/tmp` only. They are not the 9k candidate, are not applied to the repo, and
exist solely to measure the options below.

---

## 2. Zig 0.17.1 semantics (Step 1)

Probes: `repro/mi_matrix/known_excluded/d15_assignment_void/probes/z01..z28`.
Observed oracle output: `results/zig_0_17_1.tsv`; Z98 probe matrix:
`results/z98_probe_matrix.tsv`.

**Key result: Zig has no assignment expression.** Assignment is a statement.
An assignment-ending block has type `void`. Every probe that consumes an
assignment as a value is a parse or type error.

| Probe | Shape | Zig 0.17.1 | Type/notes |
|---|---|---|---|
| z01 | `g = 1;` statement | accept | statement |
| z02 | `const y: i32 = g = 1;` | reject | `expected ';' after statement` |
| z03 | `const y: i32 = (g = 1);` | reject | `expected ')', found '='` |
| z04 | labeled break of assignment | reject | `invalid left-hand side to assignment` |
| z05 | `const y: void = { g = 1; };` | accept | assignment-ending block is `void` |
| z06 | `{ g = 1; }` statement | accept | statement block |
| z07 | `g = h = 1;` | reject | `expected ';' after statement` (no chaining) |
| z08 | `if (g = 1) {}` | reject | parse error (assignment not an expression) |
| z09 | `while (g = 1) {}` | reject | parse error |
| z10 | statement switch, assignment + `{}` prongs | accept | all prongs `void` |
| z11 | statement switch, assignment + value prong | reject | `incompatible types: 'void' and 'comptime_int'` |
| z12 | statement switch, mixed int/bool | reject | `incompatible types: 'comptime_int' and 'bool'` |
| z13 | `_ = (g = 1);` | reject | parse error |
| z14 | `defer g = 1;` | accept | statement |
| z15 | `const y: ?i32 = { g = 1; };` | reject | `expected type '?i32', found 'void'` |
| z16 | `const y: E!i32 = { g = 1; };` | reject | `expected type 'E!i32', found 'void'` |
| z17 | `take(g = 1);` | reject | parse error |
| z18 | if-expression arm assignment | reject | parse error |
| z19 | `return (g = 1);` | reject | parse error |
| z20 | `(g = 1);` | reject | parse error |
| z21 | `@TypeOf(g = 1)` | reject | parse error (assignment is not an expression) |
| z22 | value switch with expected `void` | accept | all prongs `void` |
| z23 | `arr[0] = 2` as value | reject | parse error |
| z24 | nested statement blocks ending in assignment | accept | `void` |
| z25 | block with `if`-statement tail as `i32` | reject | `expected type 'i32', found 'void'` |
| z26 | statement switch, block assignment prongs | accept | all prongs `void` |
| z27 | value switch (`i32`) with assignment block prong | reject | `expected type 'i32', found 'void'` |
| z28 | if-statement assignment branches | accept | statement |

Consequences:

- The only legal assignment uses are statement position, a block tail whose
  value is discarded/`void`, and `defer`.
- A block ending in an assignment is `void`; a block ending in an
  `if`/`while`/`var_decl` statement is also `void`.
- `_ = expr` discards; it is not an assignable expression.
- Optional/error-union value positions do **not** accept an assignment-ended
  block.

Z98 current is the opposite on the block/switch tail: `ResolveAssign` returns
the LHS type, so an assignment-ended block behaves like a value. Most of this
divergence is currently hidden because Z98's parser also rejects `(x = 1)` and
assignment in general value positions. It becomes observable only where a
block tail or switch prong is resolved as an expression (`z15`, `z16`, `z27`,
and the 35 statement-switch entries).

---

## 3. Sema inventory (Step 2)

### 3.1 Assignment result

`semanticAnalyzerResolveAssign` (`sf/src/semantic_analyzer.zig:4660`) returns:

- `TYPE_VOID` on every error/discard path (including `_ =`, line 4678);
- **`lhs` on success**: `sf/src/semantic_analyzer.zig:4725` (normal assignable
  coercion) and `:4729` (float-narrow accept).

The generic `semanticAnalyzerResolveExprImpl` writes the returned type into the
resolved-type table for the assignment node (tail after the dispatch,
`sf/src/semantic_analyzer.zig:5820` onward).

### 3.2 Consumers of the assignment/block result type

| Consumer | Location | Effect if assignment returns `void` |
|---|---|---|
| Block tail | `semantic_analyzer.zig:5766-5790` | Block ending in assignment becomes `void` (Zig-correct). |
| `expr_stmt` | `semantic_analyzer.zig:5748-5755` | Result already discarded; no behavioural change. |
| Assignment statement walk | `semantic_analyzer.zig:6845` | Result ignored; no change. |
| Switch prong type | `semantic_analyzer.zig:5162` | Assignment/assignment-block prong becomes `void`; peer/expected unification changes. |
| Switch expected/peer paths | `semantic_analyzer.zig:5037-5044`, `:5179-5220` | `sw_is_stmt_expr` masks heterogeneous statement switches; after removal, assignment prongs must be `void` to keep valid all-void statement switches accepted. |
| `orelse` fallback | `semantic_analyzer.zig:3801-3862` | `rhs_result == TYPE_VOID` now also catches assignment-ended blocks; the AST helper `semaOrelseFallbackIsValueless` already treats them as valueless, so behaviour stays aligned (a stale comment at `:3843` would need updating). |
| Typed/untyped var/const init | `semantic_analyzer.zig:6688-6769` | Untyped `const x = blk:{ y=1; }` becomes `void` and is rejected by the existing “cannot declare variable of type void” path; typed `?i32`/`E!i32` init only warns (see §5.3). |
| Return / call arg / field / array init / if-expr arms | `ResolveExpr` call sites | Assignment is not parsable there, so no valid-code change. |
| `astTerminates` / `semaOrelseFallbackDiverges` | `semantic_analyzer.zig:6060`, `:3930` | These read the node’s resolved type for `noreturn`; assignment nodes were not `noreturn`, so no change. |
| `semaOrelseFallbackIsValueless` / `semaIsAssignmentKind` | `semantic_analyzer.zig:3866-3923` | AST-kind based, already treats assignment as valueless. |
| `semanticAnalyzerFloatNarrowArmStatus` (f32 switch/if) | called from switch tail `:5240` | It reads prong resolved types; an assignment prong would classify as `void`, which is the desired reject at an f32 site. |
| **`async_analysis.scanFrameLocals`** | `sf/src/async_analysis.zig:383-445` | It reserves a frame field for **every AST node** using the node’s resolved type (`:396`). Voiding assignment nodes shrinks/changes async frame sizes; this is outside sema and is a hard blocker for global assignment-void (see §4.3). |
| **`lowerCompoundAssignRest`** | `sf/src/lower.zig:6103-6107` | It types the compound-assignment op temp from the **assignment node’s** resolved type. Voiding the node makes the op temp `void`/`int`, changing arithmetic types and emission. Required lowering change for global assignment-void. |

### 3.3 `stmt_expr_node`

`stmt_expr_node` is set for `expr_stmt` (`semantic_analyzer.zig:5748`) and for a
bare expression statement (`:6883-6887`). It is read by:

- the switch statement exemption (`:5044`, `sw_is_stmt_expr`), and
- the `orelse` value-position reject (`:3849`).

It does not depend on the assignment result type. Removing the switch exemption
does not require changing `stmt_expr_node`.

---

## 4. Lowering / temp inventory (Step 3)

### 4.1 Plain assignment

`lowerExprStep` dispatches `plain_assign` to `lowerPlainAssignStep`
(`sf/src/lower.zig:2842`) → `lowerPlainAssignRest` (`:6532`). The rest lowers
only the RHS, calls `lowerAssignLValue`, and **returns the RHS temp `src`**
(`:6566`). There is no separate “assignment result” temp.

Therefore:

- Plain assignment can already lower store-only with no value temp. The RHS
  temp is the value, and the store consumes it.
- A block or switch tail reuses that RHS temp as the block/switch value today.
  If sema types the assignment `void`, discarded positions simply ignore it.
- `lowerPlainAssignRest` already handles `src == TEMP_NONE` and `src == 0`
  (void RHS) and skips the store (`:6535-6555`). No new `TEMP_NONE` work is
  needed for plain assignment.

### 4.2 Compound assignment — a real coupling

`lowerCompoundAssignRest` (`sf/src/lower.zig:6103`) does:

```zig
var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
if (op_rt) |t| { op_r_box[0] = t; }
var op_r = nextTemp(self, op_r_box[0]);
```

If `ResolveAssign` returns `void`, `op_r` is created as `void` (emitted as
`int`), so `x += y` changes type and emits an extra materialisation temp. In the
emission matrix this produced **27 differing files** across the 185 switch
entries, including a real signedness change (`unsigned int` → `int` in
`std_ecc`) — not acceptable as a silent side effect.

Variant D (assignment-void + typing the op temp from the LHS temp instead of the
assignment node) reduces the diff count from 27 to **2**.

### 4.3 Async frame sizing — the second real coupling

`async_analysis.scanFrameLocals` (`sf/src/async_analysis.zig:383`) walks every
node in a suspending function body and calls `addFrameField` with the node’s
resolved type (`:395-397`). `frameFieldSizeAlign` uses the type’s
size/alignment (`:328-342`). Voiding assignment nodes changes `@asyncFrameSize`
results (`mud_server` 712→720, `z9torr` 12808→12688 in variant A), which is both
an emitted-constant change and a potential **under-reservation** of the async
frame (the code documents over-reservation as the P3 safety guard).

Variant E (D + using the LHS resolved type for assignment nodes in
`scanFrameLocals`) reduces the remaining emission diff to **1 file** (`z9torr`,
frame 12808→12816, an over-reservation increase). Even so, global
assignment-void requires an `async_analysis.zig` change and async-suite
verification.

### 4.4 Block-value and switch lowering

- `lowerBlockValueStep` (`sf/src/lower.zig:3006`) treats the last child as a
  value unless `lowerIsNoValueStmtKind` (`:13135`) says otherwise. Assignment is
  **not** in that predicate, so an assignment tail is lowered through
  `lowerExpr` and its RHS temp is returned. A store-only normalization would add
  `lowerIsAssignmentKind` to the block-value/`lowerExprOrBlock` tail checks and
  return a void temp. This is optional for correctness (the value is discarded
  in legal programs) and is not needed by the recommended option.
- `lowerExprOrBlock` (`:14121`) uses the same predicate; the catch/orelse join
  guard already uses `lowerBodyIsValueless` (`:13113`), which **does** treat
  assignment as valueless.
- Statement-switch lowering (`lowerSwtExLoop`, `:4634`) types its result temp
  from the **switch** node’s resolved type, not the prong expressions, and
  lowers block prong bodies through `lowerStmt` with `prong_val = 0`. Once sema
  types an all-void statement switch `void`, lowering is already store-only.
- No emitter change is needed for switch-only typing.

### 4.5 Answer to “can assignment lower store-only?”

Yes. Plain assignment already does. The only lowering reads that must change for
a **global** assignment-void rule are:

1. `lower.zig:6105` — compound-op temp type must come from the LHS/operand, not
   the assignment node.
2. `async_analysis.zig:396` — frame-local reservation must use the LHS type for
   assignment nodes (or otherwise preserve the old reservation).

Block-value tail normalization is optional. The switch-only option (c) needs
neither change because it never edits the assignment node’s recorded type.

---

## 5. Impact matrix (Step 4)

### 5.1 Probe matrix

`results/z98_probe_matrix.tsv` compares HEAD, A, B, C, D, E, G, H.

| Probe class | HEAD | Global assignment-void (A) | Statement peer (C) | Switch normalise (G) | G + expected-first (H) |
|---|---|---|---|---|---|
| assignment statement / block / defer (`z01,z05,z06,z14,z24,z28`) | accept | accept | accept | accept | accept |
| value-position assignment parses (`z02,z03,z07,z08,z09,z13,z17-z21,z23`) | reject | reject | reject | reject | reject |
| statement switch all-void (`z10,z26`) | accept | accept | accept | accept | accept |
| statement switch mixed (`z11,z12`) | accept (wrong) | accept | reject | reject | reject |
| assignment block in `?i32`/`E!i32` (`z15,z16`) | accept (wrong) | accept + warning | accept + warning | accept (wrong) | accept (wrong) |
| value switch `i32` with assignment prong (`z27`) | accept (wrong) | reject | reject | reject | reject |
| `const y: void` (`z05,z22`) | reject (Z98 limitation) | reject | reject | reject | reject |

The `z15/z16` false accepts are a **pre-existing typed-variable mismatch
warning**, not fixed by assignment-void: Z98’s typed var/const init mismatch
reports `warning[3000]` and accepts (`semantic_analyzer.zig:6720-6745`). Making
those rejects would be a separate diagnostic-level task; it is out of scope for
9k and does not block the switch fix.

### 5.2 The 38/35 statement-switch set

The Task 9k universe is the 185 canonical entries whose sources contain
`switch`. Baseline: 147 of 185 are accepted at HEAD. Removing only
`sw_is_stmt_expr` (variant C) rejects **35** of those 147; the Task 9k report
counts 38. The three-entry difference is a counting/version difference in the
9k report; the report’s representative entries are all present in the observed
35. The full observed list and per-entry status is
`results/statement_switch_repro35.tsv`; all 185 are in
`results/corpus_switch_185.tsv`.

Outcome under the proposed shapes:

| Variant | HEAD-accepted entries that now reject | Comment |
|---|---|---|
| A (global void only) | 0 | Statement exemption still masks the switches. |
| B (global void + remove exemption) | **1** | only `repro/mi_matrix/stdlib_tls_alpn_xmod` |
| C (remove exemption only) | **35** | the reproduced 9k regression set |
| G (remove exemption + switch prong normalization) | **1** | same single fixture |
| H (G + expected-first) | **1** | same single fixture; plus 12 D15 cases accept |

The single remaining reject is not an assignment-void defect:

```zig
// repro/mi_matrix/stdlib_tls_alpn_xmod/main.zig:281-283
.established => established = true,  // void
.closed => failTls(mode),            // tls.TlsAction (not noreturn)
else => failTls(mode),               // tls.TlsAction
```

`failTls` calls `os.exit` but is declared `fn failTls(...) tls.TlsAction`
(`:178`), so it is not `noreturn`. The switch genuinely mixes `void` and a
tagged-union result. **Every** rule that removes the statement exemption rejects
it, matching Zig’s `incompatible types` rejection. Task 9k must migrate the
fixture (e.g. `.closed => { _ = failTls(mode); }`, same for `else`) or keep the
statement exemption. This is an explicit operator decision.

### 5.3 Full canonical corpus

`results/corpus_all_1278.tsv` records `--check -ffast -I sf/src` for all 1278
canonical entries (1096 accepted at HEAD):

| Variant | HEAD accept → reject | HEAD reject → accept | diagnostic-code changes |
|---|---|---|---|
| A (global assignment-void) | **0** | **0** | **0** |
| B (A + remove statement exemption) | **1** (`stdlib_tls_alpn_xmod`) | **0** | **0** |

So global assignment-void alone is status-neutral on the whole corpus. Its risk
is emission (compound assignments, async frames), not acceptance.

### 5.4 Emission

`results/emission_switch_185.tsv` hashes emitted `.c`/`.h` for the 185 switch
entries under HEAD/A/D/E/G/H (D = A + compound-op fix, E = D + async fix).

| Variant | Emission diffs vs HEAD among the 147 HEAD-accepted entries |
|---|---|
| A (global void) | **27** (compound op temp type/materialisation; includes `unsigned int`→`int`) |
| D (A + compound-op fix) | **2** async frame sizes (`mud_server`, `z9torr`) |
| E (D + async frame fix) | **1** (`z9torr`, +8 over-reservation) |
| G (switch-only normalization) | **0** |
| H (G + expected-first) | **19** expected D15 value-switch coercion shifts |

The H shifts are the D15 expected-type fix itself (e.g. `opt_val_switch` now
materialises the optional instead of the old peer-typed integer). They are
semantically correct but are **not byte-identical**; Task 9k must review them
and cannot keep an unconditional “valid switches byte-identical” acceptance
criterion. G alone is byte-identical because it only changes which type is
used for valueless prongs, not the assignment node or lowering.

### 5.5 D15 under the combined target shape (H)

`results/d15_parity_under_H.tsv`:

- 12/12 `corpus_adapted/` cases: rc 0, 5 `.c` (Zig and pre-D15 parity).
- 5/5 `neg/` mixed cases: rc 2, exactly one `error[3000]`, 0 `.c`.
- `selectors/stmt_mixed_int_bool`, `stmt_mixed_int_void`: rc 2 (Zig parity).
- `selectors/stmt_void`: rc 0.
- `sel_runtime_opt_i32`, `sel_comptime_opt_i32`, capture/noreturn/undefined:
  rc 0.
- `sel_comptime_mixed_i32`, `sel_comptime_mixed_opt_i32`: still rc 2 (the
  documented Zig lazy-prong/spec divergence from 9j §5.1; unchanged).

---

## 6. Options and recommendation (Step 5)

### (a) Global assignment/block `void`

**Files:** `sf/src/semantic_analyzer.zig` (two `return lhs` → `TYPE_VOID`),
`sf/src/lower.zig` (`lowerCompoundAssignRest` op-temp type),
`sf/src/async_analysis.zig` (`scanFrameLocals` assignment-node type), plus
`repro/mi_matrix/stdlib_tls_alpn_xmod/main.zig` and tests.

**Blast radius:** every assignment node, every async frame, every compound
assignment. Measured: zero corpus status changes, but 27 emission diffs before
lowering fixes, 2 after the compound fix, 1 after the async fix; `z9torr`
frame +8. Not byte-identical without more async work. Does not by itself fix
`z15/z16` typed block-value false accepts (warning only). Requires an async
regression run and likely a new fixture expectation.

**Verdict:** technically feasible, but not the 2-line sema change the D15 task
assumed, and not safe to approve as Task 9m without the extra files and async
verification.

### (b) Expression-statement / block-only normalization

**Files:** `sf/src/semantic_analyzer.zig` block-tail/`expr_stmt` only.

**Blast radius:** block results become `void`, matching Zig for `z15/z16`-style
blocks, but switch prongs still see the LHS type. It therefore does **not**
fix the 35 statement-switch entries when `sw_is_stmt_expr` is removed, and it
does not make typed var/const init reject (warning only). **Insufficient alone.**

### (c) Switch-only normalization (recommended)

Keep global assignment typing unchanged. Inside
`semanticAnalyzerResolveSwitchExpr`, after resolving a prong body, treat a
valueless/assignment-ended body as `void` before peer/expected unification
(reuse the existing `semaOrelseFallbackIsValueless`, but skip `noreturn`).
Then implement the 9k expected-type-first shape and remove `sw_is_stmt_expr`.

**Exact files:**

- `sf/src/semantic_analyzer.zig` — switch resolver only:
  1. hoist `sw_exp = topExpectedType(self)` (normalise `TYPE_VOID` to 0);
  2. normalize `bt` for valueless/assignment-ended prong bodies to
     `TYPE_VOID` (skip `TYPE_NORETURN`);
  3. add the expected-type-first arm before the f32/peer arms, with the poison
     latch;
  4. remove `sw_is_stmt_expr`;
  5. leave f32 FX10, enum/tagged-union/captures, `undefined`, `noreturn`,
     import idiom, mandatory-`else`, and zero-prong paths unchanged.
- `repro/mi_matrix/stdlib_tls_alpn_xmod/main.zig` — make the `.closed`/`else`
  prongs `void` (e.g. `{ _ = failTls(mode); }`), or explicitly accept keeping
  the statement exemption instead.
- `sf/src/tests/test_semantic_bin.zig` — add assignment-prong switch cases
  (all-void statement accept; mixed void/value reject; value-result assignment
  prong reject).

No `lower.zig`, no `async_analysis.zig`, no emitter.

**Measured (G/H):** 34/35 reproduced statement entries fixed; only the genuine
`tls_alpn` mixed fixture remains and needs migration; 12/12 D15 cases accept;
statement mixed switches reject; `stmt_void` accepts; G emission is
byte-identical on all 185 switch entries; H adds only the expected D15
value-switch coercion shifts (19 files) that the operator must accept.

**Test plan:**
1. 12 `corpus_adapted/` cases: rc 0, 5 `.c`.
2. 5 `neg/` cases: rc 2, exactly one level-0 `error[3000]`, 0 `.c`.
3. 35 reproduced statement entries: rc 0 after migrating `tls_alpn`.
4. `stmt_mixed_*` reject; `stmt_void` accepts.
5. Full 1278-entry corpus: no new rejects beyond the migrated fixture.
6. Emission: statement-switch fixtures byte-identical; review the 19
   expected value-switch shifts; no async/lower changes.
7. `test_semantic_bin` and analyzer/semantic suites green.
8. `-fsafe` spot-check of the probe and switch sets.

### (d) Keep `sw_is_stmt_expr`, scope 9k to value-result switches

**Files:** `sf/src/semantic_analyzer.zig` expected-first arm only (plus tests).

**Blast radius:** value-result switches only. Zero new rejects; zero statement
emission changes; the 12 D15 cases and the 35 sensitive matrix cells still fix.
It leaves the Zig/spec divergence (`stmt_mixed_int_bool`, `stmt_mixed_int_void`
accepted) and does not touch assignment typing. This is the plan’s sanctioned
fallback and is the lowest-risk option, but it does not satisfy 9k’s current
“remove `sw_is_stmt_expr`” contract.

### (e) Revert `280a3b12` and document the D15 gap

Restores the pre-D15 false accepts (mixed value switches, mixed statement
switches) and leaves the 12 valid corpus cases rejecting. Only appropriate if
D15 is deferred entirely; not recommended.

### Recommendation

**Do not authorize Task 9m as a global assignment/expression-void change.** It
is not safe as a two-line sema change: it requires `lower.zig` and
`async_analysis.zig` changes, still changes async frame sizes, and leaves
`z15/z16` false accepts.

**Adopt option (c) in Task 9k:** switch-only valueless/assignment-prong
normalization + expected-type-first + removal of `sw_is_stmt_expr`, with the
`stdlib_tls_alpn_xmod` fixture migration. This fixes the D15 cases and the
statement-switch set with sema-only changes and byte-identical emission for
statement switches. If the operator does not want a new switch-normalization
rule or the fixture migration, use option (d) and amend 9k’s contract to keep
the statement exemption.

---

## 7. STOP — operator review

No `sf/src` file was changed by this task. Task 9m and Task 9k were not started;
the uncommitted 9k candidate was not used or modified.

Operator decisions required before 9k:

1. Approve option (c) (switch-only normalization + remove the statement
   exemption) **or** option (d) (keep `sw_is_stmt_expr`, scope 9k to value
   switches).
2. If (c): approve the one fixture migration in
   `repro/mi_matrix/stdlib_tls_alpn_xmod` and accept the 19 expected
   value-switch emission shifts from expected-type-first. Task 9k must not
   claim unconditional byte-identity for value switches.
3. Note the pre-existing `z15/z16` block-value false accepts and the 38-vs-35
   count difference as documented residual items; neither is an
   assignment-void blocker for 9k.

**Probes/results:**
`repro/mi_matrix/known_excluded/d15_assignment_void/`.
**Task report:** `.superpowers/sdd/2026-10-29-phase35-defects-plan/task-9l-report.md`.
