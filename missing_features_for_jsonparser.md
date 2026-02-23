# Missing Features and Issues for JSON Parser

During the "Baptism of Fire" using the JSON parser example, several critical issues and missing features were identified in the Z98 bootstrap compiler.

## Critical Bugs

### 1. Infinite Recursion in Recursive Types
The `TypeChecker` (specifically `visitStructDecl` and `visitUnionDecl`) does not handle recursive or mutually recursive types correctly. When a type references itself (e.g., `JsonValue` contains a slice of `JsonValue`), the compiler enters infinite recursion until it hits a stack overflow or segmentation fault.
*   **Status**: Identified. Needs a placeholder type strategy to break recursion.

### 2. Cross-Module Enum Member Access
Accessing enum members from a different module using the module prefix (e.g., `json.JsonValueTag.Number`) fails. The `TypeChecker` reports that the enum has no such member, even if it is correctly defined in the imported module.
*   **Status**: Identified. Likely an issue in `visitMemberAccess` when handling `TYPE_MODULE` or `TYPE_ENUM`.

### 3. TypeInterner Memory Corruption
The `TypeInterner` was missing a modulo operator in its hashing logic, leading to potential out-of-bounds access in the bucket array.
*   **Status**: **FIXED** in `src/bootstrap/type_system.cpp`.

### 4. Segmentation Fault in Optional Types
A segmentation fault occurs when processing optional types (e.g., `?File`). This may be a side effect of the recursive type issue or a separate bug in `createOptionalType` or the interner.
*   **Status**: Identified.

## Missing Features / Z98 Deviations

### 1. Tagged Union Captures in Switch
The current compiler does not fully support Zig-style tagged union captures in `switch` statements (e.g., `switch (val) { .Number => |n| ... }`).
*   **Workaround**: Use bare unions with explicit tag enums and manual field access.

### 2. Braceless Control Flow
While the spec allows braceless `if` and `while` for single statements, the compiler's stability improved when using explicit braces in the JSON parser example.

### 3. Implicit Casting in Unions
Explicit casts or careful manual initialization is required for union members in the bootstrap phase to ensure C89 compatibility and avoid compiler crashes.

## Conclusion
The compiler is not yet "production-ready" for the full JSON parser example. The immediate priority is fixing the recursive type handling and cross-module symbol resolution.
