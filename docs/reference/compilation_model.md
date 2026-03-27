> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Compilation Model

This document describes the overall compilation model of the Z98 bootstrap compiler.

## Separate Compilation (Current)

As of Milestone 10, the compiler uses a **Separate Compilation Model**. This replaces the earlier Single Translation Unit (STU) approach.

1.  **Module Parsing**: The `CompilationUnit` loads and parses the entry module and recursively discovers all imports via `@import`.
2.  **Topological Sorting**: All discovered modules are topologically sorted based on their `@import` dependencies. This ensures that a module's dependencies are always processed before the module itself.
3.  **Semantic Analysis (Multi-Pass)**:
    -   **Pass 0: Placeholder Registration**: Registers `TYPE_PLACEHOLDER` for all top-level types across all modules to support cross-module recursion.
    -   **Pass 1: Type Checking**: Resolves all types and validates operations across all modules in topological order.
    -   **Pass 2: C89 Feature Validation**: Rejects non-C89 features (e.g., `anyerror`, anonymous union payloads) and bootstrap-specific limitations.
    -   **Pass 3: Control Flow Lifting**: Transforms expression-valued control-flow (`if`, `switch`, `try`, `catch`, `orelse`) into statement-form equivalents using temporary variables.
4.  **Static Analysis**: Lifetime, Null Pointer, and Double Free analyzers run on the lifted AST.
5.  **Metadata Preparation**: Collects all reachable types for module headers to ensure aggregate types (structs/unions) are defined before use.
6.  **Code Generation**:
    -   **Paired Output**: The `CBackend` generates one `.c` and one `.h` file for each Zig module.
    -   **Build Scripts**: Automatically generates `build_target.sh` (POSIX) and `build_target.bat` (MSVC) to orchestrate compilation and linking of the generated C modules.
    -   **Runtime Inclusion**: Copies `zig_runtime.h` and `zig_runtime.c` to the output directory to ensure the project is self-contained.

## Symbol Visibility and Linkage

- **Private Symbols**: Zig functions and variables without `pub` are emitted with the `static` keyword in C, limiting their visibility to the current `.c` file.
- **Public Symbols**: Zig symbols with `pub` are emitted with external linkage and declared in the module's generated `.h` file.
- **Extern Symbols**: `extern` declarations are emitted as `extern` in C and bypass module-based name mangling.

## Resource Management

The compilation model is designed to operate within a strict **<16MB memory limit**:
-   **Arena Allocation**: All AST nodes and analysis metadata are allocated in a multi-tiered arena system (Global, Token, and Transient arenas).
-   **String Interning**: All identifiers and module names are interned.
-   **Token Clearing**: The Token Arena is reset after all modules are parsed, freeing memory before the memory-intensive analysis and codegen phases.
