# C89 Rejection Framework

This document outlines the features of the Zig language that are intentionally rejected by the bootstrap compiler to ensure strict C89 compatibility. The rejection process is a key part of the compiler's design, preventing the use of modern language constructs that have no direct or simple equivalent in C89.

The framework is implemented in two primary ways:
1.  **AST Pre-Scan:** An immediate check after parsing to find and reject AST nodes corresponding to unsupported language syntax. This is performed by the `C89FeatureValidator` class.
2.  **Type Compatibility Validation:** A system within the `TypeChecker` to reject types that are not compatible with C89. This is primarily handled by the `is_c89_compatible` function.

## AST Pre-Scan Validator

The `C89FeatureValidator` is a visitor class that traverses the entire Abstract Syntax Tree immediately after the parsing stage is complete. Its sole responsibility is to detect AST nodes that represent language features not supported in the C89-compatible subset.

When an unsupported feature is found, the validator performs the following actions:
1.  It uses the `ErrorHandler` to report a fatal error, providing a clear message indicating why the feature is not supported.
2.  It immediately calls `abort()` to halt the compilation process.

This "fail-fast" approach prevents the `TypeChecker` and subsequent compilation stages from ever having to deal with language constructs that cannot be translated to C89.

## Feature Compatibility Table

The following table details the Zig features that are rejected and provides the rationale for their exclusion.

| Feature                 | Zig Syntax Example              | Supported by Parser | Rejection Status & Rationale                                                                                                                              |
| ----------------------- | ------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Slices**              | `var my_slice: []u8;`            | **Yes**             | **Rejected.** Slices are a core Zig feature but require a struct (`{ptr, len}`) and runtime support that do not exist in C89. Rejected by the AST Pre-Scan. |
| **Error Unions**        | `var value: !i32;`              | **Yes**             | **Rejected.** Error handling with `!` is a Zig-specific concept. C89 uses error codes or `errno`. Rejected by the AST Pre-Scan (`try`, `catch`).        |
| **Optionals**           | `var value: ?*i32;`             | No                  | **Rejected.** Optionals are implemented as tagged unions or pointers, which is a higher-level concept than what C89 supports directly.                      |
| **`try` Expression**    | `try fallible_func();`          | **Yes**             | **Rejected.** Directly tied to error unions. Rejected by the AST Pre-Scan.                                                                                |
| **`catch` Expression**  | `fallible_func() catch 0;`      | **Yes**             | **Rejected.** Directly tied to error unions. Rejected by the AST Pre-Scan.                                                                                |
| **`orelse` Expression** | `optional_val orelse default;`  | **Yes**             | **Rejected.** Tied to optionals and error unions. Rejected by the AST Pre-Scan.                                                                           |
| **`isize`/`usize`**     | `var x: isize = -1;`            | **Yes**             | **Rejected.** These types are pointer-sized integers, which are not a concept in C89 where `int` or `long` is used. Rejected by the Type System.           |
| **Function Pointers**   | `var fn_ptr = &my_func;`        | No                  | **Rejected.** While C89 supports function pointers, they are rejected by the bootstrap to simplify the type system and code generation.                  |
| **Struct Methods**      | `my_struct.my_method()`         | No                  | **Rejected.** C89 structs do not have associated functions. The equivalent is passing a struct pointer to a global function.                              |
| **`async`/`await`**     | `async my_func();`              | No                  | **Rejected.** Asynchronous programming is a modern concept with no C89 equivalent.                                                                        |
| **Variadic Functions**  | `fn my_printf(fmt: ..., args) {}` | No                  | **Rejected.** The bootstrap compiler does not support variadic arguments to simplify the calling convention and type checking.                               |
