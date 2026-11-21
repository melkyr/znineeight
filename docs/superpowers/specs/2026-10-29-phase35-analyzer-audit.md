# Phase 3.5 — Static Analyzer Audit (D4-pre)

**Status:** Audit complete; investigation-only (no `sf/src` change, no fix).
**Base:** `c84abdbf` (`fix(async): correct the tail-return EU wrapper step ABI (Phase3.5 D14)`).
**Plan:** `docs/superpowers/plans/2026-10-29-phase35-defects-plan.md` Task 8.
**Consumes:** Task 0 probe `tests/analyzers/d4_contract_probe.zig`, Task 0
inventory `docs/superpowers/specs/2026-10-29-phase35-repro-inventory.md`,
Task 0.5 root causes `docs/superpowers/specs/2026-10-29-phase35-upstream-root-cause.md` §2.
**Produces:** the binding must-work set for Task 9 (D4-upgrade).

This audit reads the current analyzer pipeline, replays the D4 probe, isolates
the analyzer passes with `--no-null-check` / `--no-lifetime-check` /
`--no-leak-check`, exercises targeted `/tmp` fixtures for every claimed inert
path, and measures the self-source `WARN_6002` class. It defines what the four
analyzers promise, what they actually do, which diagnostics are false or
vacuous, and what Task 9 must make true.

---

## 0. Task 0.5 cause confirmation (STOP check)

The Task 0.5 report attributes D4 to four per-analyzer causes. Each is
confirmed in the current tree; **none is a downstream-only symptom**, so there
is no STOP.

| Analyzer | Task 0.5 cause | Current-code confirmation | Verdict |
|---|---|---|---|
| Lifetime / Provenance | Symbol-table provenance is structurally dead for fn locals/params; the analyzer-internal substrate is the real path; dead-arm parity is partial. | `classifyProvenance` queries `symbolTableLookup` first (`sf/src/analyzer.zig:89`); `symbol_registrator.zig` registers module-root decls only (`:473-502`); the no-symbol fallback is the state map (`analyzer.zig:100-111`). Params are seeded only in `runLifetimeAnalyzer` (`:1243-1266`). Fold table is absent from `AnalyzerContext` (`:518-544`). | **Confirmed upstream** (analyzer substrate, not a symptom of another pass). |
| NullPointer | Params are not seeded; `return` and `var` initializer expressions are not walked. | `runNullAnalyzer` seeds nothing (`analyzer.zig:1235-1241`); unknown idents fall to `maybe` (`:849-853`); `visitStatement` handles `return_stmt` without `analyzeExpr` (`:1149-1158`); `handleNullVarDecl` classifies but does not walk the initializer (`:916-926`). Targeted fixtures `np_return_null.zig`, `np_init_null.zig`, `np_assign_null.zig` all pass silently (rc=0, no diagnostic). | **Confirmed upstream** (walk/seed coverage). |
| DoubleFree | Ownership is name-keyed; assignment does not propagate allocation state; only captures inherit state. | `handleAllocAssign` writes `unknown` for an identifier RHS (`analyzer.zig:441-471`, especially `:470`); `onDoubleFreeStmt` handles `var_decl` with `handleAllocCall` only (`:1215-1217`); state inheritance exists only in `bindCaptureState` (`:1018-1031`). D4 probe shows `warning[3039] freeing untracked pointer 'q'` and no double-free for the alias chain. | **Confirmed upstream** (state model, not a diagnostic-format symptom). |
| Signature | Analyzer logic stands at T5; remaining items are test/doc residue. | `analyzeSignature` / `validateSignatureType` / `validateSignatureNamed` are recursive and active (`analyzer.zig:562-579`, `:679-727`); probe's `?Aggregate`, `E!Aggregate`, and arbitrary-width ints are clean. The residue is hand-fed-symbol tests (`sf/src/tests/test_analyzer_bin.zig:545`, `:571`, `:640`, `:667`, `:694`, `:726` omit `file_id`; `:1511` has it), aggregate-only `testFixture`, and docs. | **Confirmed: test/doc only**, not analyzer logic. |
| Cross-cutting dead-arm | The shared fold table exists but is not plumbed into the analyzer. | `phase_ComptimeEvaluation` runs before `phase_StaticAnalyzers` (`sf/src/main.zig:476`, `:483`); sema is bound to the table (`:838`); lowering consumes it (`sf/src/lower.zig:8013`); `phase_StaticAnalyzers` does not pass it (`main.zig:873-913`), and `AnalyzerContext` has no field for it (`analyzer.zig:518-544`). | **Confirmed upstream**; the table is available, the consumer is missing. |

Probe replay at this base (`tests/analyzers/d4_contract_probe.zig`, real
`--check` pipeline) reproduces the Task 0 inventory exactly:

```text
$ ./zig1/zig1_5_clean -ffast --check tests/analyzers/d4_contract_probe.zig
rc=2
warning[3037] potential null pointer dereference      (x2)
warning[3039] freeing untracked pointer 'q'
error[3035] double free of pointer 'p'                (dead arm)
error[3030] returning address of local variable 'x'   (true positive)
```

Code mapping (pre-existing enum-rendering drift; the names are the contract):
`warning[3037]` = `WARN_6002_POTENTIAL_NULL_DEREF`, `warning[3039]` =
`WARN_6006_FREEING_UNTRACKED`, `error[3035]` = `ERR_2005_DOUBLE_FREE`,
`error[3030]` = `ERR_2020_RETURNING_ADDRESS_OF_LOCAL`. The probe's two
`WARN_6002` lines are two passes reporting one walked condition (see §3 L2),
not two distinct source defects.

