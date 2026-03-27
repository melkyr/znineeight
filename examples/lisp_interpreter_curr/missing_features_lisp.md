# Detailed Findings from the Lisp Interpreter "Baptism of Water"

This document records the issues, bugs, and limitations discovered while attempting to compile and run both downgraded and advanced Z98 Lisp interpreters.

## 1. Summary of Results

| Version | Status | Notes |
|---------|--------|-------|
| Downgraded (`lisp_interpreter`) | **SUCCESS** | Baseline is stable in 32-bit mode. |
| Intermediate (`lisp_interpreter_curr`) | **SUCCESS** | Fixed a symbol memory bug. Basic Lisp works. |
| Advanced (`lisp_interpreter_adv`) | **FAILED** | Blocked by multiple C89 codegen issues (anonymous structs). |

## 2. Portability & Compatibility Reports

### 32-bit Compatibility (`-m32`)
- **Status**: **SUCCESS**.
- **Observations**: The compiler and generated code run correctly in 32-bit mode. This is essential for the 1998 target.

### Windows Compatibility (Mingw-w64 + Wine)
- **Status**: **SUCCESS**.
- **Observations**:
    - Successfully cross-compiled `lisp_interpreter_curr` to a 32-bit Windows `.exe`.
    - Successfully ran basic expressions (e.g., `(+ 1 2)`) under `wine`.
    - **Note**: Had to increase the stack size (`-Wl,--stack,16777216`) to avoid stack overflow exceptions in `wine` due to the recursive nature of the evaluator and how `wine` handles stack committed pages.

### Compiler Portability (Clang++)
- **Status**: **SUCCESS**.
- **Observations**: `zig0` (the bootstrap compiler) compiles successfully with `clang++` and correctly generates C code.

### Standard Library Portability (Musl-gcc)
- **Status**: **PARTIAL SUCCESS / BUG FOUND**.
- **Observations**:
    - Building the generated C code with `musl-gcc` (64-bit) resulted in a **Segmentation Fault** during symbol lookup.
    - **Analysis**: Musl's `string.h` and memory layout differ from GLIBC. The crash occurred in `env_lookup`, suggesting that some pointer-to-integer casts or alignment assumptions in the C89 generator might be incompatible with Musl's strictness.
    - 32-bit Musl compilation failed due to missing `__divdi3` and other libgcc symbols in the environment.

## 3. Verified Compiler & Interpreter Bugs

### Issue: Symbol Name Corruption (FIXED in `curr`)
- **Problem**: Symbol names were stored as slices pointing to the temporary line buffer. Reading a new line corrupted previous symbols.
- **Fix**: Modified `parser.zig` to copy symbol names into permanent memory during parsing.

### Issue: `memcpy` and `<string.h>`
- **Problem**: The compiler generates `memcpy` calls for `switch` captures but fails to include `<string.h>`.
- **Status**: Warning only, but should be fixed in the compiler for strict C89 compliance.

### Issue: Recursion/Scoping in `lisp_interpreter_curr`
- **Problem**: Recursive functions (e.g., `factorial`) fail with `UnboundSymbol`.
- **Reason**: The interpreter captures the environment *at the time of lambda creation*. Since the function name is added to the environment *after* the lambda is created, the lambda's captured environment does not contain itself.
- **Status**: Documented as a limitation of the current interpreter implementation.

## 4. Summary of Advanced Version Blockers (from `lisp_interpreter_adv`)

### Issue 1: Missing Definitions for Anonymous Structs (BLOCKER)
When a `union(enum)` variant uses an anonymous struct, the compiler declares but **never defines** this struct in the generated C code.

### Issue 2: Cross-Module Visibility and Inclusions
Dependent module headers are not always included in the correct order, or types are used before they are fully defined in the header.

### Issue 3: `union(enum)` Tag Assignment (Precedence Bug)
Assigning a tag literal to a dereferenced union pointer (e.g., `t.* = .Eof`) generates invalid C precedence: `*t.tag` instead of `(*t).tag`.

## Conclusion
The intermediate interpreter (`lisp_interpreter_curr`) is a viable target for Win98-era systems and 32-bit environments. However, standard library portability (Musl) and advanced language features (anonymous structs in unions) still require compiler-side fixes to achieve the full "Baptism of Water" goals.
