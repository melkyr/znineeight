# Compiler Gaps Report

This document outlines the current missing or pending features in the RetroZig compiler as of the current development state, based on a comparison between the Design Document, the AI Task Roadmap, and the actual implementation.

## 1. Functional Gaps in Code Generation (C89 Emitter)

While the Parser and TypeChecker support many language constructs, the `C89Emitter` in `src/bootstrap/codegen.cpp` still lacks implementation for several key features:

*   **`defer` Statements**: Task 206 is still a placeholder. The emitter currently outputs a comment `/* defer */` but does not implement the scope-exit logic required for `defer`.
*   **`for` Loops**: The parser supports `for` loops (Task 63, 79), and the TypeChecker validates them (Task 221), but the `C89Emitter` does not yet handle `NODE_FOR_STMT`. It falls back to a comment.
*   **`switch` Expressions**: Similar to `for` loops, `switch` is parsed (Task 64) and type-checked (Task 221), but it is not implemented in the `C89Emitter` (NODE_SWITCH_EXPR).

## 2. Deferred Design Components

*   **PE Backend (`pe_builder.cpp`)**: Section 4.7 of `DESIGN.md` describes a direct Win32 PE executable generator. Currently, `src/bootstrap/pe_builder.cpp` is an empty file. The project has successfully pivoted to a C89 codegen path using external compilers (GCC/MSVC 6.0) to fulfill the bootstrap requirements. Direct PE generation remains a deferred goal for later stages.

## 3. Pending Roadmap Tasks (`AI_tasks.md`)

The following milestones and tasks are currently pending implementation:

*   **Phase 1: The Cross-Compiler (Zig)**:
    *   **Task 223**: Translate the C++ compiler logic into the supported Zig subset.
    *   **Task 224**: Use `zig0.exe` to compile `zig1.exe`.
    *   **Task 225**: Verify `zig1.exe`.
*   **Phase 2: Self-Hosting**:
    *   **Task 226**: Use `zig1.exe` to compile its own source code (`zig2.exe`).
    *   **Task 227**: Perform binary comparison for self-hosting verification.

## 4. Documentation Discrepancies

*   **`DESIGN.md` Checkboxes**: The implementation checklist in `DESIGN.md` (Section 10) is not synchronized with the actual progress recorded in `AI_tasks.md`. Many "Week X" tasks that are functionally complete in the code and marked DONE in `AI_tasks.md` are still unchecked in `DESIGN.md`.
*   **Milestone 4 Status**: `AI_tasks.md` still labels Milestone 4 as "IN PROGRESS" despite all its sub-tasks (81-188) being marked COMPLETE and verified by integration tests.

## 5. Implementation Verification Gaps

*   **Error Recovery**: `DESIGN.md` mentions a sophisticated error recovery strategy (synchronization points, recovery tokens), but the current `Parser::error` implementation simply calls `plat_abort()`, which is a "fatal error" strategy rather than a recovery strategy.
*   **Checked Conversions**: While several `@intCast` helpers are implemented in `zig_runtime.h`, the full matrix of possible numeric conversions is not yet exhaustive.
