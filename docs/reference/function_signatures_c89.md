> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Function Signature Analysis for C89 (Task 153)

## Overview
Standard C89 has specific limitations and conventions regarding function signatures. The Z98 bootstrap compiler implements a signature analysis pass to ensure that Zig function signatures can be portably translated to C89, specifically targeting the MSVC 6.0 environment.

## Supported Signature Patterns

As of Milestone 11, the following are supported in function signatures (parameters and return types):

### 1. Primitive Types
All Z98 primitive types (`i8`-`i64`, `u8`-`u64`, `isize`, `usize`, `f32`, `f64`, `bool`, `void`).

### 2. Pointers and Slices
- **Pointers**: `*T`, `[*]T`, and multi-level pointers (e.g., `**T`) are fully supported.
- **Slices**: `[]T` and `[]const T` are supported. They are passed by value as C structs `{ T* ptr, usize len }`.

### 3. Error Unions and Optionals
- **Error Unions**: `!T` or `ErrorSet!T` are supported. When used as a return type, they allow the use of `try` and `catch` in the caller.
- **Optional Types**: `?T` is supported.
- **Note**: Both are passed/returned by value as C structs. Optional pointers (`?*T`) are automatically optimized to raw C pointers at `extern`/`export` boundaries for ABI compatibility.

### 4. Aggregates
- **Structs**: Supported. Passed by value.
- **Enums**: Supported. Mapped to C enums/integers.
- **Tagged Unions**: Supported. Passed by value.

## Rejected Signature Patterns

### 1. Anonymous Aggregates
Functions cannot use anonymous structs/unions/enums in their signatures. All types must be named via `const` assignment.

### 2. Parameter Count Limits
- **Parameter Count**: Functions follow standard C89 parameter limits (at least 31).

### 3. Array Return Types
Functions returning arrays (e.g., `fn f() [3]i32`) are strictly rejected by the `TypeChecker` as C89 does not support returning arrays by value.

## Type Alias Resolution
Signature analysis is performed after type resolution. This means type aliases are fully resolved to their underlying types before validation:
```zig
const MyInt = i32;
fn foo(a: MyInt) void {} // Treated as fn foo(a: i32) - ALLOWED
```

## Array Parameters (Warning)
Zig sized arrays (e.g., `[10]i32`) are allowed in function parameters but trigger a warning (`WARN_ARRAY_PARAMETER`), as they are treated as pointers in the generated C89 code, losing their size information in the signature.

## Implementation Details
The signature analysis pass executes after the `TypeChecker` has resolved all types. This allows for precise, type-aware diagnostics.
