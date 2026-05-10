# Deep Dive: Example Regressions (rogue_mud & lisp_interpreter_curr)

This document outlines the investigation into why previously working examples are failing after recent compiler changes, specifically the memory arena split and pipeline refactoring.

## 1. rogue_mud: Undefined Type for 'res' in sand.zig

### Symptoms
Compilation of `rogue_mud` fails with a post-check assertion:
`Undefined type for symbol 'res' in module 'sand'`

### Root Cause Analysis
The investigation revealed a combination of three factors causing this regression:

1.  **Double-Visit Bug**: `visitVarDecl` contained an early-return check that triggered if a symbol already had a type. Since local variables are now "pre-inserted" into the symbol table with `TYPE_UNDEFINED` during the first pass of a block, this check caused the compiler to skip the actual inference logic on the subsequent "main" visit to the same declaration.
2.  **Initializer Deferral Gap**: In the line `const res = sand.start + aligned_pos;`, the initializer is a `NODE_BINARY_OP`. `visitVarDecl` has logic to defer resolution if the initializer returns `TYPE_UNDEFINED` (which happens if a dependency like `sand.start` is temporarily unresolved). However, this deferral was only enabled for `if`, `switch`, and anonymous initializers. `NODE_BINARY_OP` was not covered, leading to a permanent `TYPE_UNDEFINED` assignment if resolution wasn't instantaneous.
3.  **AST Transience (Arena Split)**: Because `sand.zig` is a common utility, it is processed as an imported module. The memory arena split means a module's AST is freed immediately after its own pipeline finishes. If a local variable like `res` fails to resolve during the initial check (due to the issues above), it can never be "re-resolved" later because the source AST is gone, and the `sym->details` pointer is dangling.

### Recommendation
- Expand the deferral logic in `visitVarDecl` to include `NODE_BINARY_OP` and other expression types.
- Ensure that local variables in imported modules are fully resolved before the module's `mod_arena` is reset.

---

## 2. lisp_interpreter_curr: Segfault in visitMemberAccess

### Symptoms
Compiling `lisp_interpreter_curr` results in a `Segmentation fault`. Valgrind points to `TypeChecker::visitMemberAccess`.

### Root Cause Analysis
The segfault was caused by a NULL pointer dereference when handling "naked" member accesses (e.g., `.Member` used for anonymous enums or implicit tagged union variants).

1.  **Parser Behavior**: The parser correctly produces a `NODE_MEMBER_ACCESS` node with a `NULL` base expression when it encounters a leading dot followed by an identifier.
2.  **Unsafe Logging**: In `DEBUG` builds, a log statement at the very beginning of `visitMemberAccess` attempted to access `node->base->resolved_type` before verifying if `node->base` was non-NULL.
3.  **Missing Logic Guards**: Beyond the log, the auto-dereference and placeholder resolution logic in `visitMemberAccess` lacked guards for cases where `base_type` was NULL. This allowed the compiler to reach code that checked `base_type->kind`, triggering a crash.

### Recommendation
- Add robust NULL checks for `node->base` and the resulting `base_type` throughout `visitMemberAccess`.
- The initial fix added to the `DEBUG` log should be accompanied by logic that handles naked member access by deriving the base type from the `ExpectedType` context.

---

## 3. Impact of Memory Arena Split

The transition to per-module `mod_arena` has made the compiler significantly more memory-efficient but has exposed "on-demand" resolution as a dangerous pattern.

## 4. Deep dive after hardening

### Current Status
After applying the hardening fixes (NULL guards, re-evaluation of  locals, and expanded  list), the situation is as follows:

- **lisp_interpreter_curr**: The segmentation fault in `visitMemberAccess` and static analyzers is RESOLVED. The compiler now successfully generates C code for the example. This was fixed by zero-initializing all AST node allocations and adding null-guards in analyzer visitors.
- **rogue_mud**: The "Undefined type for symbol 'res'" error persists, now manifesting as a controlled `abort()` from diagnostic instrumentation. 

### Diagnostic Output (rogue_mud)
The following logs were captured during the compilation of `rogue_mud`:

```
[MEMBER] field 'start' type kind=15, is_many=1
[TYPE] visitVarDecl 'res' line=25 depth=2 module=sand
[SYMBOL] INSERTED 'res' into scope level 2
...
[TYPE] visitVarDecl 'aligned_pos' is_local=1 current_fn_ret=0x55bd15f66e88 level=2
[TYPE] visitVarDecl 'res' is_local=1 current_fn_ret=0x55bd15f66e88 level=2
```

**Key Findings**:
1. `sand.start` is correctly resolved as a many-item pointer (`kind=15`, `is_many=1`).
2. `res` is visited during the second pass, but it fails to resolve.
3. `checkPointerArithmetic` is NEVER reached for the expression `sand.start + aligned_pos`, indicating that `visitBinaryOp` returns `TYPE_UNDEFINED` early because one of the operands is unresolved.

### Diagnostic Plan for Continued Deep Dive

To further isolate why `res` fails to resolve in `rogue_mud`, the following instrumentation has been added:

