# Bug Deep Dive: zig0 to zig1 "Matriuska" Compilation Failures

This document details the investigation into compilation errors encountered when using the `zig0` bootstrap compiler to compile the `sf/src/main.zig` (Stage 1) codebase.

## 1. Bug 1: Transitive Alias Resolution Failure (Undeclared Types)

### 1.1 Symptoms
The compiler reports "use of undeclared type" for identifiers that are validly defined as transitive aliases to types in other modules.

**Example Failure:**
```
sf/src/lexer.zig:25:18: error: use of undeclared type 'U8ArrayList'
        string_buf: *U8ArrayList,
                     ^
sf/src/lexer.zig:44:37: error: use of undeclared type 'Token'
    pub fn lexerNextToken(self: *Lexer) Token {
                                        ^
```

In `lexer.zig`, these are defined as:
```zig
const ga_mod = @import("growable_array.zig");
const U8ArrayList = ga_mod.U8ArrayList;
const token_mod = @import("token.zig");
const Token = token_mod.Token;
```

### 1.2 Initial Findings
*   **Phase 0.5 (Placeholder Resolution)**: Logs show that placeholders for the "root" types (e.g., `Token` in `token.zig`) ARE successfully resolved during the fixed-point iteration loop.
*   **Phase 1.5 (Global Signature Resolution)**: The failure happens when resolving signatures for modules that depend on these aliases.
*   **The "Matriuska" Effect**: The issue appears to be a breakdown in the resolution chain: `Module A (lexer)` -> `Alias (Token)` -> `Module B (token_mod)` -> `Concrete Type (Token)`.

### 1.3 Deep Dive: The Module Pointer Identity Crisis
Instrumentation has revealed a fundamental issue with how modules are identified during cross-module lookups:
*   **Pointer-Based Registry**: The `TypeRegistry` uses `Module*` pointers as part of its hash key.
*   **Identity Mismatch**: In some "Matriuska" scenarios (deep/circular imports), the same logical module (e.g., `token.zig`) is occasionally represented by different `Module*` instances.
*   **Lookup Failure**: When `lexer.zig` attempts to resolve `token_mod.Token`, it uses the `Module*` stored in the `token_mod` symbol. If this pointer doesn't exactly match the one used during `Token`'s registration in `token.zig`, the registry lookup returns `NULL`.
*   **Root Cause Suspect**: `CompilationUnit::addSource` or `resolveImportsRecursive` might be creating duplicate `Module` objects for the same file path due to non-canonical path comparisons or timing issues in the recursive discovery process.

### 1.4 Transitive Placeholder Stalling
A second failure mode involves aliases-to-aliases:
*   **Placeholder Finalization**: `TypeChecker::resolveNamedPlaceholder` refuses to finalize a placeholder if the resolved type is *itself* a placeholder.
*   **Iteration Limit**: In a deep chain like `ModA.T -> ModB.T -> ModC.T`, if `ModC.T` is resolved in Iteration 1, `ModB.T` can only resolve in Iteration 2, and `ModA.T` in Iteration 3.
*   **Convergence Failure**: While 10 iterations are usually enough, any circularity among constants or deep transitive chains can cause placeholders to remain unresolved when the loop terminates, leading to "undeclared type" errors in Phase 2.

---

## 2. Bug 2: Loop Capture Scope Mismatch (Undeclared Identifier)

### 2.1 Symptoms
Loop capture variables (e.g., `ei` in a `for` loop) are reported as "undeclared identifier" even though they are clearly in scope.

**Example Failure:**
```
sf/src/string_interner.zig:140:36: error: use of undeclared identifier 'ei'
            var entry = &entries_slice[ei];
                                       ^
```

### 2.2 Initial Findings
*   **Scope Registration**: Instrumentation confirms that `visitForStmt` correctly enters a new scope (e.g., Level 3) and inserts the capture symbol `ei`.
*   **Lookup Failure**: When visiting the identifier `ei` inside the loop body, the lookup fails.
*   **Module Filter Constraint**: `SymbolTable::lookup` and `Scope::find` employ a module-name filter. Local variables (captures, stack vars) are registered with a `NULL` module name.
*   **Visibility Gap**: If `current_module_` is set to something non-NULL (e.g., during cross-module resolution or simply because the compiler is processing a specific module), the `Scope::find` logic might be skipping the `NULL`-module local variables if the filter is too aggressive.

