# Bug Deep Dive: --self-test failure (ERR_LIFETIME_VIOLATION not detected)

## Observation
When running `./zig0 --self-test`, the compiler correctly detects `ERR_NULL_POINTER_DEREFERENCE` and `ERR_DOUBLE_FREE`, but fails to detect `ERR_LIFETIME_VIOLATION` in the following code:

```zig
fn lifetime_test() -> *i32 {
    var x: i32 = 10;
    return &x; // Lifetime violation
}
```

## Root Cause Analysis
The failure occurs in `src/bootstrap/lifetime_analyzer.cpp` within the `isDangerousLocalPointer` method.

### Analysis of `isDangerousLocalPointer`
The method attempts to determine if an expression refers to a local variable that would be dangerous to return.

1.  **Provenance Resolution**: For the expression `&x`, `getPointerProvenance` correctly returns the string `"x"`.
2.  **Symbol Lookup**:
    ```cpp
    Symbol* sym = NULL;
    if (expr->type == NODE_IDENTIFIER) {
        sym = expr->as.identifier.symbol;
    }
    if (!sym && !unit_.isPostCheckPhase()) sym = unit_.getSymbolTable().findInAnyScope(base_name);
    if (!sym) return false;
    ```
    - The expression `expr` is `&x`, which is of type `NODE_UNARY_OP` (with `op == TOKEN_AMPERSAND`).
    - Therefore, `expr->type == NODE_IDENTIFIER` is **false**, and `sym` remains `NULL`.
    - `unit_.isPostCheckPhase()` is **true** because the static analyzers run after the type-checking phase.
    - Consequently, `unit_.getSymbolTable().findInAnyScope(base_name)` is **skipped**.
    - Since `sym` is `NULL`, the function returns `false`, and no violation is reported.

### Why this happens
The `LifetimeAnalyzer` relies on string-based provenance tracking (`base_name`), but it lacks a reliable way to resolve these strings back to `Symbol` objects during the post-check phase. The check `!unit_.isPostCheckPhase()` was added as a safety measure to prevent unsound symbol re-resolution after scopes are discarded (Bug 2), but it has effectively "blinded" the `LifetimeAnalyzer` for any expression that isn't a direct `NODE_IDENTIFIER`.

For `&x`, even though the operand `x` is a `NODE_IDENTIFIER` and likely has its `symbol` field populated, `isDangerousLocalPointer` only looks at the `symbol` field of the top-level expression (`&x`), which doesn't have one.

## Potential Fix Strategy (For Reference)
- The analyzer should be updated to retrieve the `Symbol` from the underlying `NODE_IDENTIFIER` node if the provenance matches it, or a more robust way to map provenances to symbols needs to be implemented.
- Alternatively, if the provenance is a simple name, and we are in the post-check phase, we might need a way to look up symbols in a "frozen" global symbol table if the analyzers are supposed to work across the whole module.

## Other Analyzers
- `NullPointerAnalyzer`: PASSED. It uses `getExpressionState` which handles `NODE_NULL_LITERAL` and `NODE_IDENTIFIER` states correctly.
- `DoubleFreeAnalyzer`: PASSED. It tracks allocations and deallocations by name and has its own `TrackedPointer` state management.
