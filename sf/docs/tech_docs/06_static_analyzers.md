# 06 — Static Analyzers [updated: 2026-09-28 — FX8 (Volume II defect fix, `labeled_stmt` traversal): `visitStatement` gains a `labeled_stmt` arm that unwraps the statement and routes `child_0` through the same statement walk — a labeled block reaches `walkBlock`; a labeled loop/switch reaches the matching arm — so labeled blocks/loops get the FX2 treatment (defer enqueue at the walked `current_depth` and drain at their own scope exit, leak check, null/lifetime/double-free visibility). Measured: an allocation leak inside a labeled block (probe f1, silent on the FX2/FX7 compiler) now reports `warning[3038]` (x2: label-block exit + function exit); a leak in a labeled loop body reports `warning[3038]` x1; a null deref inside a labeled block/loop reports `error[3034]` + `warning[3037]` (rc 2); a double free split across a labeled block reports `error[3035]` (rc 2); a free after a labeled block no longer warns `warning[3039]`. Labeled statements are now fully traversed (remaining untraversed statement classes: prong case items, deferred statement bodies). A free split across a labeled LOOP is silent (`freed` + `allocated` -> `unknown`, the pre-existing loop merge — not FX8). Runtime behavior unchanged (lowering owns defer execution). Fixtures `repro/mi_matrix/stdlib_analyzer_labeled_xmod` (stdlib pin 262 -> 263) + `repro/mi_matrix/analyzer_labeled_reject_xmod` + standalone `repro/labeled_analyzer.z98` / `repro/labeled_analyzer_reject.z98`; fixed point `ff059647856e5c223c1622d1b031579b` -> `4e76f5a4268486d6deae080cebf89978` (hop1 == hop2, explicit gate); 4-MD5 emitted-C UNCHANGED 8/8 both modes; corpus zero class movers.] [updated: 2026-09-28 — FX7 (Volume II defect fix, switch-merge prong-name propagation): the `swt_ex` arm merges each prong with the existing conservative merge and, in the double-free pass only, inserts prong-only names into the enclosing state as `AllocState.unknown` via the new `stateMapMergeInsertMissing` (`sf/src/state_map.zig`). The join is the contract's divergent-state value: "maybe allocated in this prong, untracked on the others" — neither `allocated` (no spurious leak) nor absent/untracked (no spurious `WARN_6006`). A pointer first assigned `arena_alloc` in a prong and freed after the switch is now tracked (a second post-switch free is a definite `error[3035]`). The if/while/for merges are unchanged; the null/lifetime maps are unchanged because every enclosing variable is already seeded at its declaration/param binding there, so a prong-only name is necessarily prong-local (propagating it would track a dead binding). Fixtures `repro/mi_matrix/stdlib_analyzer_switch_merge_xmod` (stdlib pin 261 -> 262) + `repro/mi_matrix/analyzer_switch_merge_reject_xmod` + standalone `repro/switch_merge.z98` / `repro/switch_merge_reject.z98`; fixed point `1a258bd4bcb5194fc3256be0be456311` -> `ff059647856e5c223c1622d1b031579b` (hop1 == hop2, explicit gate); 4-MD5 emitted-C UNCHANGED 8/8 both modes; corpus 1065 = 907 OK / 52 GREEN / 106 FAIL, zero class movers over the 1063 common dirs; gate-program stderr byte-identical.] [updated: 2026-09-27 — FX2 (Volume II defect fix, D1 extras): `visitStatement` now traverses switch-prong and bare-block statements. The `swt_ex` arm first analyzes the condition (preserving the previous `expr_stmt(swt_ex)` condition route) and then walks every prong body through the existing fork -> walkBlock -> merge; the `expr_stmt` arm detects a statement-switch wrapper and recurses `visitStatement(swt_ex)`; a bare `block` statement routes through `walkBlock` (depth increment, defer enqueue/drain at its own block exit, leak check). Defers inside prongs/blocks now reach the null/lifetime/double-free passes; runtime behavior is unchanged (analyzer-only). Accepted movement: duplicate bare-block `WARN_6005`; lisp `WARN_6002` counts +58/+73/+85 (`lisp_interpreter_adv/curr/upgraded` only, zero other warning movers over 1055 corpus dirs; zero error movement); FX7 (switch-merge prong-name propagation) and FX8 (`labeled_stmt`) stay out of scope. Fixtures `repro/mi_matrix/stdlib_defer_switch_block_xmod` (stdlib pin 256 -> 257) + standalone `repro/defer_traversal.z98`; fixed point `98cd68f4a4f99b520f663d6964673e67` -> `325f741f0326ebaf177a0503e000312a` (hop1 == hop2); 4-MD5 emitted-C UNCHANGED. FX2-only traversal SIGSEGVs without FG (the newly queued prong defers reach the stale queue), so it lands after `resetDeferQueue`.] [updated: 2026-09-26 — FG (Volume II defect fix, D1): new `resetDeferQueue` (analyzer.zig) clears the defer queue's `items/len/cap` and is called immediately after each of the four per-phase/per-function `sandReset` sites in `runAllAnalyzers`, so the queue can no longer alias recycled scratch memory that a live `StateMap` now occupies; fixes the D1 SIGSEGV (`checkLeaksOnScopeExit` / `stateMapMergeStates`) for a plain-`defer` fn plus a nested-block-`defer` fn in one module. Bookkeeping-only (the queue is drained at every block exit); fixture `repro/mi_matrix/stdlib_defer_queue_reset_xmod`; fixed point `6b68ca72…` -> `c4f10f9e2d33a0833b9882c5dad2539b` (hop1 == hop2); 4-MD5 UNCHANGED] [updated: 2026-09-20 — refreshed against current analyzer/StateMap source; removed line refs and dated evidence]

