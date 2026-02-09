# RetroZig Compiler - AI Agent Guidelines

## Overview

This document outlines the roles, responsibilities, development methodology, constraints, and communication protocols for AI agents working on the RetroZig compiler project. It serves as a guide for both human developers initiating requests and the AI agents executing them.

## Project Context

- **Goal**: Develop a C++98 compatible compiler capable of running on circa 1998 hardware/software environments.
- **Constraints**:
    - **Language Standard**: C++98.
    - **Memory Limit**: Significantly less than 16MB peak usage.
    - **Dependencies**: Win32 API (kernel32.dll) only. No third-party libraries.
    - **Compiler Compatibility**: Must work with older toolchains (e.g., MSVC 6.0 quirks like `__int64`).

## Current Status: Milestone 4 (Task 166)

We are implementing the bootstrap type system and semantic analysis with strict C89 compatibility constraints.

### Key Architectural Components

1. **Multi-Phase Compilation Pipeline** (`CompilationUnit::performFullPipeline`)
2. **Feature Detection & Rejection** (`C89FeatureValidator`)
3. **Comprehensive Cataloguing** (9 specialized catalogues)
4. **Pass-Based Semantic Analysis** (Type checking → Validation → Lifetime → Null pointer → Double free)

## AI Agent Role: Specialized Compiler Implementer

The AI agent acts as a focused, knowledgeable assistant for implementing specific, well-defined tasks within the compiler project.

### Responsibilities of the AI Agent

1. **Interpret Tasks**: Accurately parse and understand the task description provided in `AI_tasks.md`.
2. **Consult Documentation**: Read and comprehend relevant project documents (`Design.md`, `lexer.md`, `AST_parser.md`, etc.) before implementing.
3. **Adhere to Constraints**: Strictly follow all technical constraints (C++98, memory limits, dependencies) without deviation.
    - **C++ Standard Library Usage Policy**:
        - **Allowed**: Headers that are generally implemented by the compiler and have no external runtime library dependencies or hidden memory allocations. This includes headers like `<new>` (for placement new), `<cstddef>` (for size_t), `<cassert>` (for assert), and `<climits>`.
        - **Forbidden**: Headers that depend on a C/C++ runtime library (like msvcrt.dll beyond kernel32.dll) or perform dynamic memory allocation. This includes headers like `<cstdio>` (fprintf), `<cstdlib>` (malloc), `<iostream>`, `<string>` (std::string), and `<vector>` (std::vector).
        - **Exceptions**:
            - `<cstdlib>`: Allowed *only* for `abort()` (for fatal error handling in the parser), and `strtol`/`strtod` (for number parsing in the lexer). Direct memory management functions like `malloc` and `free` are strictly forbidden; use `plat_alloc` and `plat_free` instead.
    - **Platform Abstraction Layer (PAL)**:
        - All system-level operations (memory, files, console) MUST use the PAL (`platform.hpp`) to ensure compatibility and ease of development across Windows and Linux.
4. **Implement Code**: Generate C++ code (.h, .cpp files) that fulfills the task requirements, considering architecture principles like Arena Allocation and string interning.
5. **Document Changes**: Update existing documentation (e.g., `AST_parser.md`) and add Doxygen-style comments to the generated code.
6. **Task Review**: Review completed tasks for architectural alignment and completeness.
7. **Seek Clarification**: When encountering ambiguity in task specifications or required decisions not covered by documentation, explicitly ask for clarification rather than making assumptions.
8. **Follow Methodology**: Implement code with a Test-Driven Development (TDD) mindset, ensuring modularity and correctness for future testing phases.

## Memory Management Protocol (Task 166+)

### Persistent Instrumentation
The codebase now contains persistent memory instrumentation guarded by `#ifdef MEASURE_MEMORY`. This instrumentation MUST remain in the codebase to facilitate ongoing memory analysis and regression testing.

### Phase-Aware Analysis Required
All memory-related work must track usage across compilation phases:
1. **Lexing & Parsing**: AST node creation, string interning
2. **Type Checking**: Type objects, symbol table expansion
3. **C89 Validation**: Catalogue population
4. **Semantic Analysis**: Analysis state tracking
5. **Code Generation**: Output buffers

### Catalogue Memory Overhead
The compiler maintains 9 catalogues for feature tracking. Memory impact:
- `ErrorSetCatalogue`: Error set definitions and merges
- `GenericCatalogue`: Generic function instantiations
- `ErrorFunctionCatalogue`: Error-returning functions
- Try/Catch/Orelse catalogues: Error handling patterns
- `ExtractionAnalysisCatalogue`: C89 translation strategies
- `ErrDeferCatalogue`: Errdefer statements
- `IndirectCallCatalogue`: Function pointer calls

**Guideline**: When implementing catalogue features, estimate memory per entry (≈ 32-64 bytes).

### Optimization Priority List
When memory exceeds thresholds, optimize in this order:
1. **Catalogue entries** (largest potential savings)
2. **AST node allocations** (biggest baseline consumer)
3. **Type object sharing** (reduce duplication)
4. **String interning** (hash table optimization)
5. **Phase memory reuse** (arena reset between phases)
   
## Communication Protocol for Human Developers

When instructing the AI agent, provide a structured prompt that includes:
- **Clear Objective**: State the specific task number and name (e.g., "Implement Task 40: Foundational Parser/AST").
- **Reference Materials**: Explicitly list the key documents the agent should consult.
- **Reiterate Constraints**: Remind the agent of the critical technical limitations.
- **Specify Deliverables**: Outline the expected outputs.
- **Encourage Questions**: Invite the agent to ask for clarification if needed.

## Implementation Guidelines

### For New Features
1. **Memory Estimate First**: Calculate expected memory impact before coding.
2. **Phase Placement**: Place features in appropriate compilation phase.
3. **Catalogue Strategy**: Decide if feature needs cataloguing or can be rejected immediately.
4. **Testing**: Include memory assertions in unit tests where practical.

### For Memory Optimization
1. **Profile Before Optimizing**: Use `MEASURE_MEMORY` and `scripts/memory/analyze_compiler_memory.sh` to identify hotspots.
2. **Focus on Catalogue Growth**: Largest potential for savings.
3. **Consider Lazy Allocation**: Only allocate when feature is actually used.
4. **Shared Structures**: Reuse common objects (types, error sets).

### Critical Files for Memory Analysis
- `src/include/compilation_unit.hpp` - Pipeline orchestration
- `src/include/type_checker.hpp` - Type system memory
- `src/include/c89_feature_validator.hpp` - Rejection framework
- `src/include/memory.hpp` - Arena allocator & MemoryTracker
- All catalogue header files

## Testing Requirements
All memory-related changes require:
1. **Unit tests** with memory assertions.
2. **Integration test** with compiler subset (`test/compiler_subset.zig`).
3. **Valgrind clean** (no leaks).