---

## 1. Contract inventory — what each analyzer should do

Design intent comes from `docs/sf/STATIC_ANALYZERS_p2.md` (the p2 design
document, still at the old path; Task 10 moves it to
`sf/docs/initial_design/STATIC_ANALYZERS_p2.md`), the diagnostics reference in
that document (§8), `docs/tech_debt/static_analyzers.md`, the D4 entry in
`examples/torrent_example_defects.md`, and the Task 0.5 fix contracts.

### 1.1 Lifetime / Provenance (`LifetimeAnalyzer`)

**Purpose:** detect pointers that outlive the storage they point at; in
practice, returning the address of a stack local/parameter, or returning a
pointer variable whose tracked provenance is local.

**Promised diagnostics:**

| Code | Level | Promise |
|---|---|---|
| `ERR_2020_RETURNING_ADDRESS_OF_LOCAL` | error | `return &local`, `return &local.field`, `return &local[i]` |
| `ERR_2021_RETURNING_ADDRESS_OF_PARAM` | error | `return &param` (the address of the parameter binding) |
| `WARN_6010_RETURNING_POINTER_VIA_VARIABLE` | warning | `var p = &local; return p;` and capture propagation |
| `WARN_6011_RETURNING_SLICE_OF_LOCAL` | warning | `return local_array[0..n]` |

**Provenance model:** `unknown` (call result/extern; safe), `local` (dangle),
`param` (by-value parameter; value safe, interior is call-frame), `param_addr`
(address of parameter; dangle), `global` (safe), `heap` (safe), `external`
(pointer-like parameter / caller-owned pointee; interiors safe, bare `&p`
dangles). The design says every pointer variable is tracked, parameters are
registered, and captures inherit the captured expression's provenance.

**Accepted shapes:** `return param_ptr` (safe), `return &global` (safe),
`return arena_alloc(...)` (heap), arbitrary member/index chains that bottom out
at a provenance-bearing base, and `if (opt) |ptr| { return ptr; }` where the
capture inherits the origin. The true positive `return &x` must stay reported.

**Known design limits (documented):** no alias tracking through pointer
dereferences, no field-level assignment tracking, no interprocedural analysis,
function results are conservatively `heap`, and captures are handled by the
analyzer-internal state map because the real pipeline has no local symbol
table.

### 1.2 NullPointer (`NullPointerAnalyzer`)

**Purpose:** report definite, uninitialized, and potential null pointer
dereferences before they become runtime faults.

**Pointer states:** `uninit = 10`, `is_null = 11`, `safe = 12`, `maybe = 13`.

**Promised transitions:** declaration with no init → `uninit`; `= null` /
`= 0` → `is_null`; `= &x` / `try alloc()` / `orelse` / `catch` → `safe`;
call result → `maybe`; null guards refine the then/else branches; captures
(`if`/`while`/`for`/switch prong/`catch`) are `safe`; branch merges of
divergent states → `maybe`.

**Promised diagnostics:**

| Code | Level | Promise |
|---|---|---|
| `ERR_2004_DEFINITE_NULL_DEREF` | error | dereference in `is_null` state |
| `WARN_6001_UNINIT_DEREF` | warning | dereference in `uninit` state |
| `WARN_6002_POTENTIAL_NULL_DEREF` | warning | dereference in `maybe` state |

**Accepted shapes:** `p.*` when `p` is `safe`; guarded `if (p) |q|` and
`if (p != null)`; `orelse` / `catch` results; non-optional pointer parameters
(which the design treats as caller-provided non-null pointers). Every deref —
in conditions, expression statements, assignment RHS, `return` expressions, and
`var` initializers — is in scope. A non-optional `*T` parameter must not warn;
an optional parameter must be conservative until refined.

### 1.3 DoubleFree (`DoubleFreeAnalyzer`)

**Purpose:** detect double frees, leaks, use-after-free, and ownership
transfers for the arena-style allocator API.

**Allocation states:** `untracked`, `allocated`, `freed`, `returned_val`,
`transferred`, `unknown` (plus the internal `freed_reported` latch).

**Promised diagnostics:**

| Code | Level | Promise |
|---|---|---|
| `ERR_2005_DOUBLE_FREE` | error | free of `freed` state |
| `ERR_2006_USE_AFTER_FREE` | error | same-block deref/index/field use after free |
| `WARN_6005_MEMORY_LEAK` | warning | allocation not freed at scope exit / overwritten |
| `WARN_6006_FREEING_UNTRACKED` | warning | free of a name with no allocation state |
| `INFO_7001_OWNERSHIP_TRANSFERRED` | info | pointer passed to an ownership-taking function |

**Promised transitions:** alloc call / `try alloc` → `allocated`; free →
`freed`; second free → `ERR_2005`; `p = new_alloc` while `allocated` →
leak warning for the old allocation; `p = null` → leak warning; `return p` →
`returned_val`; `some_func(p)` → `transferred`; captures inherit the origin's
state and mark the origin transferred; branch merges produce `unknown`; scope
exit reports `allocated` leaks. Alias assignments (`var q = p`) are part of the
design's ownership model: the alias must be tracked and cross-name frees must
be checked.

**Accepted shapes:** the true `free(p); free(p)` double free, allocation →
free → no leak, return-of-allocation, capture aliases, and defer-driven frees.
The free/alloc recognition is intentionally API-shaped (`arena_alloc`,
`sandAlloc`/`sand_alloc`, `gpaAlloc`/`gpaAllocZeroed`; `arena_free`,
`sandFree`, `gpaFree`).

### 1.4 Signature (`SignatureAnalyzer`)