### 2.3 Deep Dive: Synthetic Node Scope Leak
The most likely root cause for the "undeclared identifier" bug in `for` loop captures is the interaction between `TypeChecker` and later passes:
*   **Unresolved Synthetic Nodes**: `TypeChecker::visitArraySlice` (used in range-based loops and string literal coercions) creates synthetic AST nodes for `base_ptr` and `len`.
*   **Deferred Resolution**: These synthetic nodes are populated but **not visited immediately** by the `TypeChecker` within the active loop scope.
*   **Out-of-Scope Visitation**: Later passes (like `MetadataPreparationPass` or `CallResolutionValidator`) traverse the AST using `forEachChild`, which includes these synthetic sub-trees.
*   **Level 2 Lookup**: When these later passes attempt to resolve an identifier (like the capture `ei` used in a synthetic index access), they do so from the **Global Scope** or a higher-level function scope (Level 2).
*   **Lookup Failure**: Since `ei` is only defined in the transient loop scope (Level 3), the lookup fails with "undeclared identifier".

### 2.4 Block Re-visitation and Scope State
*   **Idempotency Failure**: `TypeChecker::visitBlockStmt` returns early if `resolved_type` is already set. However, it does not re-open the symbol table scope.
*   **Child Desync**: If child nodes within the block are re-visited (e.g., due to `coerceNode` on a parent), they may attempt lookups in a symbol table that has already been popped back to the parent level.

---

## 3. The Smoking Gun: Symbol Table Global Leak and Post-Check Visitation

The deep dive has identified a critical architectural flaw in how the compiler handles subsequent passes after the initial type checking.

### 3.1 `findInAnyScope` - The False Safety Net
When a lookup fails in the current scope stack, the `TypeChecker` falls back to `SymbolTable::findInAnyScope`.
*   **The Leak**: `SymbolTable` maintains `all_scopes_`, a list of every scope ever created during the compilation of a module.
*   **The Unsoundness**: `findInAnyScope` searches this global list from newest to oldest. This is fundamentally unsound because it ignores whether a scope is actually a parent of the current node.
*   **Consequence**: It can return symbols from completely unrelated functions or blocks simply because they were the most recently processed "local" scopes.

### 3.2 Phase 3+ Validation Passes
The "undeclared identifier" and "undeclared type" errors seen in the logs are actually happening **after** Phase 2 (Body Checking) has already failed or completed.
*   **Re-visitation**: Passes like `C89FeatureValidator` and `CallResolutionValidator` traverse the AST and, in many cases, call `TypeChecker::visit` on nodes to ensure they are fully resolved.
*   **Scope Mismatch**: These subsequent passes run when the `SymbolTable` has already been popped back to the Global Scope (Level 1).
*   **Lookup Failure**: When `visitIdentifier` is called on a local variable (like `ei`) during these later passes, `SymbolTable::lookup` correctly fails (since Level 3 is gone). The fallback `findInAnyScope` then either fails or finds a shadow symbol, leading to the "undeclared identifier" error.

---

## 4. Final Summary of Findings

1.  **Bug 1 (Aliases)**: Rooted in the `TypeRegistry` being overly sensitive to `Module*` identity and the Phase 0.5 resolution loop not being aggressive enough in unwrapping transitive placeholders that resolve to `TYPE_TYPE` constants.
2.  **Bug 2 (Identifiers)**: Rooted in post-typechecking passes re-visiting the AST without proper scope context, combined with a `SymbolTable` that "remembers" too many dead scopes, leading to both false positives and false negatives during identifier resolution.

---

## 5. Conclusion and Recommendations

The compilation of the Stage 1 compiler stresses the `zig0` bootstrap compiler beyond its original single-module design. The "Matriuska" bugs are not merely edge cases but reflections of fundamental architectural assumptions that hold true for simple examples but fail under the weight of deep circularity and complex transitive dependencies.

### 5.1 Recommended Architectural Fixes (STATUS: PARTIALLY IMPLEMENTED)
*   **Canonical Module Identity** (FIXED in Z98 0.12.2): The `TypeRegistry` now uses interned, absolute, and lowercased canonical paths as keys. This eliminates logical identity mismatches even if multiple `Module*` pointers exist for the same file.
*   **Scope-Aware Re-visitation**: Passes that occur after type checking must either:
    1.  Strictly avoid calling `TypeChecker::visit` on nodes that are already resolved.
    2.  Provide a mechanism to re-establish the correct scope stack before attempting re-visitation.
*   **Abolish `findInAnyScope`**: The "safety net" of searching all historical scopes is dangerous. Identifier lookups must strictly follow the lexical parent-pointer chain. If a symbol is not in the current active scope stack, it is truly undeclared.
*   **Aggressive Alias Unwrapping** (FIXED in Z98 0.12.2): Phase 0.5 now uses a fixed-point iteration loop (up to 10,000 passes) and deeply unwraps `TYPE_TYPE` constants during placeholder resolution. This ensures that transitive alias chains (e.g., `const A = B; const B = C;`) are fully resolved to concrete types before Phase 1.5 begins.