1.  **BINARY_UNDEF Diagnostic**: In `TypeChecker::visitBinaryOp`, when the operator is `TOKEN_PLUS` and an operand is `TYPE_UNDEFINED`, the compiler logs the type kinds of both operands. This reveals which specific branch (left or right) is failing.
2.  **RES_DEBUG Diagnostic**: In `visitFnBody`, right before re-evaluating `res`, the compiler looks up `sand` and `aligned_pos` in the symbol table and logs their type kinds. This confirms if they were ever resolved in the symbol table before `res` was reached.
3.  **MEMBER_POS_DEBUG Diagnostic**: In `visitMemberAccess`, when accessing the `pos` field, the compiler logs the full field list of the base struct. This helps determine if `sand.pos` fails because the `Sand` struct is incomplete or if `findStructField` has a bug.

### Systemic Fixes Applied

1.  **TYPE_UNDEFINED Cache Bypass**: `TypeChecker` now uses a `resolveOrVisit` helper. This helper forces a fresh `visit()` call if a node's `resolved_type` is `TYPE_UNDEFINED`, preventing stale "failed" results from short-circuiting future resolution attempts during multiple passes.
2.  **Analyzer Hardening**: Added NULL guards to `LifetimeAnalyzer::visitVarDecl` and `NullPointerAnalyzer::visitVarDecl` to prevent crashes when `node->symbol` is missing.
3.  **Symbol Linking**: Hardened `visitVarDecl` to ensure `node->symbol` is correctly linked to the symbol table entry immediately during the pre-insertion phase for local variables.


-   **Persistence**: Symbols and Types remain in the permanent arena, but any pointers they hold back to the AST (like `ASTNode* decl_node`) are only valid during the module's active processing window.
-   **Synchronization**: The "Global Signature Resolution" pass (Phase 1.5) was intended to mitigate this by resolving all top-level signatures upfront. However, local variable inference (like `res` in `sand.zig`) still relies on AST-walking during Phase 2. If Phase 2 fails to complete resolution for a module, that module's metadata becomes permanently corrupted once its AST is freed.

## 5. Findings from Phase 11.5 Deep Dive

### rogue_mud: The `aligned_pos` Chain

Diagnostic logs for `rogue_mud` show that `aligned_pos` has type kind 17 (`TYPE_UNDEFINED`) during the second pass of `visitFnBody`:
`[RES_DEBUG] sand type kind=15, aligned_pos type kind=17`

Tracing the dependencies:
1. `res = sand.start + aligned_pos`
2. `aligned_pos = (sand.pos + mask) & ~mask`
3. `sand.pos` is a member access on the `sand` parameter.

The logs show `[MEMBER_POS_DEBUG]` correctly identifies the `pos` field in the `Sand` struct with kind 11 (`TYPE_USIZE`). However, `aligned_pos` remains undefined. This is because `visitBinaryOp` for `aligned_pos` fails, and due to the systemic `TYPE_UNDEFINED` caching bug, it was never re-attempted correctly until the `resolveOrVisit` fix.

Even with `resolveOrVisit`, if a dependency is in a different module that has already been reset, resolution will still fail. In this case, `sand` is a local parameter, so it should be resolvable. The remaining issue is likely that `aligned_pos` is not being marked for re-evaluation correctly or its initializer contains a node that still returns `TYPE_UNDEFINED` without triggering a retry.

### lisp_interpreter_curr: Segfault and Uninitialized AST Nodes (RESOLVED)

The segmentation fault in `lisp_interpreter_curr` was caused by uninitialized `node->symbol` pointers in AST nodes.

**Root Cause**:
- AST nodes are allocated from the `ast_arena_` using `ast_arena_->alloc(sizeof(ASTNode))`.
- Previously, the `ArenaAllocator` did NOT zero-initialize memory.
- Many AST nodes (like `NODE_VAR_DECL` or `NODE_IDENTIFIER`) have a `symbol` pointer field.
- If type-checking failed or deferred, these pointers remained as garbage values.
- Static analyzers like `LifetimeAnalyzer` checked `if (!node->symbol)`, which passed for garbage values, causing a crash upon dereference.

**Resolution**:
- **Arena zero-initialization**: The `ArenaAllocator::alloc` method was updated to `plat_memset` all allocated blocks to zero. This ensures all AST nodes and other internal structures are properly initialized.
- **Analyzer Hardening**: Null-guards were added to analyzer visitors as a secondary safety measure.

## 6. Final Resolution of Regression Issues

### lisp_interpreter_curr (RESOLVED)
- **Segfault**: Fixed. The root cause was garbage pointers in AST nodes (specifically `node->symbol`) because the `ArenaAllocator` didn't zero-initialize memory.
- **Fix**: Updated `ArenaAllocator::alloc` to `plat_memset` all new blocks to zero.
- **Status**: Compiler successfully generates C code for all modules in the lisp interpreter.