**Purpose:** reject function signatures that cannot be represented in C89 or
that use unsupported Z98 type forms; accept the D1/D2 fixed shapes.

**Promised diagnostics:**

| Code | Level | Promise |
|---|---|---|
| `ERR_2010_VOID_PARAMETER` | error | direct parameter resolves to `void` (nested `*void` is fine) |
| `ERR_2011_INCOMPLETE_TYPE` | error | named aggregate/enum in a signature is unresolved/not laid out, at any wrapper depth |
| `ERR_2012_ANYTYPE_NOT_SUPPORTED` | error | `anytype` anywhere in a signature, recursively through wrappers and fn-ptr lists |
| `WARN_7010_LARGE_RETURN` | warning | direct/fn-ptr return size > 64 bytes |
| `ERR_2013_OPAQUE_NOT_SUPPORTED` | error | reserved in the enum, not emitted by the analyzer |

**Accepted surface (must stay clean):** fn-ptr returns of `?Aggregate` /
`E!Aggregate`; arbitrary-width ints (`i1`-`i63` / `u1`-`u64`); member type
expressions (`mod.Key`, `T.tag`); complete aggregates at any wrapper depth.
Any diagnostic on this surface is a false positive.

### 1.5 Shared pipeline contract

- Analyzers run after sema (`phase_StaticAnalyzers` after
  `phase_ComptimeEvaluation` / `phase_SemanticAnalysis`; `main.zig:476`, `:483`).
- Per-function state is scratch-reset and isolated; each analyzer gets a fresh
  `StateMap` and defer queue (`analyzer.zig:1283-1319`).
- Analyzers are post-sema and must not change emission.
- Diagnostics should identify the source construct (the design sketches carry
  spans); current null/lifetime/double-free diagnostics pass `file_id = 0`.
- The shared comptime fold table (`comptime_eval.zig:77`) is the single source
  of truth for "comptime-untaken arm does not exist for analysis"; sema and
  lowering consume it, so the analyzers must consume the same table for
  parity.

---

## 2. Reality map — what each analyzer actually does

### 2.1 Lifetime / Provenance

**Real path (works):**
- `classifyProvenance` (`analyzer.zig:72-153`) classifies `address_of`,
  `fn_call`, `field_access`, `slice_expr`, `ident_expr`.
- `checkReturnProvenance` (`:155-226`) reports `ERR_2020` for `&local`,
  `WARN_6011` for `local[0..]`, `WARN_6010` for a tracked local pointer, and
  `ERR_2021` for `param_addr`.
- `runLifetimeAnalyzer` (`:1243-1271`) seeds pointer-like parameters as
  `external` and by-value parameters as `param`; `onLifetimeStmt`
  (`:1193-1210`) tracks `var_decl` and `plain_assign` provenance; capture
  inheritance is in `bindCaptureState` (`:1014-1017`).
- True positive preserved: D4 probe reports `error[3030]` for `return &x`.

**Inert / structurally dead path:**
- **Symbol-table provenance is dead for locals/params.** `classifyProvenance`
  asks `symbolTableLookup` first (`analyzer.zig:89`). The only registration
  site is `symbol_registrator.zig:473-502`, which iterates module-root decls
  and never inserts fn locals, params, or captures. For real compiles the
  lookup always misses; the fallback (`analyzer.zig:100-111`) is the only live
  path. The fallback is conservative but cannot recover a missed name's real
  storage class except through seeded params or previously tracked values.
- **The dead path is what the unit tests exercise.** Hand-fed `Symbol{...}`
  records in `sf/src/tests/test_analyzer_bin.zig` make the symbol-table arm
  pass while the real pipeline never takes it (see §2.5).
- **`resolveOrigin` loses provenance through dereferences** (`:67`):
  `*ptr = &local; return *ptr` and `return (*p).field` are not caught. This is
  a documented limitation, but it means the "provenance" model is
  address-expression-local, not alias-aware.
- **Field-level assignments are not tracked** (`onLifetimeStmt` only handles
  `var_decl` / `plain_assign` with an ident LHS, `:1193-1210`).
- **Function results are always `heap`** (`:127`), regardless of the callee.
- **Dead-arm parity is incomplete.** `analyzerFoldComptimeBool`
  (`:1040-1071`) folds only bool literals, parens, `!`, `&&`, `||`; it does
  not fold integer comparisons (`1 == 0`), named bool consts, `@isWindows`,
  or the shared fold table. The `if`/`if_expr` walkers consult it
  (`:773-798`, `:1087-1103`), but `switch`/`swt_ex` prongs are never folded
  (`:1125-1142`). `phase_ComptimeEvaluation` runs before the analyzers
  (`main.zig:476`, `:483`) and populates `ctx.comptime_folds`; `AnalyzerContext`
  has no `comptime_folds` field (`analyzer.zig:518-544`) and
  `phase_StaticAnalyzers` never passes it (`main.zig:873-913`). Sema/lowering
  do consume it (`main.zig:838`, `lower.zig:8013`), so the analyzer is the
  odd one out.
- **Cross-mode re-walking.** `visitStatement` calls `analyzeExpr` on
  `if`/`while`/`switch` conditions regardless of the active analyzer mode
  (`analyzer.zig:1104`, `:1119`, `:1129`). `runLifetimeAnalyzer` and
  `runDoubleFreeAnalyzer` both run this code, so null diagnostics are emitted
  from non-null passes too (measured in §3 L2).

### 2.2 NullPointer

**Real path (works):**
- `analyzeExpr` checks `deref` against `classifyExpr` and emits `ERR_2004` /
  `WARN_6001` / `WARN_6002` (`analyzer.zig:729-747`).
