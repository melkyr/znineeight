# Z98 C89/C++98 Compatibility Strategy

This document describes the strategy and implementation details for ensuring the Z98 bootstrap compiler (`zig0`) can be built with legacy C++98 compilers (such as MSVC 6.0 and OpenWatcom) and that it generates C89-compliant code.

## Goals

1.  **Compiler Portability**: The bootstrap compiler source must be strict C++98, avoiding modern features like `long long` (use `i64`/`u64`), `nullptr` (use `NULL`), and C++11 standard library additions.
2.  **Generated Code Compliance**: The C code emitted by `zig0` must be valid C89, conforming to definition-before-statement rules and avoiding non-standard extensions unless wrapped in compatibility macros.
3.  **Platform Abstraction**: Use a centralized compatibility layer to handle compiler-specific quirks (e.g., MSVC 6.0's `__int64` and `__inline`).

## Compatibility Layer: `compat.hpp`

The `src/include/compat.hpp` header is the single source of truth for compiler and target abstractions. It provides:

-   **Compiler Detection**: Macros like `ZIG_COMPILER_MSVC` and `ZIG_COMPILER_OPENWATCOM`.
-   **Fixed-Width Types**: Definitions for `i8`, `u8`, `i32`, `u32`, `i64`, `u64`, etc., using compiler-specific extensions where necessary (e.g., `__int64` on MSVC).
-   **Boolean Fallback**: Defines `bool`, `true`, and `false` for compilers that lack a built-in boolean type in C mode or pre-standard C++.
-   **Keyword Abstractions**: `ZIG_INLINE` resolves to `inline` or `__inline`.
-   **Literal Suffixes**: `ZIG_I64_SUFFIX` and `ZIG_UI64_SUFFIX` for consistent 64-bit literal emission.
-   **Warning Suppression**: `RETR_UNUSED(x)` to silence unused parameter/variable warnings.

## Guidelines for Compiler Source (`src/bootstrap/`)

-   **Include `common.hpp`**: All source files should include `common.hpp`, which in turn includes `compat.hpp`.
-   **Avoid `long long`**: Use the `i64` and `u64` typedefs instead of `long long` or `unsigned long long` to ensure compatibility with MSVC 6.0.
-   **No `<stdint.h>` or `<cstddef>`**: Use `common.hpp` which provides `size_t` and fixed-width types via `compat.hpp`.
-   **Silence Warnings**: Use `RETR_UNUSED(param)` at the beginning of functions with unused parameters to maintain a warning-free build on strict compilers.

## Verification

To verify C++98 compliance of the compiler source, compile with:

```bash
g++ -std=c++98 -pedantic -Wunused-parameter -Werror -Isrc/include -c src/bootstrap/*.cpp
```

Phase 1 of the compatibility plan ensures that this command passes for all core compiler files.
