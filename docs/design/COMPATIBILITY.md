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

## Generated C89 Code Compatibility

The Z98 bootstrap compiler generates C89-compliant code intended to be built with legacy toolchains like MSVC 6.0 and OpenWatcom.

### Generated Code Headers

The generated C code relies on a dedicated compatibility header, `src/include/zig_compat.h`, which provides abstractions for C89 environments:

- **ZIG_UNUSED**: Expands to `__attribute__((unused))` on GCC-compatible compilers and to nothing on others (like MSVC 6.0 and OpenWatcom), preventing "unused function" warnings.
- **ZIG_INLINE**: Defined as `static` by default to ensure strict C89 compliance while allowing compilers to inline functions. On MSVC and GCC, it may use compiler-specific keywords like `__inline` or `__inline__`.
- **Fixed-width types**: Maps `i64` and `u64` to `long long` or `__int64` as appropriate.
- **Boolean support**: Provides `bool`, `true`, and `false` typedefs/macros for C89.

All generated `.c` and `.h` files include `zig_runtime.h`, which in turn includes `zig_compat.h`.

### Mixed Declarations and Code

C89 requires all variable declarations to appear at the beginning of a block, before any executable statements.

- **Current Implementation**: The compiler uses a two-pass approach in `C89Emitter::emitBlock` to hoist variable declarations (`NODE_VAR_DECL`) to the top of their respective C blocks.
- **Known Limitation**: Temporaries generated during expression lifting (e.g., in `if` conditions or complex assignments) are currently emitted at their point of use. While many legacy compilers (like MSVC 6.0 and OpenWatcom) are lenient with this, strict C89 compilers may issue warnings or errors.
- **Workaround**: The `ControlFlowLifter` pass ensures most complex control flow is transformed into statement form, which helps in grouping declarations.
- **Future Work**: A full hoisting pass is planned to ensure *all* compiler-generated temporaries are also moved to the top of the block, achieving 100% strict C89 compliance.

### Runtime IO Signature Fix

Standard Zig string literals and slices often use `u8` (`unsigned char`). However, many standard C functions (and the Win32 `WriteConsoleA` API) expect `const char*`.

- **Problem**: Passing `unsigned char*` to functions expecting `char*` produces `pointer-sign` warnings on many compilers.
- **Fix**: The runtime functions `__bootstrap_print`, `__bootstrap_write`, and `__bootstrap_panic` now use `const char*` for their string arguments. Internal casts to `unsigned char*` are performed within the runtime implementation where needed.
- **Generated Code**: The `C89Emitter` explicitly casts string arguments to `(const char*)` when calling these functions. To avoid redefinition errors on MinGW/Win32, the emitter also skips generating redundant C prototypes for these helpers in module source files, relying on the central definition in `zig_runtime.h`.

## Milestone 11 Achievements

The following features were finalized in Milestone 11 and are fully supported by the C89/C++98 compatibility layer:

- **Recursion Support**: Recursive type definitions (structs, unions) are handled via a placeholder resolution mechanism.
- **Anonymous Struct Payloads**: Tagged unions can now have nested anonymous struct payloads, which are correctly decomposed into field assignments in C89.
- **Switch Ranges**: Switch prongs now support inclusive (`...`) and exclusive (`..`) ranges, which are expanded into individual C `case` labels.
- **Payload Captures**: `while` and `if` statements support optional and error union payload captures, implemented via temporary variables and block-scoped declarations.
- **Pointer Arithmetic**: Many-item pointers (`[*]T`) support arithmetic and indexing, mapped directly to C pointer operations.
- **@intToPtr and @ptrToInt**: Supported for low-level memory operations, respecting the target's pointer size.
- **@intToFloat**: Supported for converting integers to floating-point types, with constant folding for literals.
- **Braceless Control Flow**: Single-statement `if`, `while`, and `for` bodies are supported and normalized into braced blocks during the lifting pass.