- `classifyExpr` maps null/int literals, `address_of`, `try`, `fn_call`,
  `orelse`, `catch`, and tracked idents (`:834-854`).
- Guard detection and refinement (`detectNullGuard` `:874-901`,
  `applyNullGuardRefinement` `:903-914`) run in `if` statements
  (`:1107-1109`); capture binding marks null payloads `safe`
  (`bindCaptureState` `:1011-1013`).
- Definite null deref in an expression statement or condition is reported.

**Inert / incomplete paths:**
- **Parameters are not seeded.** `runNullAnalyzer` (`:1235-1241`) initializes
  an empty `StateMap` and walks the body; unlike `runLifetimeAnalyzer` it does
  not seed params. `classifyExpr` falls through to `maybe` on an unknown ident
  (`:849-853`), so every `param.*` in an unguarded context warns. This is the
  source of the self-source `WARN_6002` class.
- **`return` expressions are not walked.** `visitStatement`'s `return_stmt`
  arm (`:1149-1158`) calls `checkReturnProvenance` / `handleOwnershipReturn`
  but never `analyzeExpr(node.child_0)`. `/tmp` fixture `np_return_null.zig`
  (`var p: *u32 = null; return p.*;`) passes with rc=0.
- **`var` initializers are not walked.** `handleNullVarDecl` (`:916-926`)
  classifies the initializer to seed the binding but never calls `analyzeExpr`
  on it. `np_init_null.zig` (`var q: u32 = p.*` with `p = null`) passes with
  rc=0.
- **Assignment RHS is not walked for null.** `visitStatement`'s
  `plain_assign` branch (`:1168-1170`) calls `handleNullAssign`, which only
  classifies the RHS (`:928-937`). `np_assign_null.zig`
  (`q = p.*` with `p = null`) passes with rc=0.
- **Cross-mode emission.** As in §2.1, `analyzeExpr` is invoked from
  lifetime/double-free passes for `if`/`while`/`switch` conditions. Measured on
  self-source: the null pass emits 43 `WARN_6002`, the double-free pass emits
  the same 43, and the all-on run emits 86. A single-fixture check shows the
  same duplication (`np_cond.zig`: 1 with the null pass alone, 1 with
  double-free alone, 3 with all three).
- **No source attribution.** The null diagnostics pass
  `@intCast(u32, 0)` as `file_id` (`:739`, `:742`, `:745`); the renderer then
  prints only `warning[code]: message` with no file/line/caret
  (`diagnostics.zig:749-765`). `WARN_6005` also uses zero spans at
  `analyzer.zig:436` (`start = end = 0`).
- **Blanket `try` / `catch` are `safe`** (`classifyExpr:840`, `:842-843`).
  That matches the design's alloc-oriented table, but it is unsound for a
  `try`/`catch` whose success payload is an optional; the current analyzer
  cannot represent that shape, so it is a latent silent-pass class rather than
  a demonstrated one.

### 2.3 DoubleFree

**Real path (works):**
- Allocation tracking: `isAllocCall` (`analyzer.zig:240-262`) recognizes
  `sandAlloc`, `sand_alloc`, `arena_alloc`, `gpaAlloc`, `gpaAllocZeroed`
  (including through `try`); `handleAllocCall` (`:391-394`) and
  `handleAllocAssign` (`:441-471`) set `allocated`.
- Free tracking: `isFreeCall` (`:264-283`) recognizes `arena_free`, `sandFree`,
  `gpaFree`; `handleFreeCall` (`:396-424`) reports `ERR_2005` for `freed` and
  `WARN_6006` for absent state.
- Leaks: `checkLeaksOnScopeExit` (`:426-439`) and overwrite-leak detection in
  `handleAllocAssign` (`:449-458`).
- Use-after-free: `reportUseAfterFree` / `checkUseAfterFreeExpr`
  (`:311-389`).
- Ownership return/pass: `handleOwnershipReturn` (`:473-483`) and
  `handleOwnershipPass` (`:485-511`).
- Capture aliases: `bindCaptureState` inherits `allocated` and marks the
  origin `transferred` (`:1018-1031`). True `free(p); free(p)` is reported.

**Inert / incomplete paths:**
- **Alias assignments do not propagate state.** `handleAllocAssign` sets any
  non-alloc, non-null RHS to `unknown` (`:463-470`). `var q = p;` therefore
  drops `p`'s `allocated` state for `q`; the `var_decl` path in
  `onDoubleFreeStmt` calls only `handleAllocCall` (`:1215-1217`), so aliases
  declared in initializers never inherit either. `bindCaptureState` fixes the
  same problem only for payload captures. D4 probe: `sandFree(s,p);
  sandFree(s,q)` emits `warning[3039]` for `q` and no `ERR_2005` for the real
  double free.
- **Free recognition is ident-only.** `isFreeCall` returns the name only when
  the pointer argument is a bare `ident_expr` (`:279-282`). Frees through a
  field or array element (`sandFree(s, st.p)`, `sandFree(s, arr[0])`) return
  `null`; no state is updated and no double free is reported. `/tmp` fixtures
  `df_field.zig` and `df_index.zig` both pass with rc=0.
- **Allocation destinations are ident-only.** `handleAllocAssign` returns
  early unless the LHS is an `ident_expr` (`:446`); allocations stored into
  fields/elements are untracked.
- **Ownership pass is over-eager.** `handleOwnershipPass` treats every
  identifier argument of every `fn_call` as an ownership transfer when the
  argument is `allocated` (`:485-511`). Passing the allocator handle `s` to
  `sandFree(s, p)` marks `s` `transferred` and emits `INFO_7001`, which also
  suppresses its leak. Demonstrated by `dead_const.zig` / `df_field.zig`
  (`info[3040] ownership of 's' transferred`).
