# MSVC 6.0 Compatibility Guide

This document summarizes the specific constraints and strategies used in the RetroZig compiler to ensure compatibility with Microsoft Visual C++ 6.0 and the C++98 standard.

## 1. Core Language & STL

- **Standard**: C++98 (max). No C++11 or later features (no `auto`, `nullptr`, `static_assert`, lambdas, etc.).
- **STL Usage**: Strictly limited. Avoid `std::vector`, `std::map`, and other heavy containers due to fragmented support and potential binary size bloat. Use the project's own `DynamicArray` and `ArenaAllocator`.
- **Booleans**: If `bool`, `true`, or `false` are missing in the environment, they must be defined manually.
- **Integers**: Use `__int64` for 64-bit integers on MSVC 6.0 instead of `long long`.

## 2. Template Handling

MSVC 6.0 has notoriously buggy template support. To avoid Internal Compiler Errors (ICE) and silent corruption:

- **Pass by Reference/Pointer**: Never pass `DynamicArray` or other templates by value. Always use `const T&` or `T*`.
- **Avoid Nesting**: Do not nest templates deeply (e.g., `DynamicArray<DynamicArray<T>>`). Use flat structures or intermediate `typedef`s.
- **Explicit Instantiation**: If a template is used across multiple translation units, consider explicit instantiation in a single `.cpp` file.

## 3. Structs & PODs

- **Safe Copying**: For simple structs like `Symbol`, which only contain scalar types (pointers, enums, `int`, `bool`), default copy semantics are safe. These are treated as POD (Plain Old Data) types.
- **Memory Layout**: Do not rely on specific padding or alignment unless explicitly handled.

## 4. Compiler Warnings & Hardening

- **Signed/Unsigned Mismatches**: MSVC 6.0 is strict about comparisons between signed `int` and unsigned `size_t`. Always use explicit casts when comparing loop indices to container lengths:
  ```cpp
  for (int i = (int)list.length() - 1; i >= 0; --i)
  ```
- **RAII Guards**: Use simple stack-based guards (like `ScopeGuard` in the parser) to manage state. Avoid complex destructor logic that might trigger compiler bugs.
- **Top-of-Block Declarations**: While C++98 allows declarations anywhere, some older MSVC versions (and C89 compatibility) prefer or require variables to be declared at the beginning of a scope.