### rogue_mud (IN PROGRESS - Instrumented)
- **Undefined 'res'**: Still occurs, but the cause is now isolated to the `aligned_pos` dependency chain.
- **Findings**:
    - `actual_align` now resolves correctly to `usize` (kind 11) using improved `if` expression unification.
    - `aligned_pos` remains `TYPE_UNDEFINED` because its initializer (a bitwise AND of an addition) fails to resolve in the available passes.
    - Systematic `TYPE_UNDEFINED` caching has been mitigated via the `resolveOrVisit` helper, which is now applied to `visitMemberAccess`, `visitBinaryOp`, `visitIfExpr`, `visitIfStmt`, `visitAssignment`, `visitCompoundAssignment`, `visitParenExpr`, and `visitVarDecl` initializers.
    - **Composite Stalling**: Despite leaf resolution (confirmed by `[MEMBER_POS_RESULT]` showing `sand.pos` as `usize`), the composite expression `(sand.pos + mask)` remains `TYPE_UNDEFINED`.
    - **Identifier Caching Suspect**: `TypeChecker::visitIdentifier` contains a shortcut during `is_post_check_phase_` that returns the cached `node->resolved_type` immediately. If this was set to `TYPE_UNDEFINED` earlier, it may be blocking re-resolution even if the symbol is now valid.
    - **Re-evaluation Loop**: The loop in `visitFnBody` correctly triggers for `aligned_pos` and `res`, but they stall because their initializers contain sub-expressions (like the parenthesized addition) that are not yet transitioning to concrete types.
- **Status**: The compiler is now heavily instrumented with `[VAR_REEVAL]`, `[RES_DEBUG]`, `[BINARY_UNDEF]`, `[IF_EXPR]`, and `[MEMBER_POS_RESULT]` diagnostics to facilitate the final logic fix.

### Compiler Hardening
- **Pre-codegen Assertions**: Added strict checks in `CompilationUnit` to abort if any global/public symbol remains with a NULL, `TYPE_UNDEFINED`, or `TYPE_PLACEHOLDER` type before code generation. This prevents silent "missing code" failures.
- **Symbol Table Consistency**: Improved `visitVarDecl` to link `node->symbol` immediately during local variable pre-insertion, ensuring analyzers always see a valid (though possibly incomplete) symbol.

## 7. Deep Dive: NULL type for symbol 'res' (NEW)

### Symptoms
After hardening the compiler to handle `TYPE_UNDEFINED` and improving re-evaluation of local variables, a new failure emerged:
`NULL type for symbol 'res' in module 'sand'`

This is distinct from the previous `TYPE_UNDEFINED` errors. Instrumentation in `Scope::insert` revealed that symbols were being inserted into the symbol table with a `NULL` type.

### Initial Instrumentation Findings
Adding a `plat_abort()` in `Scope::insert` when `symbol.symbol_type == NULL` caught an immediate failure during the compilation of `rogue_mud`:

`[SYMBOL_NULL] Inserting symbol 'sand_mod' with NULL type! module=main scope_level=1`

This indicated that `@import` aliases (like `const sand_mod = @import("lib/sand.zig");`) were being registered without a valid type (neither `TYPE_MODULE` nor a `TYPE_PLACEHOLDER`).

### Investigation Findings
The investigation into the `sand_mod` NULL type error revealed a systemic issue in how symbols are initially registered and subsequently updated.

1.  **Parser Prematurity**: `Parser::parseVarDecl` creates and inserts a `Symbol` for every variable declaration it encounters. However, for `@import` aliases (and often for constants holding types), the actual `Type` is not yet available during parsing. Consequently, the symbol was being inserted with a `NULL` type.
2.  **`SymbolTable::insert` Rejection**: When `CompilationUnit::resolveImportsRecursive` later attempted to register the proper `TYPE_MODULE` for the import alias, it called `getSymbolTable().insert(mod_sym)`. However, `SymbolTable::insert` contains logic to prevent redeclarations, causing the update call to return `false` and do nothing, leaving the `NULL` type in place.
3.  **`Scope::insert` Vulnerability**: The low-level `Scope::insert` method performed a wholesale struct replacement (`entry->symbol = symbol`). This meant any later "update" with an incomplete `Symbol` struct (e.g. from `ASTLifter` or a misplaced builder call) would permanently corrupt the symbol table entry, even if it was previously correct.

### Resolution and Hardening
The systemic issue was resolved by applying three layers of hardening to ensure symbol table integrity:

1.  **`Scope::insert` Resilience**: The low-level insertion logic was updated to prevent accidental type corruption. If an existing symbol is being updated with a new `Symbol` struct that has a `NULL` type, the existing valid type is preserved.
2.  **Explicit Import Updating**: `CompilationUnit::resolveImportsRecursive` now explicitly checks for existing symbols when registering module aliases. If found, it updates the type directly instead of relying on `insert()`.
3.  **Parser Sanitization**: `Parser::parseVarDecl` was updated to initialize symbols with `TYPE_UNDEFINED` instead of `NULL` when the type is not yet known.

### Future Work
While the immediate "NULL type" corruption is blocked, a complete audit of `SymbolBuilder` usages is recommended to ensure all symbols are created with at least `TYPE_UNDEFINED`. This will prevent reliance on the `Scope::insert` safety net.