- **State overwrite is lossy.** In `handleFreeCall`, a `transferred` or
  `returned_val` name falls through to `freed` (`:415`) instead of being
  diagnosed or kept untracked; an `unknown` state is silently set `freed`.
  Freed values are not distinguished from non-owned pointers.
- **Dead-arm parity is absent.** `switch` prongs are never folded
  (`:1125-1142`), and `analyzerFoldComptimeBool` misses integer comparisons,
  named consts, `@isWindows`, and the shared table (`:1040-1071`). D4 probe's
  `if (1 == 0)` double free is a false `ERR_2005`; `/tmp` `dead_const.zig`
  (`const K = false`) and `dead_switch.zig` (dead `0 =>` prong) reproduce the
  same false error.
- **No source attribution** for its diagnostics (all `file_id = 0`; leak
  span zero at `:436`).

### 2.4 Signature

**Real path (works):**
- `analyzeSignature` walks every parameter and the return type
  (`analyzer.zig:562-579`); `rejectAnytypeType` recurses through wrappers and
  fn-ptr lists (`:589-626`); `validateSignatureNamed` checks incomplete types,
  direct-parameter `void`, and >64-byte returns (`:631-677`); the recursive
  `validateSignatureType` handles `optional_type`, `error_union_type`,
  `ptr_type`/`many_ptr_type`/`slice_type`/`array_type`, `fn_type`, and
  `field_access` (`:679-727`); arbitrary-width ints are accepted in the
  uncached-name branch (`:660-669`).
- D4 probe's Signature surface (`?Aggregate`, `E!Aggregate`, `i7`/`u48`/`i3`)
  is clean.
- Only `ERR_2012` uses the real `ctx.source_file_id` (`:600`, `:675`); the
  other signature diagnostics use `file_id = 0`. `ERR_2013` is never emitted,
  by design.

**Residue (no analyzer-logic inert path found):**
- `ERR_2013_OPAQUE_NOT_SUPPORTED` exists but has no emitter (documented).
- The rest of the D4 Signature item is the test/doc set below.

### 2.5 Test harness and docs residue

- **`testFixture` counts only aggregate errors/warnings, not codes.** It
  accepts `err_spec` / `warn_spec` and checks `diag.error_count` /
  `diag.warning_count` (`sf/src/tests/test_analyzer_bin.zig:1717-1792`). A
  fixture cannot assert "exactly one `WARN_6002` and no other warning".
- **Fixtures are hard-coded.** Only the files listed in `main()` run
  (`:1851-1859`); there is no directory manifest or generic CLI entry. The D4
  probe is not registered (ADJ-20).
- **Hand-fed-symbol unit tests are vacuous for the real pipeline.** The
  analyzer tests insert `Symbol{...}` records directly (e.g. `:545`, `:571`,
  `:640`, `:667`, `:694`, `:726`), exercising the symbol-table arm that real
  compiles never take for locals/params. Only `:1511` sets `file_id`; the rest
  omit it (`file_id` is zero-filled by zig1, but zig0 would reject).
- **Docs residue:** `docs/design/static_analyzers.md` still contains
  C++-era prose and the old diagnostic names; `docs/sf/STATIC_ANALYZERS_p2.md`
  §5.3 has the aspirational slice row (the current code reports `WARN_6011`
  for a slice of a local array, but the design table's other rows and the
  pseudo-code are not a faithful description); `docs/tech_debt/static_analyzers.md`
  §4.2 still records the old 44 measurement text.

---

## 3. Lie list — confident-but-wrong, vacuous, and silent-pass classes

The old anchor was **44 false `WARN_6002` on the compiler self-source**. At
`c84abdbf` the measurement is:

```sh
# From /tmp (output path independent; warnings count is the metric):
Z=/workspace/znineeight/zig1/zig1_5_clean
$Z -ffast --check -I /workspace/znineeight/sf/src \
   /workspace/znineeight/sf/src/main.zig 2>&1 \
   | grep -o 'warning\[[0-9]*\]' | sort | uniq -c
#      86 warning[3037]     (= WARN_6002)
#      13 warning[18]       (= WARN_7010 large return; not D4)
```

The 86 is **not 86 sites**. Isolating the passes:

```sh
$Z -ffast --check --no-lifetime-check --no-leak-check ...   # null only
#      43 warning[3037]
$Z -ffast --check --no-null-check --no-lifetime-check ...   # double-free only
#      43 warning[3037]
$Z -ffast --check --no-null-check --no-leak-check ...       # lifetime only
#       0 warning[3037]
```

So the current null-pass `WARN_6002` count is **43**; the all-analyzers run
doubles it to **86** because the double-free pass re-emits the null
diagnostics. The old 44 anchor's exact command was not recorded in the Task 5
report (a known minor), so the audit records both numbers: 43 for the
null-pass class and 86 for the current raw all-pass count. The 43 are the
documented unseeded-parameter class; the historical measurement called that
class false. We did not instrument per-site
truth (the diagnostics carry no `file_id`), so Task 9's target is stated as
"no param-deref false positives" and "raw count must not move into another
class", plus a per-site justification for any residual after seeding. The
`warning[18]` count (13) is `WARN_7010` and out of D4.

