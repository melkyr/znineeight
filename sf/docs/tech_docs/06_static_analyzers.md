# 06 — Static Analyzers

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Analyzer passes | 4 | Signature, Null, Lifetime, Double-Free |
| `PtrState` variants | 4 | `uninit`, `is_null`, `safe`, `maybe` |
| `Provenance` variants | 6 | `unknown`, `local`, `param`, `param_addr`, `global`, `heap` |
| `AllocState` variants | 6 | `untracked`, `allocated`, `freed`, `returned_val`, `transferred`, `unknown` |
| `StateMap` ops | 5 | `init`, `get`, `set`, `fork`, `mergeStates` |
| StateMap parent linking | delta-chain | Fork creates empty child → parent link; get walks up chain |
| Merge strategy | conservative | Mismatch → `unknown_state` (99) |
| Alloc call detection | 3 fn names | `sandAlloc`, `sand_alloc`, `arena_alloc` |
| Free call detection | 2 fn names | `arena_free`, `sandFree` |
| `PER_FUNC_BUDGET` | 524,288 | 512KB sand peak limit per function |

---

## analyzer.zig (`sf/src/analyzer.zig`, 803 lines)

4 independent analyzer passes in phase 6. Each runs per-function with a fresh `StateMap` and resets the scratch arena between passes.

---

### DeferEntry (`sf/src/analyzer.zig:18-22`)

```zig
pub const DeferEntry = struct {
    kind: u8,        // 0 = defer_stmt, 1 = errdefer_stmt
    stmt_idx: u32,   // AST node index of the defer/errdefer statement
    scope_depth: u32,
};
```

Tracked in `AnalyzerContext.defer_queue_items[]`. Used by `walkBlock` to execute deferred statements on scope exit.

---

### PtrState enum (`sf/src/analyzer.zig:24-29`)

| Variant | Meaning |
|---------|---------|
| `uninit` | Pointer was declared without init |
| `is_null` | Pointer is provably null |
| `safe` | Pointer is provably non-null (address_of, try, orelse, catch) |
| `maybe` | Pointer could be null (fn call return, unknown) |

Used by the null analyzer to track pointer nullity through `StateMap`.

---

### Provenance enum (`sf/src/analyzer.zig:31-38`)

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

### AllocState enum (`sf/src/analyzer.zig:40-47`)

| Variant | Meaning |
|---------|---------|
| `untracked` | Not known to be an allocation |
| `allocated` | Currently allocated (after sandAlloc/arena_alloc) |
| `freed` | Has been freed (after arena_free/sandFree) |
| `returned_val` | Allocated pointer was returned from function |
| `transferred` | Ownership was passed to another function |
| `unknown` | State after overwrite with unknown value |

State machine for the double-free analyzer. Transitions:
- `init → untracked`
- `alloc call → allocated`
- `free call on allocated → freed`
- `free call on freed → ERR_2005_DOUBLE_FREE`
- `free call on untracked → WARN_6006_FREEING_UNTRACKED`
- `return of allocated → returned_val`
- `pass allocated to fn → transferred`
- `overwrite allocated → WARN_6005_MEMORY_LEAK`
- `scope exit with allocated → WARN_6005_MEMORY_LEAK`

---

### NullGuard struct (`sf/src/analyzer.zig:354-357`)

```zig
pub const NullGuard = struct {
    name_id: u32,
    is_not_null: u8,  // 1 = safe in then, 0 = safe in else
};
```

Result of `detectNullGuard`. Captures a variable nullity condition from `if`/`while` conditions (`x != null`, `x == null`, bare `x`, `!x`).

---

