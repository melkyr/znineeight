# Function Signature Analysis for C89 (Task 153)

## Overview
Standard C89 has specific limitations and conventions regarding function signatures that modern Zig does not share. The RetroZig bootstrap compiler implements a `SignatureAnalyzer` pass to detect and reject signatures that cannot be easily or portably translated to C89, specifically targeting the MSVC 6.0 environment.

## Rejected Signature Patterns

### 1. Non-C89 Types in Parameters
The following types are strictly rejected when used as function parameters in the bootstrap phase:
- **Slices**: `[]T` (Rejected as they lack a direct primitive mapping in C89)
- **Error Unions**: `!T` or `E!T` (Rejected as error handling is handled via alternative designs in C89)
- **Error Sets**: `error{...}` (Rejected as they are not compatible with C89 function signatures)
- **Optional Types**: `?T` (Rejected as nullability is handled differently in C89)

### 2. Multi-level Pointers
- **Multi-level Pointers**: `* * T` (and deeper) are rejected to avoid complexity in the bootstrap translation and to maintain compatibility with simpler C89 patterns. Only single-level pointers (e.g., `*i32`, `*const u8`) are allowed.

### 3. Parameter Count Limits
- **Maximum 4 Parameters**: To ensure compatibility with conservative stack management and calling conventions on 1998-era hardware (specifically MSVC 6.0), functions are limited to a maximum of 4 parameters. Signatures with more than 4 parameters are rejected.

### 4. Void Parameters
- Parameters cannot have the `void` type.

## Type Alias Resolution
Signature analysis is performed after type resolution. This means type aliases are fully resolved to their underlying types before validation:
```zig
const MyInt = i32;
fn foo(a: MyInt) void {} // Treated as fn foo(a: i32) - ALLOWED
```

## C89-Compatible Signatures

### Allowed Constructs
- **Primitive Types**: `i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `isize`, `usize`, `f32`, `f64`, `bool`.
- **Single-level Pointers**: `*T` or `*const T` (where T is a C89-compatible type).
- **Enums**: Zig enums are allowed as they map to C89 integers/enums.
- **Structs**: Structs are allowed as parameters if their fields are C89-compatible.
- **Up to 4 Parameters**.

### Array Parameters (Warning)
Zig sized arrays (e.g., `[10]i32`) are allowed in function parameters but trigger a warning (`WARN_ARRAY_PARAMETER`), as they are treated as pointers in the generated C89 code, losing their size information in the signature.

## Implementation Details
The `SignatureAnalyzer` runs as Pass 0.5 in the compilation pipeline, executing after the `TypeChecker` (Pass 0) has resolved all types but before the `C89FeatureValidator` (Pass 1) performs general feature rejection. This allows for precise, type-aware diagnostics.
