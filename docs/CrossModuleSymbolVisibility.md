# Bug Investigation: Cross-Module Symbol Visibility

## Status
**Bug**: `module 'X' has no member named 'Y'`
**Root Cause**: Incorrect module processing order during Type Checking, leading to failed on-demand symbol resolution.

## Investigation Steps

1.  **Reproduction**:
    -   The bug was reproduced by compiling the Lisp interpreter (`examples/lisp_interpreter/main.zig`).
    -   Initial blockers (missing `@intToPtr` support) were resolved by adding the builtin to the compiler and modifying the interpreter to use optional pointers (`?*T`).
    -   The error `module 'parser' has no member named 'parse_expr'` was consistently observed during the compilation of `main.zig`.

2.  **Instrumentation**:
    -   Added `DEBUG_VISIBILITY` logging to track:
        -   Symbol insertion (including `pub` status via a new `SYMBOL_FLAG_PUB`).
        -   Module loading and import resolution order.
        -   Per-module Type Checking start/end.
        -   Cross-module member access lookups.

3.  **Analysis of Logs**:
    -   **Discovery Order**: Modules are currently processed in the order they are discovered during import resolution, starting with the entry module (`main`).
    -   **Pre-emptive Access**: `main` starts its Type Checking phase *before* any of its dependencies (`parser`, `eval`, etc.) have been type-checked.
    -   **On-Demand Resolution**: When `main` accesses `parser_mod.parse_expr`, the `TypeChecker` attempts to resolve `parse_expr` on-demand.
    -   **Nested Dependencies**: `parse_expr` has parameters whose types depend on other imports *within* `parser.zig` (e.g., `token_mod.Tokenizer`).
    -   **The Failure**: Because `parser.zig` hasn't been type-checked yet, the internal lookups for its own dependencies (`token_mod`) can fail or return incomplete results. This causes the on-demand resolution of `parse_expr` to fail, which the compiler then reports as the symbol being missing from the module.

## Findings

-   The symbol table *does* contain the requested symbols (they are inserted during parsing).
-   The "Visibility" error is a misleading fallback reported when on-demand semantic analysis of a symbol fails.
-   The underlying issue is that the compiler expects to be able to resolve any symbol at any time, but its current state management doesn't handle nested cross-module dependencies well when modules are type-checked out of order.

## Recommendations

1.  **Topological Sort**: Implement a topological sort of the module dependency graph. The `CompilationUnit` should execute the Type Checking phase on modules in an order where dependencies are processed before their importers.
2.  **Explicit Symbol Availability**: Ensure that symbols marked `pub` are fully available and their signatures are resolved before any importer starts type checking.
3.  **Robust On-Demand Resolution**: Improve the `TypeChecker`'s ability to switch contexts and resolve nested dependencies during on-demand lookups, or eliminate the need for it by using the correct processing order.

## Documentation Updates
-   `DESIGN.md`: Updated with notes on module processing order.
-   `Z98_upcoming_bugfixes.md`: Bug documented and linked to this report.