> Covers: `analyzer.zig`, `state_map.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Analyzer passes | 4 | Signature, Null, Lifetime, Double-Free |
| `PtrState` variants | 4 | `uninit`, `is_null`, `safe`, `maybe` |
| `Provenance` variants | 6 | `unknown`, `local`, `param`, `param_addr`, `global`, `heap` |
| `AllocState` variants | 6 | `untracked`, `allocated`, `freed`, `returned_val`, `transferred`, `unknown` |
| `StateMap` ops | 7 | `init`, `get`, `set`, `fork`, `mergeStates`, `mergeInsertMissing`, `getEntries` |
| StateMap parent linking | delta-chain | Fork creates empty child → parent link; get walks up chain |
| Merge strategy | conservative | Mismatch → `unknown_state` (99) |
| Alloc call detection | 3 fn names | `sandAlloc`, `sand_alloc`, `arena_alloc` |
| Free call detection | 2 fn names | `arena_free`, `sandFree` |
| `PER_FUNC_BUDGET` | 524,288 | 512KB sand peak limit per function |

---

## analyzer.zig (`sf/src/analyzer.zig`, 864 lines)

4 independent analyzer passes in phase 6. Each runs per-function with a fresh `StateMap` and resets the scratch arena between passes.

---

### DeferEntry (`sf/src/analyzer.zig`)

```zig
pub const DeferEntry = struct {
    kind: u8,        // 0 = defer_stmt, 1 = errdefer_stmt
    stmt_idx: u32,   // AST node index of the defer/errdefer statement
    scope_depth: u32,
};
```

Tracked in `AnalyzerContext.defer_queue_items[]`. Used by `walkBlock` to execute deferred statements on scope exit.

---

### PtrState enum (`sf/src/analyzer.zig`)

| Variant | Meaning |
|---------|---------|
| `uninit` | Pointer was declared without init |
| `is_null` | Pointer is provably null |
| `safe` | Pointer is provably non-null (address_of, try, orelse, catch) |
| `maybe` | Pointer could be null (fn call return, unknown) |

Used by the null analyzer to track pointer nullity through `StateMap`.

---

### Provenance enum (`sf/src/analyzer.zig`)

| Variant | Meaning |
|---------|---------|
| `unknown` | Cannot determine origin |
| `local` | Points to a local variable |
| `param` | Is a function parameter |
| `param_addr` | Address of a function parameter |
| `global` | Points to a global |
| `heap` | Comes from an allocation |

Used by the lifetime analyzer to track where pointers originate. Checked by `checkReturnProvenance` to prevent returning dangling references.

---

### AllocState enum (`sf/src/analyzer.zig`)

| Variant | Meaning |
|---------|---------|
| `untracked` | Not known to be an allocation |
| `allocated` | Currently allocated (after sandAlloc/arena_alloc) |
| `freed` | Has been freed (after arena_free/sandFree) |
| `returned_val` | Allocated pointer was returned from function |
| `transferred` | Ownership was passed to another function |
| `unknown` | State after overwrite with unknown value |

State machine for the double-free analyzer. Transitions:
- `assign null_literal → untracked`
- `alloc call → allocated`
- `free call on allocated → freed`
- `free call on freed → ERR_2005_DOUBLE_FREE`
- `free call on a name with no state entry → WARN_6006_FREEING_UNTRACKED`
- `free call on any other tracked state → freed` (no diagnostic)
- `return of allocated → returned_val`
- `pass allocated to fn → transferred`
- `overwrite allocated → WARN_6005_MEMORY_LEAK`
- `scope exit with allocated → WARN_6005_MEMORY_LEAK`

---

### NullGuard struct (`sf/src/analyzer.zig`)

```zig
pub const NullGuard = struct {
    name_id: u32,
    is_not_null: u8,  // 1 = safe in then, 0 = safe in else
};
```

Result of `detectNullGuard`. Captures a variable nullity condition from `if`/`while` conditions (`x != null`, `x == null`, bare `x`, `!x`).

---

### AnalyzerContext struct (`sf/src/analyzer.zig`)

```zig
pub const AnalyzerContext = struct {
    store: *AstStore,
    registry: *TypeRegistry,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    symbols: *SymbolTable,
    alloc: *Sand,
    current_fn_name: u32,
    defer_queue_items: [*]DeferEntry,
    defer_queue_len: usize,
    defer_queue_cap: usize,
    defer_queue_alloc: *Sand,
    current_depth: u32,
    null_analysis_mode: u8,
    skip_null_check: u8,
    skip_lifetime_check: u8,
    skip_doublefree_check: u8,
    warn_all: u8,
    on_stmt_cb: fn(*AnalyzerContext, *StateMap, u32) void,
    in_defer_exec: u8,
    lifetime_analysis_mode: u8,
    doublefree_analysis_mode: u8,
};
```

Passed as `ctx` throughout. Controls which analyzers run via `skip_*` flags and `null_analysis_mode`.

---

### resolveOrigin (`sf/src/analyzer.zig`)

`[inference: follow field_access/index_access/slice_expr chain to root identifier's name_id]`

Walks the AST upward through field accesses and index accesses to find the root identifier. Returns `null` on deref (pointer indirection severs the chain). Used by `classifyProvenance` and `checkReturnProvenance` to determine what variable an expression ultimately refers to.

---

### classifyProvenance (`sf/src/analyzer.zig`)

`[inference: AstKind dispatch → symbol lookup → StateMap lookup → Provenance variant]`

| Input Kind | Mechanism | Result |
|------------|-----------|--------|
| `address_of` | resolveOrigin → symbolTableLookup | local/param_addr/global/unknown |
| `fn_call` | direct | `heap` |
| `field_access` | resolveOrigin → stateMapGet | stored provenance or unknown |
| `slice_expr` | resolveOrigin → stateMapGet | stored provenance or unknown |
| `ident_expr` | stateMapGet | stored provenance or unknown |
| other | — | `unknown` |

Called by the lifetime analyzer to determine pointer provenance.

---

### checkReturnProvenance (`sf/src/analyzer.zig`)

`[inference: classifyProvenance → if local → check address_of/slice_expr/ident → emit ERR_2020/WARN_6011/WARN_6010; if param_addr → emit ERR_2021]`

Validates that function return expressions don't create dangling references:
- `Prov.local + address_of → ERR_2020_RETURNING_ADDRESS_OF_LOCAL` (error)
- `Prov.local + slice_expr → WARN_6011_RETURNING_SLICE_OF_LOCAL` (warning)
- `Prov.local + ident_expr → WARN_6010_RETURNING_POINTER_VIA_VARIABLE` (warning)
- `Prov.param_addr → ERR_2021_RETURNING_ADDRESS_OF_PARAM` (error)

---

### isAllocCall (`sf/src/analyzer.zig`)

`[inference: unwrap try_expr → check fn_call + ident_expr callee → match name_id against sandAlloc/sand_alloc/arena_alloc]`

Returns `true` if an expression is a call to any recognized allocation function.

---

### isFreeCall (`sf/src/analyzer.zig`)

`[inference: check fn_call + ident_expr callee → match arena_free/sandFree → extract first arg's name_id]`

Returns `?u32` — the `name_id` of the pointer being freed, or `null` if not a free call.

---

### compositeNameId (`sf/src/analyzer.zig`)

`[inference: join base.field as "base_str.field_str" → intern and return name_id]`

Creates composite identifier strings for struct field tracking (e.g. `foo.bar`). Used to distinguish field-level provenance.

---

### handleAllocCall (`sf/src/analyzer.zig`)

`[inference: isAllocCall guard → stateMapSet(name_id, AllocState.allocated)]`

Marks a variable as allocated. Called from `onDoubleFreeStmt` for `var_decl` with alloc init.

---

### handleFreeCall (`sf/src/analyzer.zig`)

`[inference: isFreeCall → current state → allocated→freed; freed→ERR_2005_DOUBLE_FREE; no entry→WARN_6006_FREEING_UNTRACKED; other tracked→freed]`

State machine transition on free. Emits diagnostics for double-free (error) and freeing untracked pointers (warning).

---

### checkLeaksOnScopeExit (`sf/src/analyzer.zig`)

`[inference: stateMapGetEntries → any state == AllocState.allocated → WARN_6005_MEMORY_LEAK]`

Called at the end of `walkBlock` after executing defer queue. Reports any allocations that were never freed.

---

### handleAllocAssign (`sf/src/analyzer.zig`)

`[inference: if LHS was allocated → WARN_6005_MEMORY_LEAK (overwritten); then classify RHS → alloc call→allocated, null→untracked, else→unknown]`

Handles assignments that might overwrite a previously allocated pointer (leak), or transfer a new allocation.

---

### handleOwnershipReturn (`sf/src/analyzer.zig`)

`[inference: if ret_expr is ident_expr and state == allocated → set returned_val]`

Marks an allocated pointer as returned (transfers ownership out of function).

---

### handleOwnershipPass (`sf/src/analyzer.zig`)

`[inference: iterate fn_call args → if allocated → set transferred + INFO_7001_OWNERSHIP_TRANSFERRED]`

Marks allocated pointers passed as arguments as ownership-transferred. Warning level depends on `ctx.warn_all`.

---

### deferQueueEnsureCapacity (`sf/src/analyzer.zig`)

`[inference: grow-by-doubling from min 8, memcpy DeferEntry array]`

Grows the defer queue (parallel arena from `ctx.defer_queue_alloc`) when full.

---

### resetDeferQueue (`sf/src/analyzer.zig`)

`[inference: defer_queue_items = undefined; defer_queue_len = 0; defer_queue_cap = 0]`

Drops the defer queue's stale bookkeeping (items pointer + length + capacity). Called
immediately after each of the four `alloc_mod.sandReset(ctx.alloc)` sites in
`runAllAnalyzers` (after the signature pass and after each optional pass), because the
queue lives in the scratch arena that `sandReset` recycles. The queue is drained at every
block exit (`executeDeferQueue` from `walkBlock`), so it is empty between
functions/phases and the reset is a semantic no-op that only kills the stale pointer —
without it, the next `DeferEntry` write (`:713`) reused the stale capacity and overlaid
recycled scratch memory that now held a live `StateMap` (D1 SIGSEGV).

---

### analyzeSignature (`sf/src/analyzer.zig`)

`[inference: iterate param types → validateSignatureType + rejectAnytypeType; validate return type + rejectAnytypeType]`

First pass over function signatures. Validates parameter types and return type for completeness, then runs the recursive `anytype` reject over the same type nodes.

### validateSignatureType (`sf/src/analyzer.zig`)

`[inference: ident_expr → nameCacheGet → type-kind dispatch → incomplete type/void param/anytype/large return checks]`

Checks performed:
- `unresolved_name` or incomplete `struct_type`/`union_type`/`tagged_union_type`/`enum_type` → `ERR_2011_INCOMPLETE_TYPE`
- `void_type` as param → `ERR_2010_VOID_PARAMETER`
- `size > 64` on return type → `WARN_7010_LARGE_RETURN`
- `anytype` ident → `ERR_2012_ANYTYPE_NOT_SUPPORTED` (deduped via `diagnosticCollectorMarkNodeOnce`; A1-F passes the module's real `ctx.source_file_id`, so it renders `file:line:col` + caret). Direct ident only — nested/wrapped `anytype` is handled by `rejectAnytypeType`.

---

### rejectAnytypeType (`sf/src/analyzer.zig`)

`[inference: recurse the type-expression tree; on an ident_expr named 'anytype' emit ERR_2012 once per node]`

A1-F helper called from `analyzeSignature` for every parameter type and the return node. Walks `ptr_type`/`many_ptr_type`/`slice_type`/`optional_type`/`array_type` (child_0), `error_union_type` (child_0 + child_1) and `fn_type` (child_0 return + payload extra children) to reach each leaf, emitting level-0 `ERR_2012_ANYTYPE_NOT_SUPPORTED` (`error[16]`) with the leaf span and `ctx.source_file_id`, deduped via the shared `diagnosticCollectorMarkNodeOnce` (one diagnostic per node; the parser's S1 `anytype` sentinel re-activated the previously-dead check).

---

### analyzeExpr (`sf/src/analyzer.zig`)

`[inference: AstKind dispatch → recursive child analysis → state updates for null tracking]`

| Kind | Action |
|------|--------|
| `deref` | `classifyExpr` on child → if `is_null` → ERR_2004, if `uninit` → WARN_6001, if `maybe` → WARN_6002 |
| `index_access` | recurse on child_0 |
| `field_access` | recurse on child_0 |
| `fn_call` | recurse on all args |
| `builtin_call` | recurse on all args |
| `plain_assign` | recurse on rhs, `classifyExpr` rhs → `stateMapSet` lhs (ident lhs only) |
| other | recurse children 0-2 |

Core expression analysis for null tracking. Updates `StateMap` on assignments so subsequent expressions see refined states.

---

### classifyExpr (`sf/src/analyzer.zig`)

`[inference: AstKind dispatch → return PtrState variant]`

| Kind | PtrState |
|------|----------|
| `null_literal` | `is_null` |
| `int_literal(0)` | `is_null` |
| `address_of` | `safe` |
| `try_expr` | `safe` |
| `orelse_expr` | `safe` |
| `catch_expr` | `safe` |
| `fn_call` | `maybe` |
| `ident_expr` | `stateMapGet` or `maybe` |
| other int_literal | `safe` |
| fallback | `maybe` |

Classifies any expression into a `PtrState`. Used by `analyzeExpr` for deref checks and by `visitStatement` for var decl/assign handling.

---

### isNullExpr / isIdentExpr (`sf/src/analyzer.zig`)

`[inference: match AstKind.null_literal or int_literal(0) → return u8 bool]`

`[inference: match AstKind.ident_expr → return name_id]`

Helpers used by `detectNullGuard` to pattern-match null comparisons.

---

### detectNullGuard (`sf/src/analyzer.zig`)

`[inference: condition AstKind dispatch → cmp_ne→NullGuard{is_not_null:1}, cmp_eq→{is_not_null:0}, ident→{is_not_null:1}, bool_not→invert inner guard]`

| Condition Form | Guard Result |
|----------------|--------------|
| `x != null` | `NullGuard{name_id=x, is_not_null=1}` |
| `null != x` | `NullGuard{name_id=x, is_not_null=1}` |
| `x == null` | `NullGuard{name_id=x, is_not_null=0}` |
| `null == x` | `NullGuard{name_id=x, is_not_null=0}` |
| `x` (ident) | `NullGuard{name_id=x, is_not_null=1}` |
| `!x` | `NullGuard{name_id=x, is_not_null=inverted}` |

Detects null-check patterns in `if`/`while` conditions so the null analyzer can refine pointer states in each branch.

---

### applyNullGuardRefinement (`sf/src/analyzer.zig`)

`[inference: detectNullGuard → set then_state/else_state PtrState accordingly]`

If `is_not_null`: `then_state → safe`, `else_state → is_null`.
If `is_null`: `then_state → is_null`, `else_state → safe`.

Called from `visitStatement` when `null_analysis_mode` is active, before forking into if/else blocks.

---

### handleNullVarDecl (`sf/src/analyzer.zig`)

`[inference: classifyExpr(init) → stateMapSet(name_id, st); if no init → stateMapSet(name_id, uninit)]`

Initializes null tracking state for variable declarations. Called from `visitStatement` for `var_decl` nodes.

---

### handleNullAssign (`sf/src/analyzer.zig`)

`[inference: classifyExpr(rhs) → stateMapSet(lhs.name_id, rhs_state)]`

Updates null tracking state on assignments. Only handles `ident_expr` LHS.

---

### executeDeferQueue (`sf/src/analyzer.zig`)

`[inference: pop entries from end while scope_depth >= target_depth → execute kind==0 always, kind==1 only if is_error]`

Executes deferred statements on scope exit. Normal defers (kind=0) always run; errdefers (kind=1) only run if `is_error != 0`.

---

### walkBlock (`sf/src/analyzer.zig`)

`[inference: increment depth → visit child statements → execute defer queue at saved depth → check leaks → restore depth]`

Entry point for analyzing a block of statements. Manages scope depth, defers, and leak detection on scope exit.

---

### visitStatement (`sf/src/analyzer.zig`)

`[inference: AstKind dispatch — handles branching (fork+merge), loops, switch, return, defer, null analysis, fallback]`

| Kind | Action |
|------|--------|
| `if_stmt`/`if_capture` | evaluate cond → fork then_state/else_state → optional `applyNullGuardRefinement` + if_capture safe → walkBlock each → `stateMapMergeStates(state, then, else, 99)` |
| `while_stmt`/`while_capture` | evaluate cond → fork body_state → optional while_capture safe → walkBlock → `stateMapMergeStates(state, state, body, 99)` |
| `swt_ex` | analyze condition (`analyzeExpr(child_0)`) → per-prong: fork → walkBlock → `stateMapMergeStates(state, state, ps, 99)`; double-free pass: `stateMapMergeInsertMissing(state, ps, unknown)` inserts prong-only names (FX7) |
| `for_stmt` | fork body_state → walkBlock → `stateMapMergeStates(state, state, body, 99)` |
| `return_stmt` | if child: `checkReturnProvenance` + `handleOwnershipReturn` → on_stmt |
| `defer_stmt`/`errdefer_stmt` | push to defer_queue |
| `var_decl` (null mode) | `handleNullVarDecl` → on_stmt |
| `plain_assign` (null mode) | `handleNullAssign` → on_stmt |
| `expr_stmt` | statement-switch wrapper (`child_0` kind `swt_ex`) → recurse `visitStatement`; else `analyzeExpr(child_0)` |
| `block` | `walkBlock` (depth increment, defer queue drain at block exit, leak check) |
| `labeled_stmt` | unwrap: recurse `visitStatement(child_0)` — labeled block → `walkBlock`; labeled loop/switch → the matching arm (FX8) |
| other | on_stmt |

Central statement dispatch for all analyzers. The null analysis if/else/loop state forking logic is the most complex part — each path gets a forked `StateMap`, and after both paths execute, `stateMapMergeStates` computes a conservative merge.

#### Statement-traversal contract (FX2)

A statement `switch` is parsed as `expr_stmt(swt_ex)`
(`sf/src/parser.zig`). `visitStatement`'s `expr_stmt` arm detects that wrapper
and recurses through the `swt_ex` arm, which analyzes the condition first
(preserving the previous condition-only route) and then walks each prong body
with the shared fork/walkBlock/merge. A bare `block` statement routes through
`walkBlock`, so a defer inside it enqueues at the walked `current_depth` and
drains at its own block exit (LIFO) and the double-free pass leak-checks on
scope exit. This makes defers inside switch prongs and bare blocks visible to
all three optional analyzers; lowering alone owns defer execution, so runtime
behavior is unchanged.

Known limits (not changed by FX2):
- the `swt_ex` prong-only-name drop is **fixed by FX7** for the double-free
  pass (`stateMapMergeInsertMissing`; a prong-only name joins as
  `AllocState.unknown`, so post-switch frees stay tracked and a second free is
  `error[3035]`); the if/while/for merges still drop branch-only names;
- a bare block whose allocation leaks to function exit reports `WARN_6005`
  twice (inner block exit + function exit) — operator-accepted duplicate;
- analyzer diagnostics carry no source span (`file_id 0`);
- `labeled_stmt` bodies are traversed as of **FX8** (see below); prong case
  items and deferred statement bodies stay untraversed (`executeDeferQueue`
  re-enters with `in_defer_exec = 1`, so the defer arm skips);
- capture-safe marking for prong captures is deliberately skipped (an unmarked
  capture only reaches the conservative `WARN_6002` path).

FX2-only traversal must land after FG's `resetDeferQueue`: the newly queued
prong defers otherwise reach the stale queue pointer and SIGSEGV (measured:
FX2-only compiler rc 139 on the fixture/sibling shapes; FG+FX2 rc 0).

#### Labeled-statement traversal (FX8)

`visitStatement` unwraps `AstKind.labeled_stmt` and routes `child_0` through
the same statement walk, so a labeled block (`blk: { ... }`) reaches
`walkBlock` and a labeled loop (`lw: while (...)`) or labeled `for`/`switch`
reaches the matching arm — the same treatment FX2 gave bare blocks, switch
prongs and unlabeled loops. Defers inside labeled constructs enqueue at the
walked `current_depth` and drain at their own scope exit (so the runtime
ordering is lowering's, unchanged); the leak/null/lifetime/double-free
handlers see the body. Measured on the FX2/FX7 compiler vs the FX8 compiler:
labeled-block leak silent -> `warning[3038]` x2, labeled-loop leak silent ->
`warning[3038]` x1, null deref in a labeled block/loop silent -> `error[3034]`
+ `warning[3037]` (rc 2), double free split across a labeled block silent ->
`error[3035]` (rc 2), free-after-labeled-block `warning[3039]` -> no warning.
A free split across a labeled LOOP is silent on both compilers: the loop-body
fork/merge joins the body's `freed` with the enclosing `allocated` as
`unknown`, and a free of an `unknown` name is silent — the pre-existing loop
merge, not changed by FX8.

#### Detection Wiring

Each `run*Analyzer` entry point routes its statement handler through
`visitStatement` for control-flow-aware analysis instead of flat `walkBlock`
dispatch. A single wrapper function `detectorVisit` in `analyzer.zig` calls
`visitStatement(ctx, state, node_idx, ctx.on_stmt_cb, detectorVisit)`; each pass
stores its handler in `AnalyzerContext.on_stmt_cb`.

| Entry point | Statement handler | Diagnostics enabled |
|-------------|-------------------|---------------------|
| `runNullAnalyzer` | `onNullStmt` | ERR_2004, WARN_6001, WARN_6002 |
| `runLifetimeAnalyzer` | `onLifetimeStmt` | ERR_2020, ERR_2021, WARN_6010, WARN_6011 |
| `runDoubleFreeAnalyzer` | `onDoubleFreeStmt` | ERR_2005, WARN_6006, WARN_6005 |

Because `detectorVisit` recurses through `visitStatement`, nested control flow
(if/while/switch/for) is analyzed recursively. `onDoubleFreeStmt` additionally
calls `handleFreeCall` before `handleOwnershipPass` for fn_call nodes.

---

### onNullStmt (`sf/src/analyzer.zig`)

`[inference: no-op]`

Placeholder statement handler for the null analyzer. All null analysis is done inline in `visitStatement`.

---

### onLifetimeStmt (`sf/src/analyzer.zig`)

`[inference: var_decl → classifyProvenance(init) → stateMapSet; plain_assign → classifyProvenance(rhs) → stateMapSet(lhs)]`

Statement handler for the lifetime analyzer. Tracks provenance on variable declarations and assignments via `classifyProvenance`.

---

### onDoubleFreeStmt (`sf/src/analyzer.zig`)

`[inference: var_decl → handleAllocCall; plain_assign → handleAllocAssign; fn_call → handleFreeCall then handleOwnershipPass]`

Statement handler for the double-free analyzer. Routes to the appropriate alloc-state transition function.

---

### runSignatureAnalyzer (`sf/src/analyzer.zig`)

`[inference: delegate to analyzeSignature(fn_decl_idx)]`

Thin entry point that calls `analyzeSignature` on the function declaration node.

---

### runNullAnalyzer (`sf/src/analyzer.zig`)

`[inference: stateMapInit → set null_analysis_mode → walkBlock with onNullStmt → clear null_analysis_mode]`

Entry point for the null pointer analysis pass. Creates a fresh `StateMap`, enables null tracking, walks the function body, then disables null tracking.

---

### runLifetimeAnalyzer (`sf/src/analyzer.zig`)

`[inference: stateMapInit → iterate params → stateMapSet(param, Provenance.param) → walkBlock with onLifetimeStmt]`

Entry point for the lifetime/dangling-pointer analysis pass. Pre-populates the `StateMap` with parameter provenance (`param`), then walks the body tracking provenance assignments.

---

### runDoubleFreeAnalyzer (`sf/src/analyzer.zig`)

`[inference: stateMapInit → walkBlock with onDoubleFreeStmt]`

Entry point for the double-free/memory-leak analysis pass. Creates a fresh `StateMap` and walks the function body.

---

### runAllAnalyzers (`sf/src/analyzer.zig`)

`[inference: iterate module_root decls → skip non-fn_decl + no-body → sandResetPeak → runSignatureAnalyzer → sandReset + resetDeferQueue → [optional runNullAnalyzer → sandReset + resetDeferQueue] → [optional runLifetimeAnalyzer → sandReset + resetDeferQueue] → [optional runDoubleFreeAnalyzer → sandReset + resetDeferQueue] → check peak vs PER_FUNC_BUDGET]`

Orchestrates all 4 analyzers across every function in the module:

0. **Pre-pass**: `alloc_mod.sandResetPeak(ctx.alloc)` — track sand peak per function
1. **`runSignatureAnalyzer`** — validates function signature types
2. **`runNullAnalyzer`** — null pointer analysis (skip if `skip_null_check`)
3. **`runLifetimeAnalyzer`** — dangling pointer analysis (skip if `skip_lifetime_check`)
4. **`runDoubleFreeAnalyzer`** — double-free / memory leak analysis (skip if `skip_doublefree_check`)
5. **Budget check**: if `ctx.alloc.peak > PER_FUNC_BUDGET` → `WARN_7002_ANALYZER_BUDGET_EXCEEDED`

Each pass resets the scratch arena (`alloc_mod.sandReset`) after completion, so per-function peak is measured independently. Each reset is immediately followed by `resetDeferQueue(ctx)`: the queue is allocated from the same scratch arena, and clearing its `items/len/cap` kills the stale pointer before the next pass can reuse the capacity (D1 fix). The budget check happens after all passes complete for that function.

---

## state_map.zig (`sf/src/state_map.zig`, 109 lines)

### StateEntry (`sf/src/state_map.zig`)

```zig
pub const StateEntry = struct {
    name_id: u32,
    state: u8,
};
```

### StateMap (`sf/src/state_map.zig`)

```zig
pub const StateMap = struct {
    entries_items: [*]StateEntry,
    entries_len: usize,
    entries_cap: usize,
    entries_alloc: *Sand,
    parent: ?*StateMap,
};
```

Parent-linked delta map. A child fork is born empty — it only stores entries that differ from parent. `stateMapGet` walks up the parent chain on miss.

---

### stateMapInit (`sf/src/state_map.zig`)

`[inference: return StateMap with zero entries, null parent, no alloc]`

Creates an empty root StateMap. Used at the start of each analyzer pass.

---

### stateMapGet (`sf/src/state_map.zig`)

`[inference: reverse scan own entries for name_id → if found return state → else recurse on parent → null]`

Walk order: own entries (reverse), then parent chain. This means child overrides parent for the same name_id.

---

### stateMapSet (`sf/src/state_map.zig`)

`[inference: scan own entries → if name_id exists, update state in-place → else ensure capacity → append new entry]`

Updates or inserts an entry in the current level. Does NOT propagate to parent — the delta pattern means only the current fork's changes are stored locally.

---

### stateMapFork (`sf/src/state_map.zig`)

`[inference: alloc StateMap on scratch → zero init → parent=self → return child ptr]`

Creates a child `StateMap` on the scratch arena with a parent link to the current map. The child starts empty — all gets fall through to parent until overridden.

```
Fork pattern:
  parent (root, has {x: safe, y: maybe})
    └─ child (empty, parent=root)
         stateMapGet(child, x) → parent.x → safe
         stateMapSet(child, x, is_null)
         stateMapGet(child, x) → is_null  (local override)
         stateMapGet(child, y) → parent.y → maybe
```

---

### stateMapMergeStates (`sf/src/state_map.zig`)

`[inference: iterate branch_a entries, iterate branch_b entries → if a_state != b_state → set parent with unknown_state; else set parent with common state; if only in a or only in b → check parent for divergence]`

Conservative merge of two branch states back into parent:

```
For each entry in branch_a:
  if also in branch_b:
    if a == b → set parent to that state
    if a != b → set parent to unknown_state (99)
  if only in branch_a:
    if parent has entry and parent != a → set parent to unknown_state
    if parent has NO entry → NOTHING written (name dropped from merged map)

For each entry in branch_b not in branch_a:
  if parent has entry and parent != b → set parent to unknown_state
  if parent has NO entry → NOTHING written (name dropped from merged map)
```

The `unknown_state` parameter is always `99`, which represents a "merged" or "uncertain" state. This is conservative — if either branch disagrees, the merged state becomes unknown.

**⚠️ Precision loss — branch-only-declared variables:** when a name exists in
only one fork and the parent has no entry for it, `stateMapMergeStates`
**silently drops it** — the merge loops only write when
`stateMapGet(parent, name)` returns a value. After the merge,
`stateMapGet(parent, name)` returns `null`, so the variable's per-branch state
is lost entirely (it does not even degrade to `99`). By contrast, a
branch-only name whose parent entry *differs* becomes `unknown_state (99)`, and
one whose parent entry *matches* keeps the parent value. (The if/while/for
merges keep this behavior; the switch merge's double-free pass uses the
insert variant below — FX7.)

---

### stateMapMergeInsertMissing (`sf/src/state_map.zig`)

`[inference: for each branch-local entry absent from parent → stateMapSet(parent, name, insert_state)]`

Insert-on-merge variant used by the `swt_ex` arm after each prong's
`stateMapMergeStates` call, double-free pass only (FX7). For every name present
locally in the prong state and absent from the parent (and its chain), the
parent gets `insert_state` — the `AllocState.unknown` value for the
double-free map. This is the sound conservative join of "name written in this
prong" with "name untracked on the other prongs": the enclosing state tracks
the name (so a post-switch `arena_free` marks it freed instead of warning
`WARN_6006` untracked, and a second free reports `error[3035]`), but the value
is neither `allocated` (no spurious leak for the untaken prongs) nor
`freed`. The other analyzers do not call it: their maps seed every enclosing
variable at its declaration/param binding, so a prong-only name is a
prong-local binding whose entry dies with the prong.

---

### stateMapGetEntries (`sf/src/state_map.zig`)

`[inference: return slice of own entries_items[0..entries_len]]`

Returns only the current level's entries (not the full parent chain). Used by `checkLeaksOnScopeExit` to find allocations still marked as `allocated`.

---

## Data Flow

```
phase_StaticAnalyzers (main.zig)
  │
  └─ runAllAnalyzers(ctx, module_root_idx)
       │
       ├─ Iterate root module declarations
       │
       ├─ For each fn_decl with body (`decl.child_0 != 0`):
       │
       │  ┌─ sandResetPeak (track per-function budget)
       │  │
       │  ├─ runSignatureAnalyzer(fn_decl_idx)
       │  │   └─ analyzeSignature → validateSignatureType per param + return
       │  │
       │  ├─ sandReset
       │  ├─ resetDeferQueue (drop the stale scratch-arena queue pointer)
       │  │
       │  ├─ [if !skip_null_check] runNullAnalyzer(body_idx)
       │  │   └─ StateMap → walkBlock → visitStatement(if/while forking + merging)
       │  │       ├─ classifyExpr → PtrState for deref checks
       │  │       ├─ detectNullGuard + applyNullGuardRefinement
       │  │       └─ stateMapMergeStates for branch convergence
       │  │
       │  ├─ sandReset
       │  ├─ resetDeferQueue (drop the stale scratch-arena queue pointer)
       │  │
       │  ├─ [if !skip_lifetime_check] runLifetimeAnalyzer(decl_idx, body_idx)
       │  │   └─ StateMap (pre-populated with param provenances)
       │  │       └─ walkBlock → onLifetimeStmt
       │  │           ├─ classifyProvenance → resolveOrigin → symbolTableLookup
       │  │           └─ stateMapSet with Provenance variant
       │  │       └─ checkReturnProvenance on return statements
       │  │
       │  ├─ sandReset
       │  ├─ resetDeferQueue (drop the stale scratch-arena queue pointer)
       │  │
       │  ├─ [if !skip_doublefree_check] runDoubleFreeAnalyzer(body_idx)
       │  │   └─ StateMap → walkBlock → onDoubleFreeStmt
       │  │       ├─ handleAllocCall / handleAllocAssign
       │  │       ├─ handleFreeCall → AllocState transitions
       │  │       ├─ handleOwnershipReturn / handleOwnershipPass
       │  │       └─ checkLeaksOnScopeExit
       │  │
       │  └─ if peak > PER_FUNC_BUDGET → WARN_7002
       │
       └─ Continue to next function declaration
```

### Threading through `walkBlock` / `visitStatement`

```
Resolver types + AstStore + SymbolTable + Interner
  │
  ▼
AnalyzerContext (per-function orchestrator)
  │
  ├─ defer_queue (DeferEntry[], scope-managed; cleared by resetDeferQueue after each sandReset)
  ├─ null_analysis_mode (enables null tracking in visitStatement)
  ├─ skip_* flags (disable individual analyzers)
  │
  └─ StateMap (per-pass, parent-linked delta)
       ├─ entries[]: name_id → state byte
       ├─ parent: ?*StateMap (fork chain)
       │
       ├─ stateMapGet(name_id) → ?u8
       ├─ stateMapSet(name_id, state)
       ├─ stateMapFork → child StateMap
       └─ stateMapMergeStates(parent, a, b, unknown)
            │
            └─ Conservative: disagreeing branches → unknown_state (99)

DiagnosticCollector ← errors/warnings/info
```

---

## Debugging

### PER_FUNC_BUDGET = 512KB (`sf/src/analyzer.zig`)

Each function gets a 512KB scratch arena budget across all 4 analyzers. If `ctx.alloc.peak > PER_FUNC_BUDGET` after all passes run, `WARN_7002_ANALYZER_BUDGET_EXCEEDED` is emitted.

The budget is measured per-function because the scratch arena is reset (`sandReset`) between each analyzer pass and between each function. This means peak allocation across all passes for a single function determines budget compliance.

### Disabling individual analyzers

| Flag | Effect |
|------|--------|
| `ctx.skip_null_check = 1` | Skips `runNullAnalyzer` |
| `ctx.skip_lifetime_check = 1` | Skips `runLifetimeAnalyzer` |
| `ctx.skip_doublefree_check = 1` | Skips `runDoubleFreeAnalyzer` |

Set via CLI flags. Signature analyzer always runs (no skip flag).

### Key Markers for Tracing

| Marker | File | Meaning |
|--------|------|---------|
| `A` | main.zig | Start of the static analysis phase |

`analyzer.zig` and `state_map.zig` contain **zero** `markerWrite` calls — there
are no per-function/per-pass markers. The per-module/per-decl markers (`M`, `F`,
kind numbers) are emitted by `phase_LIRLowering` in `main.zig`, not by the
static analyzer phase.

Note: unlike other phases, the static analyzers produce no trace markers of
their own. Most debugging is done via diagnostic output (error/warning codes)
or direct GDB breakpoints on the analyzer entry points.

### Error/Warning Codes

| Code | Severity | Condition |
|------|----------|-----------|
| `ERR_2004_DEFINITE_NULL_DEREF` | error | Dereference of provably-null pointer |
| `ERR_2005_DOUBLE_FREE` | error | Freeing already-freed pointer |
| `ERR_2010_VOID_PARAMETER` | error | `void` used as parameter type |
| `ERR_2011_INCOMPLETE_TYPE` | error | Incomplete type in function signature |
| `ERR_2012_ANYTYPE_NOT_SUPPORTED` | error | `anytype` in a signature/type position (direct or nested; renders as `error[16]`, one per node, with file:line:col + caret — A1-F) |
| `ERR_2020_RETURNING_ADDRESS_OF_LOCAL` | error | Returning `&local` from function |
| `ERR_2021_RETURNING_ADDRESS_OF_PARAM` | error | Returning `&param` from function |
| `WARN_6001_UNINIT_DEREF` | warning | Dereference of uninitialized pointer |
| `WARN_6002_POTENTIAL_NULL_DEREF` | warning | Dereference of maybe-null pointer |
| `WARN_6005_MEMORY_LEAK` | warning | Allocated pointer not freed before scope exit or overwrite |
| `WARN_6006_FREEING_UNTRACKED` | warning | Freeing a pointer that wasn't tracked as allocated |
| `WARN_6010_RETURNING_POINTER_VIA_VARIABLE` | warning | Returning pointer-to-local through a variable |
| `WARN_6011_RETURNING_SLICE_OF_LOCAL` | warning | Returning slice of local array |
| `WARN_7002_ANALYZER_BUDGET_EXCEEDED` | warning | Per-function scratch arena peak exceeded 512KB |
| `WARN_7010_LARGE_RETURN` | warning | Return type exceeds 64 bytes |
| `INFO_7001_OWNERSHIP_TRANSFERRED` | info | Allocated pointer ownership transferred to callee |

### GDB Breakpoints

```gdb
# Entry to static analysis phase
break runAllAnalyzers

# Per-analyzer entry points
break runSignatureAnalyzer
break runNullAnalyzer
break runLifetimeAnalyzer
break runDoubleFreeAnalyzer

# Statement-level analysis
break visitStatement

# Null pointer analysis
break classifyExpr
break analyzeExpr
break detectNullGuard
break applyNullGuardRefinement

# Lifetime analysis
break classifyProvenance
break checkReturnProvenance
break resolveOrigin

# Double-free analysis
break isAllocCall
break isFreeCall
break handleFreeCall
break handleAllocAssign
break handleOwnershipReturn
break handleOwnershipPass
break checkLeaksOnScopeExit

# StateMap operations (state_map.zig)
break stateMapInit
break stateMapGet
break stateMapSet
break stateMapFork
break stateMapMergeStates
```

### Print commands for debugging

```gdb
# Print state map entries
print state.entries_items[0..state.entries_len]
print smap_mod.stateMapGet(state, name_id)

# Print analyzer context flags
print ctx.skip_null_check
print ctx.skip_lifetime_check
print ctx.skip_doublefree_check
print ctx.null_analysis_mode

# Print scratch arena peak
print ctx.alloc.peak
print PER_FUNC_BUDGET

# Print current function name
print interner_mod.stringInternerGet(ctx.interner, ctx.current_fn_name)

# Print defer queue state
print ctx.defer_queue_items[0..ctx.defer_queue_len]
print ctx.current_depth
```