| ID | Diagnostic / class | What is wrong | Repro evidence |
|---|---|---|---|
| **L1** | `WARN_6002` on non-optional pointer parameters | Parameters are not seeded in the null state map; `p.*` on `*T` is reported `maybe` | `np_cond.zig`: 3 warnings for one `p.*`; self-source 43 null-pass / 86 raw (pass-class counts, not unique sites); D4 probe 2 warnings for one walked condition |
| **L2** | `WARN_6002` duplicated across passes | `analyzeExpr` runs in every analyzer mode from `visitStatement` conditions; the double-free pass re-emits the null warning | Self-source: null-only 43, double-free-only 43, all 86. `np_cond.zig`: null-only 1, lifetime-only 1, double-free-only 1, all 3. Probe: all 2, isolated 1+1+0 |
| **L3** | `WARN_6006 freeing untracked pointer 'q'` on an alias | `var q = p` does not inherit `p`'s `allocated` state; `q` looks untracked | D4 probe emits `warning[3039]` for `q`; the same chain's real double free is not reported (L8) |
| **L4** | `ERR_2005` in a comptime-dead arm | The analyzer walks both arms of evaluator-foldable conditions and every switch prong | D4 probe `if (1 == 0)` → `error[3035]`; `dead_const.zig` (`const K = false`) and `dead_switch.zig` (dead prong) → `error[3035]` |
| **L5** | `INFO_7001 ownership transferred` for an allocator handle / any call argument | `handleOwnershipPass` marks every allocated ident argument as transferred | `dead_const.zig`, `df_field.zig`: `info[3040] ownership of 's' transferred` even though `s` is the allocator argument to `sandFree` |
| **L6** | Silent `return p.*` | Return expressions are not walked by the null analyzer | `np_return_null.zig` (`p = null; return p.*`) rc=0, no `ERR_2004`; D4 probe `np_false_negative` also silent |
| **L7** | Silent `var q = p.*` / `q = p.*` | Initializers and assignment RHS are not walked | `np_init_null.zig` and `np_assign_null.zig` (`p = null`) rc=0, no `ERR_2004` |
| **L8** | Silent alias-chain double free | Alias assignment loses the allocation state; free through `q` is only "untracked" | D4 probe: `free(p); free(q)` yields no `ERR_2005` |
| **L9** | Silent free through a field/index | `isFreeCall` only accepts a bare ident pointer argument | `df_field.zig` (`sandFree(s, st.p)` twice) and `df_index.zig` (`sandFree(s, arr[0])` twice) rc=0, no `ERR_2005` |
| **L10** | Silent dead-arm divergence beyond `if` | `switch` prongs are never folded and the fold does not consult the shared table | `dead_switch.zig`; `dead_const.zig`; design `docs/tech_debt/static_analyzers.md` §4.1 |
| **L11** | Vacuous diagnostics (no location) | Null/lifetime/double-free emit `file_id = 0`; `WARN_6005` uses zero spans; the renderer prints no file/line/caret | `analyzer.zig:739/742/745`, `:436`; `diagnostics.zig:749-765`. The D4 probe's 5 diagnostics have no source location |
| **L12** | Vacuous tests / docs | Aggregate-only `testFixture`, hard-coded fixture list, hand-fed `Symbol` tests on a path the real pipeline never takes, docs residue | `sf/src/tests/test_analyzer_bin.zig:545/571/640/667/694/726`, `:1717-1792`, `:1851-1859`; `docs/design/static_analyzers.md`; `docs/sf/STATIC_ANALYZERS_p2.md` §5.3; `docs/tech_debt/static_analyzers.md` §4.2 |
| **L13** | Silent untracked allocators / frees | Recognition is a fixed name whitelist; other allocator APIs are invisible | `analyzer.zig:240-262` (alloc names), `:264-283` (free names); no diagnostic for unrecognized alloc/free |

**Signature lies:** none found on the probed surface. The Signature analyzer is
the only one of the four with no confident-wrong output in this audit; its
defects are test/doc residue (L12).

---

## 4. Bar and must-work set for Task 9

### 4.1 Bar

Task 9 is done when the analyzers are *real* on the must-work set, not when a
warning count moves:

1. **Sound on the must-work shapes.** No `WARN_6002` on non-optional pointer
   parameters; no `ERR_2005` in a proven-dead arm; no `INFO_7001` for an
   allocator handle; no false `WARN_6006` for a tracked alias.
2. **Complete on the must-work defects.** Every known real defect in §3 that
   the design promises to catch is reported: `return p.*`, `var q = p.*`,
   assignment-RHS deref, alias-chain double free, field/index frees, and the
   true lifetime positives.
3. **One diagnostic per defect.** No cross-pass duplicates; a single-source
   defect yields a single diagnostic (a genuine null and a genuine double free
   at the same site would be two different codes, but the same code must not
   repeat).
4. **Source-attributed diagnostics.** Analyzer diagnostics carry the module's
   `source_file_id` and a non-zero span where the design promises location
   (at minimum null/lifetime/double-free and leak diagnostics). This makes
   fixture assertions and live triage possible.
5. **Fold parity.** The analyzers consume the shared
   `ComptimeFoldTable`/evaluator fold that sema/lowering consume, gate `if`
   arms and `switch` prongs, and keep live-arm diagnostics.
6. **No emission change.** Analyzers are post-sema; emitted `.c`/`.h` is
   byte-identical to the pre-Task-9 baseline for corpus/stdlib/examples.
7. **Self-source target.** The 43-class false `WARN_6002` collapses (not
   moves): after seeding, no self-source warning comes from a non-optional
   pointer parameter; all-pass raw count equals the single-null-pass count
   (no cross-mode duplication); any residual is individually justified in the
   Task 9 report.
8. **Fixture-driven tests replace hand-fed symbols.** `tests/analyzers/**`
   fixtures drive the real pipeline and assert exact diagnostic codes/counts;
   the vacuous hand-fed-symbol behavior tests are retired or reduced to pure
   helper tests, and `Symbol` test initializers set `file_id`.

