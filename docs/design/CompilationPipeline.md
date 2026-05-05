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

### Phase 1.3.1: Transitive Alias Flattening (Phase 0.7)
- **Action**: A dedicated sub-pass that follows all aliases whose resolved type is itself a `TYPE_TYPE` (i.e., an alias to another alias) and unwraps them until they point to a concrete type.
- **Fixed-Point Loop**: Uses a separate fixed-point loop with a safety cap (100 iterations) to ensure deeply nested chains are fully flattened.
- **Mechanism**: Calls `resolveTypeConstant` on each pending resolution symbol and finalizes the placeholder to the resulting concrete type.
- **Purpose**: Handles edge cases where the Phase 1.3 loop might not fully unwrap complex alias chains in a single pass.

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

### Phase 4: Per-Module Processing Loop
- **Action**: Iterates through all modules in topological order and performs the remaining passes for each module individually.
- **AST Release**: After each module is processed (including code generation), its specific AST arena (`mod_arena`) is reset.
- **Memory Impact**: This ensures that peak memory usage is determined by the largest single module's AST, rather than the sum of all modules.

#### Phase 4.1: AST Lifting
- **Action**: Transforms expression-form control flow into statement-form. Now uses the per-module `mod_arena` for any newly created AST nodes.

#### Phase 4.2: Static Analysis
- **Action**: Runs `LifetimeAnalyzer`, `NullPointerAnalyzer`, and `DoubleFreeAnalyzer`.

#### Phase 4.3: Per-Module Metadata Preparation
- **Action**: Transitively collects reachable types for the module's header and performs topological sorting of those types.

#### Phase 4.4: Code Generation
- **Action**: Emits the `.c` and `.h` files for the module.

### Phase 5: Global Codegen Tasks
- **Action**: Generates build scripts (`build_target.bat`, `Makefile`, etc.) and copies runtime files to the output directory.

## Architecture Principles

- **Arena Allocation**: All phases share a layered arena system to stay within the 16MB limit.
- **No On-Demand Cross-Module Switching**: Since Phase 1.5, body checking (Phase 2) never needs to switch module context to resolve a foreign symbol.
- **C89 Strictness**: Every phase is designed to ensure the resulting C code is strictly ANSI C89 compliant.
