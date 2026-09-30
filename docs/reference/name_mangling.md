> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Name Mangling Design (Task 161)

This document outlines the name mangling algorithm used by the Z98 bootstrap compiler to ensure C89 compatibility and support unique identification of generic function instantiations.

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

Measured against the seed-built compiler (seed v89). A **function** symbol is
`zF_<hash8>_<name>`: the `zF_` prefix, eight uppercase hex digits from the
function's stable name hash, then the source name. A **type** symbol is
`zT_<hash8>_<shape>`; an anonymous compiler temporary is `zT_<n>`.

| Original | Context | Mangled (measured) |
| :--- | :--- | :--- |
| `main` | `pub fn main` in `hello.z98` | `zF_EA90E208_main` |
| `print` | `std.io.print` | `zF_16378A88_print` |
| `__module_init` | emitter-generated per module | `zF_780653D2___module_init` |
| `close` | `std.net.close` | `zF_27CB3B23_close` |
| `SockAddrIn` | struct type | `zT_4106788D_SockAddrIn` |
| `[2]u8` | array type | `zT_22590979_Arr_unsigned_char_2` |

The eight hex digits keep a name stable across builds and collision-resistant;
the source name is kept as the suffix so the emitted C and a debugger stay
readable.

## Integration

-   **TypeChecker**: Computes and stores mangled names in the `Symbol` table and `GenericCatalogue`.
-   **GenericCatalogue**: Uses mangled names to identify and deduplicate instantiations.
-   **C89FeatureValidator**: Includes mangled names in diagnostics to help developers identify specific generic failures.
