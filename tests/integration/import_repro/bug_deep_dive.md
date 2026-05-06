# Bug Deep Dive: Transitive Alias Blockades and Unsound Symbol Re-resolution

## 1. Bug Summary
The Z98 bootstrap compiler (`zig0`) suffers from two critical issues during multi-module compilation (Stage 1):
1.  **Bug 1: Transitive Alias Blockades**: Global type aliases using member access (e.g., `const Foo = @import("a.zig").Foo;`) trigger `ERR_GLOBAL_VAR_NON_CONSTANT_INIT` because the emitter misidentifies them as variables and fails to recognize their initializers as constant.
2.  **Bug 2: Unsound Symbol Re-resolution**: Post-typechecking passes (static analyzers) inconsistently re-resolve identifiers using `SymbolTable::findInAnyScope`, which is unsound after lexical scopes have been popped.

## 2. Bug 1: Transitive Alias Blockades

### A. Root Cause: Metadata Loss in `TypeChecker::visitVarDecl`
When the `TypeChecker` visits a global constant declaration that aliases a type from another module, it correctly resolves the underlying type (e.g., `TYPE_STRUCT`). However, `visitVarDecl` returns this **concrete type** instead of `TYPE_TYPE`.

Consequently, the `NODE_VAR_DECL` node itself gets its `resolved_type` set to the concrete type. When the `C89Emitter` later visits this node, it sees a struct type and concludes it must emit a C variable declaration.

### B. Root Cause: `isConstantInitializer` Limitations
The emitter then attempts to validate the initializer (a `NODE_MEMBER_ACCESS` like `mod.Foo`). `isConstantInitializer` only returns `true` for member access if the base resolves to an `ENUM`. It does not recognize that member access resolving to a type or a module-level constant is also "constant" in the Z98 context.

### C. Analysis Verification
Debug logs confirm:
- `visitVarDecl 'Foo'` returns kind 24 (`TYPE_STRUCT`) instead of kind 30 (`TYPE_TYPE`).
- `emitGlobalVarDecl` processes 'Foo' with kind 24.
- `isConstantInitializer` is called for `NODE_MEMBER_ACCESS` (type 7) and returns `false`.

### D. Proposed Fix
1.  **Harden `visitVarDecl`**: If a global `const` declaration is a type alias (its initializer is a type expression or resolves to a type), ensure it returns `get_g_type_type()`.
2.  **Update `isTypeExpression`**: Ensure it returns `true` for `NODE_MEMBER_ACCESS` if `resolved_type` is `TYPE_TYPE` or if it points to a `SYMBOL_TYPE`.
3.  **Update `isConstantInitializer`**: Recognize `NODE_MEMBER_ACCESS` as constant if it resolves to `TYPE_TYPE` or `TYPE_MODULE`.
4.  **Harden Emitter**: In `emitGlobalVarDecl` and `emitLocalVarDecl`, skip any declaration where `node->resolved_type` is `TYPE_TYPE` or `TYPE_MODULE`.

## 3. Bug 2: Unsound Symbol Re-resolution

### A. Root Cause: Bypassing `is_post_check_phase_`
The `TypeChecker::visitIdentifier` function correctly uses a `is_post_check_phase_` guard to avoid re-resolving symbols after the main check pass. However, static analyzers like `NullPointerAnalyzer`, `LifetimeAnalyzer`, and `DoubleFreeAnalyzer` call `SymbolTable::findInAnyScope` directly.

`findInAnyScope` searches a linear history of all scopes ever created. This is unsound because:
1.  Identifiers (like loop variables `ei`) might exist multiple times in the history with different types or meanings.
2.  Synthetic nodes created during the main pass (e.g., by `visitArraySlice`) might not have their `Symbol*` pointers wired up, forcing analyzers to fall back to name-based lookup.
3.  Lookup might succeed for a "dead" symbol that should no longer be visible, leading to incorrect analysis or crashes.

### B. Analysis Verification
Debug logs show analyzers frequently calling `findInAnyScope` for variables like `ei` and `hash` during the post-check loop. While currently these lookups often succeed by luck (finding the most recent scope entry), it violates the architectural invariant that semantic analysis should be complete before analyzers run.

### C. Proposed Fix
1.  **Analyzer Audit**: Refactor all static analyzers to use `node->resolved_type` and `node->as.identifier.symbol` (if available) instead of direct symbol table lookups.
2.  **Synthetic Node Wiring**: Ensure that `visitArraySlice` and other synthetic-node-generating functions correctly propagate `Symbol*` pointers and `resolved_type` to their children.
3.  **Harden `findInAnyScope`**: Consider disabling this function entirely or wrapping it in a `Z98_ASSERT(!unit.isPostCheckPhase())` to enforce architectural discipline.
4.  **Symbol Pointer Persistence**: Ensure that `node->as.identifier.symbol` is always populated during the main `visitIdentifier` pass so analyzers don't need to perform lookups.