### 4.2 Must-work set (binding)

| ID | Requirement | Fixture (new/existing under `tests/analyzers/`) | Expected assertion |
|---|---|---|---|
| **NP-1** | Seed non-optional pointer-like parameters (`*T`, `[*]T`, `[]T`, fn-ptr) as `safe`; optional params remain conservative until refined | `np_param_safe.zig` | 0 `WARN_6002` for `p.*` on `*T` |
| **NP-2** | Walk `return` expressions through `analyzeExpr` | `np_return_null.zig` | `ERR_2004` for `p = null; return p.*` |
| **NP-3** | Walk `var` initializers and assignment RHS through `analyzeExpr` | `np_init_null.zig`, `np_assign_null.zig` | `ERR_2004` for `p = null; var q = p.*` and `q = p.*` |
| **NP-4** | Emit null diagnostics only from the null pass (or gate `analyzeExpr` by mode) | `np_single_deref.zig` (one guarded/unseeded deref) | exactly one `WARN_6002`, not 2/3 |
| **NP-5** | Keep guard/capture refinement and the true positive set | existing `capture_lifetime.zig`, new `np_guard_ok.zig` | no warning after `if (p != null)` / `if (p) |q|`; `ERR_2004` for a proved-null deref |
| **DF-1** | Propagate allocation state on identifier RHS for `var` init and assignment; maintain an alias relation, including the capture shape `var p = alloc; var op = p; if (op) \|q\| ...` | `df_alias_chain.zig`, existing `capture_double_free.zig`, new `df_capture_alias_chain.zig` (exact defect-c shape) | `ERR_2005` for `free(p); free(q)` after `var q = p`; `ERR_2005` for the second free through the capture alias; no `WARN_6006` |
| **DF-2** | Resolve frees through field/index/member chains (at least the alias chain the design promises) | `df_field.zig`, `df_index.zig` | `ERR_2005` on the second free; no false `INFO_7001` for the allocator handle |
| **DF-3** | Make ownership-pass precise: only real ownership-taking call sites transfer; allocator handles are not transferred | `df_owner_handle.zig` | no `INFO_7001` for `sandFree(s, p)`; leak/double-free state remains correct |
| **DF-4** | Do not silently convert `transferred`/`returned_val`/`unknown` to `freed` on free | `df_transferred_free.zig` | documented diagnostic or no state loss; no false `ERR_2005`/silent pass |
| **DED-1** | Plumb `ctx.comptime_folds` into `AnalyzerContext` and consult it in `analyzerFoldComptimeBool` | `dead_arm_const.zig` | no `ERR_2005` for `const K = false; if (K)` |
| **DED-2** | Gate `switch` prongs using the folded selector/table | `dead_arm_switch.zig` | no `ERR_2005` in the dead prong; the live prong still reports |
| **LIFE-1** | Keep the true positives and capture propagation green | existing `capture_lifetime.zig`, probe `lifetime_local` | `ERR_2020` for `return &x`; `WARN_6010` for capture-through-local |
| **LIFE-2** | Either register fn locals/params/captures in a front-end scope map or formally delete the dead symbol-table arm; tests must exercise the real path | new `lifetime_param.zig`, `lifetime_local.zig` | `return p` on `*T` safe; `return &p` `ERR_2021`; no hand-fed symbols |
| **SIG-1** | Keep the Signature surface clean and assert it by code | existing `surface_types.zig`, `fnptr_opt_aggregate.zig` + new `sig_arb_width.zig` | 0 diagnostics on valid shapes; `ERR_2011`/`ERR_2012`/`ERR_2010`/`WARN_7010` on their negative shapes |
| **DX-1** | Carry `source_file_id` and non-zero spans in null/lifetime/double-free/leak diagnostics | any fixture, harness reads spans | diagnostic location matches the fixture line; no `file_id = 0` for analyzer output |
| **TEST-1** | Fixture harness asserts exact diagnostic codes/counts, discovers `tests/analyzers/**`, and registers the D4 probe | harness change + probe | `d4_contract_probe.zig` runs through `testFixture`; expected code list matches |

Items NP-1..NP-4, DF-1, DED-1/DED-2, LIFE-1, and TEST-1 are the minimum for
the bar. DED-1 and DED-2 are assigned to Task 9a (shared infrastructure), not
left for a later sub-task. DF-2/DF-3/DF-4 and DX-1 are the next tranche; Task 9
should state which it lands and which it defers, but must not leave a must-work
item silently passing.

### 4.3 Fixture-driven test strategy

1. **Replace the aggregate-count `testFixture` with a code-aware harness.**
   Keep `testFixture(path, name, expected: []DiagnosticExpectation)` where each
   expectation is `{code, count}` or `{code, file, line}`. The D4 probe and
   every new fixture get a hard assertion, not `warning_count >= 1`.
2. **Add a fixture manifest.** A small table in `test_analyzer_bin.zig`
   (path → expected expectations) replaces the hand-maintained call list;
   globbing at test time is optional, but a missing fixture must fail.
3. **Drive the real pipeline.** The existing `testFixture` already lexes,
   parses, and runs `runAllAnalyzers`; keep that. Remove the hand-fed
   `Symbol{...}` behavior tests that only pass because the test inserts the
   symbol (L12), or rewrite them as pure helper tests (`classifyExpr`,
   `StateMap` merge) that do not claim pipeline coverage.
