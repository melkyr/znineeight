# Z98 Compilation Pipeline

This document describes the multi-phase compilation pipeline of the Z98 bootstrap compiler (`zig0`). The pipeline is designed to handle multi-module projects, circular imports, and recursive types within the constraints of C89 code generation and a 16MB memory limit.

## Pipeline Overview

The compilation process is orchestrated by `CompilationUnit::performFullPipeline`. It proceeds through the following sequential phases:

### Phase 1: Parsing and Import Resolution
- **Action**: The entry point file is lexed and parsed.
- **Canonical Identity**: `addSource` computes and stores the `canonical_path` (absolute, normalized, interned string) for each module, which is used for robust type deduplication.
- **Recursion**: Any `@import` statements trigger the recursive loading and parsing of dependency modules.
- **Scope**: Each module gets its own `SymbolTable` and AST root.
- **Context Switch**: `setCurrentModule` is used during this phase to ensure symbols are registered to the correct module.

### Phase 1.1: Topological Sorting
- **Action**: All discovered modules are sorted based on their import dependencies.
- **Purpose**: Ensures that modules are processed in an order that respects their dependencies, although the subsequent global resolution phases make this less critical for type information.

### Phase 1.2: Placeholder Registration (Phase 0)
- **Action**: Every module is scanned to register `TYPE_PLACEHOLDER` for all top-level `struct`, `union`, `enum`, and type aliases.
- **Purpose**: Enables the resolution of recursive and mutually recursive types across module boundaries.

### Phase 1.3: Named Placeholder Resolution (Phase 0.5)
- **Action**: Resolves the underlying types for the placeholders registered in the previous phase.
- **Fixed-Point Iteration**: This phase now uses a fixed-point loop (up to 10,000 iterations) that continues as long as new placeholders are resolved.
- **Deep Unwrapping**: When resolving a placeholder that points to a `TYPE_TYPE` constant (e.g., `const A = B;`), the resolver now deeply unwraps the alias chain to find the concrete underlying type.
- **Purpose**: Transition from placeholders to concrete (but potentially incomplete) type structures. This robust mechanism is critical for handling deep transitive alias chains across multiple modules.

### Phase 1.4: Name Collision Detection (Phase 1)
- **Action**: Verifies that there are no duplicate symbol definitions within the same scope across all modules.

### Phase 1.5: Global Signature Resolution (NEW)
- **Action**: For every module, the compiler resolves:
    - The type of every `const` declaration (including `@import` aliases).
    - The full signature (parameter/return types) of every `pub fn` function.
    - The type of every `pub var`.
- **Purpose**: **This is the final fix for cross-module resolution.** By resolving all top-level signatures before any function bodies are checked, we eliminate the need for fragile on-demand context switching during body checking. Every callable function already has its `symbol_type` set before Phase 2 begins.

### Phase 2: Type Checking (Body Checking)
- **Action**: The compiler visits every function body and performs full semantic analysis.
- **Local Resolution**: Forward references within the *same* module are still handled via a simplified fallback in `resolveCallSite`, but cross-module symbols are guaranteed to be resolved.
- **Post-Check Initialization**: After Phase 2 completes, the `is_post_check_phase_` flag is set globally on the `CompilationUnit`.

### Phase 2.5: Mangled Name Precomputation
- **Action**: Computes stable C89-compliant mangled names for all public symbols.

### Phase 3: Validation Passes
- **Action**: Runs specialized validators. These passes operate with `is_post_check_phase_` enabled, ensuring they rely on the pre-resolved AST and do not attempt to re-resolve identifiers.
    - `CallResolutionValidator`: Ensures all calls are resolved.
    - `SignatureAnalyzer`: Validates function signatures for C89 compatibility.
    - `C89FeatureValidator`: Rejects non-C89 Zig features.

### Phase 4: AST Lifting
- **Action**: Transforms expression-form control flow (`if`, `switch`, `try`, etc.) into C89-compliant statement-form using temporary variables.

### Phase 4.5: Metadata Preparation
- **Action**: Dependency-orders type definitions in C headers to avoid "incomplete type" errors.

### Phase 5: Static Analysis
- **Action**: Runs `LifetimeAnalyzer`, `NullPointerAnalyzer`, and `DoubleFreeAnalyzer` to detect memory safety issues.

### Phase 6: Code Generation
- **Action**: Emits the final `.c` and `.h` files for each module using the `CBackend`.

## Architecture Principles

- **Arena Allocation**: All phases share a layered arena system to stay within the 16MB limit.
- **No On-Demand Cross-Module Switching**: Since Phase 1.5, body checking (Phase 2) never needs to switch module context to resolve a foreign symbol.
- **C89 Strictness**: Every phase is designed to ensure the resulting C code is strictly ANSI C89 compliant.
