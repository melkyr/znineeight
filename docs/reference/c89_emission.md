# C89 Code Generation Strategy

This document outlines the strategy for emitting C89-compliant code from the RetroZig bootstrap compiler.

## 1. Integer Literals

Integer literals are always emitted in **decimal** format to simplify the emitter and ensure consistent output. The original base (hex, octal, binary) from the Zig source code is not preserved.

### 1.1 Mapping Table

The emission of integer literals depends on their resolved Zig type:

| Zig Type | C89 Emission | Example |
|----------|--------------|---------|
| `i32` | Decimal, no suffix | `42` |
| `u32` | Decimal + `U` suffix | `42U` |
| `i64` | Decimal + `i64` suffix | `42i64` |
| `u64` | Decimal + `ui64` suffix | `42ui64` |
| `i8`, `u8` | Decimal, no suffix | `42` |
| `i16`, `u16` | Decimal, no suffix | `42` |
| `usize` | Decimal, no suffix (maps to `unsigned int`) | `42` |
| `isize` | Decimal, no suffix (maps to `int`) | `42` |

### 1.2 64-bit Suffixes and Compatibility

The suffixes `i64` and `ui64` are specific to **MSVC 6.0**. To support other compilers (like GCC or Clang), a compatibility header (`zig_runtime.h`) is provided. This header defines macros to map these suffixes to the standard `LL` and `ULL` suffixes if possible, or provides other mechanisms for compatibility.

Every generated `.c` file should include `zig_runtime.h` at the top.

## 2. Rationale

- **Decimal-only emission**: Simplifies the internal implementation of the emitter and avoids the need to store the original literal format in the AST.
- **MSVC-first suffixes**: Prioritizes the primary target for bootstrapping (MSVC 6.0) while providing a path for cross-platform testing via the compatibility header.
- **Type-based emission**: Using the resolved type instead of raw lexer flags ensures consistency with the rest of the semantic analysis phase.