4. **Add the probe.** Register `tests/analyzers/d4_contract_probe.zig` with the
   post-Task-9 expectation set. Its current five diagnostics are the
   regression oracle: the two null warnings must collapse to the one genuine
   (or zero after parameter seeding), the untracked `q` must become the real
   `ERR_2005`, the dead-arm `ERR_2005` must disappear, and `ERR_2020` for
   `return &x` must stay.
5. **Self-source measurement as a separate check.** Run the `--check` command
   from §3 with all passes and with `--no-null-check --no-lifetime-check`;
   assert the two `warning[3037]` counts are equal (no cross-pass duplication)
   and that the param-class count is zero. Record the command and output in
   the Task 9 report (the Task 5 report lacked this and was flagged as a
   minor).
6. **No-emission proof.** After the analyzer changes, capture emitted C for
   the gate/corpus set before/after and assert a zero diff; analyzers are
   post-sema, so any diff is a regression, not an expected mover.
7. **Fix the test rot while there:** set `file_id` on every `Symbol` test
   initializer; retire/annotate the zig0-era docs residue per the plan's (f)
   item; keep `docs/design/static_analyzers.md` untouched as the zig0-era
   spec residue (spec §5.5 deferral) unless the plan says otherwise.

---

## 5. Measurements and repro index

All commands were run at `c84abdbf` with the committed
`/workspace/znineeight/zig1/zig1_5_clean` (ELF 32-bit). `/tmp` fixtures are
throwaway reproductions; the committed repros remain
`tests/analyzers/d4_contract_probe.zig` and the Task 0 fixtures under
`repro/mi_matrix/`.

| Repro | Command | Observed |
|---|---|---|
| D4 probe | `zig1_5_clean -ffast --check tests/analyzers/d4_contract_probe.zig` | rc=2; 2× `warning[3037]`, `warning[3039] 'q'`, `error[3035] 'p'`, `error[3030] 'x'` |
| Probe, null only | `--no-lifetime-check --no-leak-check` | 1× `warning[3037]` only; no `error[3030]` |
| Probe, lifetime only | `--no-null-check --no-leak-check` | 0× `warning[3037]`; `error[3030] 'x'` |
| Probe, double-free only | `--no-null-check --no-lifetime-check` | 1× `warning[3037]`, 1× `warning[3039] 'q'`, 1× `error[3035] 'p'`; no `error[3030]` |
| Self-source, all | `--check -I sf/src sf/src/main.zig` | rc=0; 86× `warning[3037]`, 13× `warning[18]` |
| Self-source, null only | add `--no-lifetime-check --no-leak-check` | 43× `warning[3037]` |
| Self-source, double-free only | add `--no-null-check --no-lifetime-check` | 43× `warning[3037]` |
| Self-source, lifetime only | add `--no-null-check --no-leak-check` | 0× `warning[3037]` |
| Return deref | `np_return_null.zig` (`var p: *u32 = null; return p.*`) | rc=0, no diagnostic |
| Init deref | `np_init_null.zig` (`var q: u32 = p.*`) | rc=0, no diagnostic |
| Assign deref | `np_assign_null.zig` (`q = p.*`) | rc=0, no diagnostic |
| Dead `if` (literal) | D4 probe `if (1 == 0)` | false `error[3035]` |
| Dead `if` (const) | `dead_const.zig` (`const K = false; if (K)`) | false `error[3035]` |
| Dead `switch` prong | `dead_switch.zig` (`switch (1) { 0 => … }`) | false `error[3035]` |
| Alias chain | D4 probe `var q = p; free(p); free(q)` | `warning[3039]` for `q`; no `ERR_2005` |
| Field free | `df_field.zig` (`sandFree(s, st.p)` twice) | rc=0; only false `info[3040]` for `s` |
| Index free | `df_index.zig` (`sandFree(s, arr[0])` twice) | rc=0; only false `info[3040]` for `s` |
| Ownership handle | `dead_const.zig` / `df_field.zig` | false `info[3040] ownership of 's' transferred` |

---

## 6. Open concerns / handoff notes

1. **The 43-vs-44 self-source count is a class count, not a per-site truth
   count.** The analyzer diagnostics have `file_id = 0`, so per-site
   classification requires Task 9's DX-1 change. Task 9 must not simply
   suppress `WARN_6002` at the parameter sites; it must seed parameters and
   then measure again.
2. **Cross-mode duplication is a separate bug from the false positive.** Do
   not fix L1 by lowering the warning level or filtering by message; fix the
   walk/mode gating and the duplication together (NP-4).
3. **The fold table is already available, and Task 9a owns DED-1/DED-2.**
   `phase_ComptimeEvaluation` runs before `phase_StaticAnalyzers`; the missing
   piece is the `AnalyzerContext.comptime_folds` field and the `main.zig`
   wiring. Task 9a explicitly owns both DED-1 (plumb and consult the fold
   table) and DED-2 (`switch`-prong gating), per the plan's Task 9a
   Interfaces. A `switch` fold path may need a selector table/evaluator call
   beyond a plain `comptimeFoldTableGet` (sema's own comment at
   `semantic_analyzer.zig:4179` notes foldable switch selectors may have no
   table entry), so DED-2 is not just a table pass-through.
4. **DF-3 (ownership precision) changes warning/info volume on live code.**
   It is in the must-work list because the false `INFO_7001` suppresses leaks;
   Task 9 should land it with a before/after self-source and corpus
   measurement, not silently.
5. **`docs/design/static_analyzers.md` is zig0-era and stays untouched** per
   the plan/spec §5.5 deferral; only `docs/sf/STATIC_ANALYZERS_p2.md` §5.3 and
   `docs/tech_debt/static_analyzers.md` are in Task 9's docs cleanup.
