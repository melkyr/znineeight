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

- **lisp_interpreter_curr**: The segmentation fault in `visitMemberAccess` is RESOLVED. The compiler now successfully generates C code for the example.
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
