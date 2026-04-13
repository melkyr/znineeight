# Z98 Bootstrap Architecture & Capability Specification

This document provides a senior-level technical specification of the architectural patterns and internal mechanisms implemented in the Z98 bootstrap compiler (`zig0`). These capabilities define the "ground truth" for the `zig1` implementation.

## 1. Memory Management: The Hierarchical Arena System

To satisfy the **<16MB peak RAM constraint** while maintaining high throughput on 1998-era hardware, `zig0` eschews standard heap allocation in favor of a multi-tiered arena strategy.

### 1.1 Arena Topology
*   **Persistent (Global) Arena**: Lifecycle spans the entire execution. Houses the `StringInterner` (atomic deduplication), `TypeRegistry` (nominal type identity), and cross-module `SymbolTable`.
*   **Module-Specific Arenas**: Lifecycle tied to a `CompilationUnit`. Contains the AST and module-local semantic metadata.
*   **Transient Token Arena**: High-churn arena used exclusively during Lexing/Parsing. It is **purged immediately** after AST construction to reclaim memory for Semantic Analysis.
*   **Emission Buffer Arena**: Used for stringifying complex L-values and managing `typedef` order during C code generation.

### 1.2 Resource Discipline
*   **Zero-Free Policy**: Objects are never individually freed. Fragmentation is eliminated by construction.
*   **Bump-Pointer Allocation**: `O(1)` allocation cost with 8-byte alignment guarantees.
*   **Reset & Reuse**: Data structures that grow with AST depth (e.g., state-maps in Static Analyzers) use a `reset()` checkpointing pattern at the end of each function-level analysis.

## 2. Advanced Type System: Placeholder Mutation & Late Binding

Z98 supports self-referential and mutually recursive types (critical for AST nodes and Lisp-like data structures) using a sophisticated **late-binding mutation pattern**.

### 2.1 The Resolution Protocol
1.  **Registration**: Upon encountering a type name (e.g., `Node`), the compiler registers a `TYPE_PLACEHOLDER`.
2.  **Stable Mangling**: A deterministic C-name (e.g., `zS_0_Node`) is assigned to the placeholder immediately. All dependent pointers (e.g., `*Node`) reference this placeholder.
3.  **AST Visitation**: The Type Checker resolves the aggregate body.
4.  **In-Place Mutation**: Once layout is computed, the `Type` structure is mutated from `TYPE_PLACEHOLDER` to `TYPE_STRUCT`.
5.  **Cascading Refresh**: A work-queue drains all transitive dependencies, ensuring that any type cached (like `[]Node`) is updated with the new layout information.

## 3. Modular Compilation: Topological Dependency Model

`zig0` implements a **separate compilation model** that mirrors professional C toolchains while preserving Zig's modularity.

### 3.1 Linkage & Visibility
*   **Topological Sorting**: Modules are analyzed in dependency order (Kahn's algorithm).
*   **Metadata Leakage**: The `MetadataPreparationPass` identifies "private" special types (like an internal `[]u8`) that are reachable via `pub` signatures and promotes them to the module header to prevent "incomplete type" errors in downstream modules.
*   **C Header Contract**: Generates self-contained `.h` files with automated include guards and forward-declarations for all local aggregates.

## 4. AST ControlFlowLifter: Lowering Expression-Oriented Logic

Because C89 is strictly statement-based, Zig's expression-oriented features (nested `if`, `switch`, `try`, `catch`, `orelse`) require a mandatory normalization pass.

### 4.1 Hoisting Mechanics
*   **Recursive Lifting**: The lifter traverses the AST post-order. When a "Control Flow Expression" is found in a non-statement context, it is hoisted.
*   **Temporary variable Injection**: A new local variable is declared at the top of the C block. The expression is converted into a statement that assigns to this variable.
*   **Evaluation Order Preservation**: The lifter ensures that `foo(try bar(), baz())` results in `bar()` being called and checked before `baz()` is evaluated.

## 5. C89 Emitter: Standards-Compliant Codegen

### 5.1 Block-Level Normalization
C89 requires declarations before statements. `zig0` implements a **Two-Pass Block Emitter**:
*   **Pass 1 (Scan)**: Collects all `VarDecl` nodes in the current `{}` scope and emits C-style declarations.
*   **Pass 2 (Emit)**: Emits executable statements, converting original declarations into simple assignments.

### 5.2 Intrinsic Lowering
*   **Print Decomposition**: `std.debug.print` is parsed at compile-time. The emitter decomposes it into a sequence of specific runtime calls (`__bootstrap_print_int`, `__bootstrap_print_char`), eliminating the need for a heavyweight `vfprintf` in the runtime.
*   **Slice Specialized Helpers**: Generates `static inline` helpers (e.g., `__make_slice_u8`) in a centralized `zig_special_types.h` to ensure ABI compatibility across translation units.

## 6. Static Analysis: Flow-Sensitive Safety Tracking

The compiler enforces memory safety through a suite of data-flow analyzers.

### 6.1 State-Map Delta Pattern
To maintain the **16MB limit**, analyzers do not deep-copy state at branches.
*   **Delta Chaining**: When forking for an `if`, a new "delta" map is created, pointing to the parent state.
*   **Conservative Join**: At the merge point, states are unified (e.g., `SAFE + NULL = MAYBE_NULL`).
*   **LIFO Defer Execution**: Analyzers maintain a compile-time stack of `defer` blocks, simulating their execution at every `return`, `break`, or `continue` to update pointer states accurately.
