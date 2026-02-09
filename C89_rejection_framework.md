# C89 Rejection Framework

This document outlines the features of the Zig language that are intentionally rejected by the bootstrap compiler to ensure strict C89 compatibility. The rejection process is a key part of the compiler's design, preventing the use of modern language constructs that have no direct or simple equivalent in C89.

The framework is implemented in two primary ways:
1.  **AST Pre-Scan:** An immediate check after parsing to find and reject AST nodes corresponding to unsupported language syntax. This is performed by the `C89FeatureValidator` class.
2.  **Type Compatibility Validation:** A system within the `TypeChecker` to reject types that are not compatible with C89. This is primarily handled by the `is_c89_compatible` function.

## AST Pre-Scan Validator

The `C89FeatureValidator` is a visitor class that traverses the entire Abstract Syntax Tree immediately after the parsing stage is complete. Its sole responsibility is to detect AST nodes that represent language features not supported in the C89-compatible subset.

When an unsupported feature is found, the validator performs the following actions:
1.  It uses the `ErrorHandler` to report a fatal error, providing a clear message indicating why the feature is not supported.
2.  It sets an internal `error_found_` flag, which causes the `validate()` method to eventually return `false`.

This approach allows the compiler to collect multiple errors before terminating, providing a better developer experience while still ensuring that no non-C89 code proceed to the generation phase. To maintain stability in test environments, child processes explicitly call `abort()` if the error handler reports any errors.

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
| **`isize`/`usize`**     | `var x: isize = -1;`            | **Yes**             | **Rejected.** These types are pointer-sized integers, which are not supported in the bootstrap phase to ensure predictable behavior. Rejected by the Type System. |
| **Multi-level Pointers**| `var p: **i32 = null;`          | **Yes**             | **Rejected.** Multi-level pointers add unnecessary complexity to the bootstrap type system. Only single-level pointers (`*T`) are allowed. |
| **Function Pointers**   | `var fn_ptr = &my_func;`        | No                  | **Rejected.** While C89 supports function pointers, they are rejected by the bootstrap to simplify the type system and code generation.                  |
| **Struct Methods**      | `my_struct.my_method()`         | No                  | **Rejected.** C89 structs do not have associated functions. The equivalent is passing a struct pointer to a global function.                              |
| **`async`/`await`**     | `async my_func();`              | No                  | **Rejected.** Asynchronous programming is a modern concept with no C89 equivalent.                                                                        |
| **Variadic Functions**  | `fn my_printf(fmt: ..., args) {}` | No                  | **Rejected.** The bootstrap compiler does not support variadic arguments to simplify the calling convention and type checking.                               |
| **`defer`**             | `defer file.close();`           | **Yes**             | **Supported.** While not a C89 keyword, `defer` is implemented via simple code transformation (moving the code to function exit points).                 |
| **`errdefer`**          | `errdefer cleanup();`           | **Yes**             | **Rejected.** Relies on the error handling system which is not supported in C89.                                                                          |
| **Generics**            | `fn max(comptime T: type, ...)` | **Yes**             | **Rejected.** Generic functions (with `comptime` parameters) and calls with explicit type arguments are rejected.                                         |

## Milestone 5 Integration & Translation Strategy

| Zig Feature | Milestone 4 Status | Milestone 5 Translation Strategy | C89 Equivalent |
|-------------|--------------------|-----------------------------------|----------------|
| Error Unions | Rejected | Extraction Strategy (Stack/Arena/Out) | Struct + Union |
| Error Sets | Rejected | Global Integer Registry | #define constants |
| `try` | Rejected | Pattern-based Generation | `if (err) return err;` |
| `catch` | Rejected | Fallback Pattern Generation | `if (err) { val = fallback; }` |
| `orelse` | Rejected | Optional Unwrapping Pattern | `if (val) { ... } else { ... }` |
| `errdefer` | Rejected | Goto-based Cleanup | `goto cleanup;` |
| Generics | Rejected | Template Specialization / Mangling | Mangled Functions |

## Bootstrap-specific restrictions beyond C89

The bootstrap compiler imposes several restrictions that are stricter than C89 itself to simplify the implementation and ensure the robustness of the first compilation stage:

1. **Parameter Count**: Functions are strictly limited to a maximum of **4 parameters**. This ensures compatibility across various legacy calling conventions and stack models.
2. **No Multi-level Pointers**: Even though C89 supports `int**`, the bootstrap compiler only supports `int*` (single-level pointers) to simplify memory analysis and code generation.
3. **No Function Pointers**: Function pointers are rejected as values or parameters to keep the type system minimal.
4. **Explicit Integer Sizes**: `isize` and `usize` are rejected in favor of explicit-width types like `i32` and `u32`, preventing platform-dependent behavior during bootstrapping.