### AnalyzerContext struct (`sf/src/analyzer.zig:359-377`)

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
};
```

Passed as `ctx` throughout. Controls which analyzers run via `skip_*` flags and `null_analysis_mode`.

---

### resolveOrigin (`sf/src/analyzer.zig:49-59`)

`[inference: follow field_access/index_access/slice_expr chain to root identifier's name_id]`

Walks the AST upward through field accesses and index accesses to find the root identifier. Returns `null` on deref (pointer indirection severs the chain). Used by `classifyProvenance` and `checkReturnProvenance` to determine what variable an expression ultimately refers to.

---

### classifyProvenance (`sf/src/analyzer.zig:61-100`)

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

### checkReturnProvenance (`sf/src/analyzer.zig:102-170`)

`[inference: classifyProvenance → if local → check address_of/slice_expr/ident → emit ERR_2020/WARN_6011/WARN_6010; if param_addr → emit ERR_2021]`

Validates that function return expressions don't create dangling references:
- `Prov.local + address_of → ERR_2020_RETURNING_ADDRESS_OF_LOCAL` (error)
- `Prov.local + slice_expr → WARN_6011_RETURNING_SLICE_OF_LOCAL` (warning)
- `Prov.local + ident_expr → WARN_6010_RETURNING_POINTER_VIA_VARIABLE` (warning)
- `Prov.param_addr → ERR_2021_RETURNING_ADDRESS_OF_PARAM` (error)

---

### isAllocCall (`sf/src/analyzer.zig:172-190`)

`[inference: unwrap try_expr → check fn_call + ident_expr callee → match name_id against sandAlloc/sand_alloc/arena_alloc]`

Returns `true` if an expression is a call to any recognized allocation function.

---

### isFreeCall (`sf/src/analyzer.zig:192-209`)

`[inference: check fn_call + ident_expr callee → match arena_free/sandFree → extract first arg's name_id]`

Returns `?u32` — the `name_id` of the pointer being freed, or `null` if not a free call.

---

### compositeNameId (`sf/src/analyzer.zig:211-233`)

`[inference: join base.field as "base_str.field_str" → intern and return name_id]`

Creates composite identifier strings for struct field tracking (e.g. `foo.bar`). Used to distinguish field-level provenance.

---

### handleAllocCall (`sf/src/analyzer.zig:235-238`)

`[inference: isAllocCall guard → stateMapSet(name_id, AllocState.allocated)]`

Marks a variable as allocated. Called from `onDoubleFreeStmt` for `var_decl` with alloc init.

---

### handleFreeCall (`sf/src/analyzer.zig:240-268`)

`[inference: isFreeCall → current state → allocated→freed; freed→ERR_2005_DOUBLE_FREE; untracked→WARN_6006_FREEING_UNTRACKED]`

State machine transition on free. Emits diagnostics for double-free (error) and freeing untracked pointers (warning).

---

### checkLeaksOnScopeExit (`sf/src/analyzer.zig:270-283`)

`[inference: stateMapGetEntries → any state == AllocState.allocated → WARN_6005_MEMORY_LEAK]`

Called at the end of `walkBlock` after executing defer queue. Reports any allocations that were never freed.

---

### handleAllocAssign (`sf/src/analyzer.zig:285-314`)

`[inference: if LHS was allocated → WARN_6005_MEMORY_LEAK (overwritten); then classify RHS → alloc call→allocated, null→untracked, else→unknown]`

Handles assignments that might overwrite a previously allocated pointer (leak), or transfer a new allocation.

---

### handleOwnershipReturn (`sf/src/analyzer.zig:316-326`)

`[inference: if ret_expr is ident_expr and state == allocated → set returned_val]`

Marks an allocated pointer as returned (transfers ownership out of function).

---

### handleOwnershipPass (`sf/src/analyzer.zig:328-352`)

`[inference: iterate fn_call args → if allocated → set transferred + INFO_7001_OWNERSHIP_TRANSFERRED]`

Marks allocated pointers passed as arguments as ownership-transferred. Warning level depends on `ctx.warn_all`.

---

### deferQueueEnsureCapacity (`sf/src/analyzer.zig:379-390`)

`[inference: grow-by-doubling from min 8, memcpy DeferEntry array]`

Grows the defer queue (parallel arena from `ctx.defer_queue_alloc`) when full.

---

### analyzeSignature (`sf/src/analyzer.zig:392-407`)

`[inference: iterate param types → validateSignatureType; validate return type]`

First pass over function signatures. Validates parameter types and return type for completeness.

---

### validateSignatureType (`sf/src/analyzer.zig:409-447`)

`[inference: ident_expr → nameCacheGet → type-kind dispatch → incomplete type/void param/anytype/large return checks]`

Checks performed:
- `unresolved_name` or incomplete `struct_type`/`union_type`/`tagged_union_type`/`enum_type` → `ERR_2011_INCOMPLETE_TYPE`
- `void_type` as param → `ERR_2010_VOID_PARAMETER`
- `size > 64` on return type → `WARN_7010_LARGE_RETURN`
- `anytype` ident → `ERR_2012_ANYTYPE_NOT_SUPPORTED`

---

### analyzeExpr (`sf/src/analyzer.zig:449-497`)

`[inference: AstKind dispatch → recursive child analysis → state updates for null tracking]`

| Kind | Action |
|------|--------|
| `deref` | `classifyExpr` on child → if `is_null` → ERR_2004, if `uninit` → WARN_6001, if `maybe` → WARN_6002 |
| `index_access` | recurse on child_0 |
| `field_access` | recurse on child_0 |
| `fn_call` | recurse on all args |
| `plain_assign` | recurse on rhs, `classifyExpr` rhs → `stateMapSet` lhs |
| other | recurse children 0-2 |

Core expression analysis for null tracking. Updates `StateMap` on assignments so subsequent expressions see refined states.

---

### classifyExpr (`sf/src/analyzer.zig:499-519`)

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

### isNullExpr / isIdentExpr (`sf/src/analyzer.zig:521-537`)

`[inference: match AstKind.null_literal or int_literal(0) → return u8 bool]`

`[inference: match AstKind.ident_expr → return name_id]`

Helpers used by `detectNullGuard` to pattern-match null comparisons.

---

### detectNullGuard (`sf/src/analyzer.zig:539-566`)

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

### applyNullGuardRefinement (`sf/src/analyzer.zig:568-579`)

`[inference: detectNullGuard → set then_state/else_state PtrState accordingly]`

If `is_not_null`: `then_state → safe`, `else_state → is_null`.
If `is_null`: `then_state → is_null`, `else_state → safe`.

Called from `visitStatement` when `null_analysis_mode` is active, before forking into if/else blocks.

---

### handleNullVarDecl (`sf/src/analyzer.zig:581-591`)

`[inference: classifyExpr(init) → stateMapSet(name_id, st); if no init → stateMapSet(name_id, uninit)]`

Initializes null tracking state for variable declarations. Called from `visitStatement` for `var_decl` nodes.

---

### handleNullAssign (`sf/src/analyzer.zig:593-602`)

`[inference: classifyExpr(rhs) → stateMapSet(lhs.name_id, rhs_state)]`

Updates null tracking state on assignments. Only handles `ident_expr` LHS.

---

### executeDeferQueue (`sf/src/analyzer.zig:604-616`)

`[inference: pop entries from end while scope_depth >= target_depth → execute kind==0 always, kind==1 only if is_error]`

Executes deferred statements on scope exit. Normal defers (kind=0) always run; errdefers (kind=1) only run if `is_error != 0`.

---

### walkBlock (`sf/src/analyzer.zig:618-635`)

`[inference: increment depth → visit child statements → execute defer queue at saved depth → check leaks → restore depth]`

Entry point for analyzing a block of statements. Manages scope depth, defers, and leak detection on scope exit.

---

### visitStatement (`sf/src/analyzer.zig:637-698`)

`[inference: AstKind dispatch — handles branching (fork+merge), loops, switch, return, defer, null analysis, fallback]`

| Kind | Action |
|------|--------|
| `if_stmt`/`if_capture` | evaluate cond → fork then_state/else_state → optional `applyNullGuardRefinement` + if_capture safe → walkBlock each → `stateMapMergeStates(state, then, else, 99)` |
| `while_stmt`/`while_capture` | evaluate cond → fork body_state → optional while_capture safe → walkBlock → `stateMapMergeStates(state, state, body, 99)` |
| `swt_ex` | per-prong: fork → walkBlock → `stateMapMergeStates(state, state, ps, 99)` |
| `for_stmt` | fork body_state → walkBlock → `stateMapMergeStates(state, state, body, 99)` |
| `return_stmt` | if child: `checkReturnProvenance` + `handleOwnershipReturn` → on_stmt |
| `defer_stmt`/`errdefer_stmt` | push to defer_queue |
| `var_decl` (null mode) | `handleNullVarDecl` → on_stmt |
| `plain_assign` (null mode) | `handleNullAssign` → on_stmt |
| `expr_stmt` | `analyzeExpr` only |
| other | on_stmt |

Central statement dispatch for all analyzers. The null analysis if/else/loop state forking logic is the most complex part — each path gets a forked `StateMap`, and after both paths execute, `stateMapMergeStates` computes a conservative merge.

---

### onNullStmt (`sf/src/analyzer.zig:700-702`)

`[inference: no-op]`

Placeholder statement handler for the null analyzer. All null analysis is done inline in `visitStatement`.

---

### onLifetimeStmt (`sf/src/analyzer.zig:704-721`)

`[inference: var_decl → classifyProvenance(init) → stateMapSet; plain_assign → classifyProvenance(rhs) → stateMapSet(lhs)]`

Statement handler for the lifetime analyzer. Tracks provenance on variable declarations and assignments via `classifyProvenance`.

---

### onDoubleFreeStmt (`sf/src/analyzer.zig:723-734`)

`[inference: var_decl → handleAllocCall; plain_assign → handleAllocAssign; fn_call → handleOwnershipPass]`

Statement handler for the double-free analyzer. Routes to the appropriate alloc-state transition function.

---

### runSignatureAnalyzer (`sf/src/analyzer.zig:736-738`)

`[inference: delegate to analyzeSignature(fn_decl_idx)]`

Thin entry point that calls `analyzeSignature` on the function declaration node.

---

### runNullAnalyzer (`sf/src/analyzer.zig:740-745`)

`[inference: stateMapInit → set null_analysis_mode → walkBlock with onNullStmt → clear null_analysis_mode]`

Entry point for the null pointer analysis pass. Creates a fresh `StateMap`, enables null tracking, walks the function body, then disables null tracking.

---

### runLifetimeAnalyzer (`sf/src/analyzer.zig:747-763`)

`[inference: stateMapInit → iterate params → stateMapSet(param, Provenance.param) → walkBlock with onLifetimeStmt]`

Entry point for the lifetime/dangling-pointer analysis pass. Pre-populates the `StateMap` with parameter provenance (`param`), then walks the body tracking provenance assignments.

---

### runDoubleFreeAnalyzer (`sf/src/analyzer.zig:765-768`)

`[inference: stateMapInit → walkBlock with onDoubleFreeStmt]`

Entry point for the double-free/memory-leak analysis pass. Creates a fresh `StateMap` and walks the function body.

---

### runAllAnalyzers (`sf/src/analyzer.zig:772-803`)

`[inference: iterate module_root decls → skip non-fn_decl + no-body → sandResetPeak → runSignatureAnalyzer → sandReset → [optional runNullAnalyzer → sandReset] → [optional runLifetimeAnalyzer → sandReset] → [optional runDoubleFreeAnalyzer → sandReset] → check peak vs PER_FUNC_BUDGET]`

Orchestrates all 4 analyzers across every function in the module:

0. **Pre-pass**: `alloc_mod.sandResetPeak(ctx.alloc)` — track sand peak per function
1. **`runSignatureAnalyzer`** — validates function signature types
2. **`runNullAnalyzer`** — null pointer analysis (skip if `skip_null_check`)
3. **`runLifetimeAnalyzer`** — dangling pointer analysis (skip if `skip_lifetime_check`)
4. **`runDoubleFreeAnalyzer`** — double-free / memory leak analysis (skip if `skip_doublefree_check`)
5. **Budget check**: if `ctx.alloc.peak > PER_FUNC_BUDGET` → `WARN_7002_ANALYZER_BUDGET_EXCEEDED`

Each pass resets the scratch arena (`alloc_mod.sandReset`) after completion, so per-function peak is measured independently. The budget check happens after all passes complete for that function.

---

## state_map.zig (`sf/src/state_map.zig`, 109 lines)

### StateEntry (`sf/src/state_map.zig:4-7`)

```zig
pub const StateEntry = struct {
    name_id: u32,
    state: u8,
};
```

### StateMap (`sf/src/state_map.zig:9-15`)

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

### stateMapInit (`sf/src/state_map.zig:17-25`)

`[inference: return StateMap with zero entries, null parent, no alloc]`

Creates an empty root StateMap. Used at the start of each analyzer pass.

---

### stateMapGet (`sf/src/state_map.zig:39-47`)

`[inference: reverse scan own entries for name_id → if found return state → else recurse on parent → null]`

Walk order: own entries (reverse), then parent chain. This means child overrides parent for the same name_id.

---

### stateMapSet (`sf/src/state_map.zig:49-60`)

`[inference: scan own entries → if name_id exists, update state in-place → else ensure capacity → append new entry]`

Updates or inserts an entry in the current level. Does NOT propagate to parent — the delta pattern means only the current fork's changes are stored locally.

---

### stateMapFork (`sf/src/state_map.zig:62-71`)

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

### stateMapMergeStates (`sf/src/analyzer.zig:73-105`)

`[inference: iterate branch_a entries, iterate branch_b entries → if a_state != b_state → set parent with unknown_state; else set parent with common state; if only in a or only in b → check parent for divergence]`

Conservative merge of two branch states back into parent:

```
For each entry in branch_a:
  if also in branch_b:
    if a == b → set parent to that state
    if a != b → set parent to unknown_state (99)
  if only in branch_a:
    if parent has entry and parent != a → set parent to unknown_state

For each entry in branch_b not in branch_a:
  if parent has entry and parent != b → set parent to unknown_state
```

The `unknown_state` parameter is always `99`, which represents a "merged" or "uncertain" state. This is conservative — if either branch disagrees, the merged state becomes unknown.

---

### stateMapGetEntries (`sf/src/state_map.zig:107-109`)

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
       ├─ For each fn_decl with body:
       │
       │  ┌─ sandResetPeak (track per-function budget)
       │  │
       │  ├─ runSignatureAnalyzer(fn_decl_idx)
       │  │   └─ analyzeSignature → validateSignatureType per param + return
       │  │
       │  ├─ sandReset
       │  │
       │  ├─ [if !skip_null_check] runNullAnalyzer(body_idx)
       │  │   └─ StateMap → walkBlock → visitStatement(if/while forking + merging)
       │  │       ├─ classifyExpr → PtrState for deref checks
       │  │       ├─ detectNullGuard + applyNullGuardRefinement
       │  │       └─ stateMapMergeStates for branch convergence
       │  │
       │  ├─ sandReset
       │  │
       │  ├─ [if !skip_lifetime_check] runLifetimeAnalyzer(decl_idx, body_idx)
       │  │   └─ StateMap (pre-populated with param provenances)
       │  │       └─ walkBlock → onLifetimeStmt
       │  │           ├─ classifyProvenance → resolveOrigin → symbolTableLookup
       │  │           └─ stateMapSet with Provenance variant
       │  │       └─ checkReturnProvenance on return statements
       │  │
       │  ├─ sandReset
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
  ├─ defer_queue (DeferEntry[], scope-managed)
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

### PER_FUNC_BUDGET = 512KB (`sf/src/analyzer.zig:770`)

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

| Marker | File | Line | Meaning |
|--------|------|------|---------|
| `A` | main.zig | — | Start of static analysis phase |

Note: unlike other phases, the static analyzers produce minimal trace markers. Most debugging is done via diagnostic output (error/warning codes).

### Error/Warning Codes

| Code | Severity | Condition |
|------|----------|-----------|
| `ERR_2004_DEFINITE_NULL_DEREF` | error | Dereference of provably-null pointer |
| `ERR_2005_DOUBLE_FREE` | error | Freeing already-freed pointer |
| `ERR_2010_VOID_PARAMETER` | error | `void` used as parameter type |
| `ERR_2011_INCOMPLETE_TYPE` | error | Incomplete type in function signature |
| `ERR_2012_ANYTYPE_NOT_SUPPORTED` | error | `anytype` in signature |
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
