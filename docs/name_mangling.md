# Name Mangling Design (Task 161)

This document outlines the name mangling algorithm used by the RetroZig bootstrap compiler to ensure C89 compatibility and support unique identification of generic function instantiations.

## Goals

1.  **C89 Compatibility**: Ensure all identifiers in the generated C code are valid C89 identifiers (alphanumeric and underscore only, limited length).
2.  **Unique Generic Instantiations**: Provide a unique, deterministic name for each distinct instantiation of a generic function (e.g., `foo(i32)` vs `foo(f64)`).
3.  **Keyword and Reserved Name Avoidance**: Prevent collisions with C keywords (e.g., `if`, `while`) and reserved naming patterns.
4.  **Module Isolation**: Prepare for multi-file support by providing a mechanism to include module prefixes in mangled names.

## Algorithm

The mangling algorithm follows these steps:

1.  **Base Name**: Start with the original identifier name.
2.  **Generic Parameters**: If the function has generic parameters, append `__` followed by a underscored-separated list of mangled types for each parameter.
    -   Example: `max(i32, i32)` -> `max__i32_i32`
3.  **Sanitization**:
    -   All characters that are not alphanumeric or underscore are replaced with `_`.
    -   If the name starts with a digit, it is prefixed with `z_`.
    -   If the name is a C keyword, it is prefixed with `z_`.
    -   If the name starts with an underscore followed by an uppercase letter or another underscore (C reserved naming patterns), it is prefixed with `z` (e.g., `_Test` -> `z_Test`).
4.  **Length Limit**: The final mangled name is truncated to **31 characters** for MSVC 6.0 compatibility.

## Type Mangling

Types are mangled into short, safe strings:

| Zig Type | Mangled |
| :--- | :--- |
| `i32` | `i32` |
| `u8` | `u8` |
| `f64` | `f64` |
| `bool` | `bool` |
| `void` | `void` |
| `*T` | `ptr_T` |
| `[N]T` | `arr_T` |
| `!T` | `err_T` |
| `?T` | `opt_T` |
| `error{A,B}` | `errset_A_B` |
| `type` | `type` |
| `anytype` | `anytype` |

## Examples

| Original | Context | Mangled |
| :--- | :--- | :--- |
| `foo` | Standard Function | `foo` |
| `max` | Generic(i32, i32) | `max__i32_i32` |
| `if` | Function Name | `z_if` |
| `_Test` | Function Name | `z_Test` |
| `!i32` | Type | `err_i32` |
| `?u8` | Type | `opt_u8` |
| `error{A}` | Type | `errset_A` |
| `my_long_function_name_exceeding_31` | - | `my_long_function_name_exceedin` |

## Integration

-   **TypeChecker**: Computes and stores mangled names in the `Symbol` table and `GenericCatalogue`.
-   **GenericCatalogue**: Uses mangled names to identify and deduplicate instantiations.
-   **C89FeatureValidator**: Includes mangled names in diagnostics to help developers identify specific generic failures.
