# Name Collision Rules (Task 152)

This document outlines the rules for name collision detection in the RetroZig bootstrap compiler. These rules are designed to ensure C89 compatibility while respecting core Zig naming principles.

## Bootstrap Compiler Rules

### Rejected Collisions
1.  **Same scope, same name**: Two functions with the same name in the same scope are strictly forbidden. Zig does not support function overloading.
2.  **Function-variable collision**: A function and a variable with the same name in the same scope are rejected. While Zig theoretically allows this in some contexts due to separate namespaces, C89 does not always distinguish them, and rejecting them prevents ambiguous code generation.

### Allowed Constructs
1.  **Shadowing**: An inner scope (e.g., inside a function or a block) can shadow names from an outer scope. This is standard Zig behavior and is compatible with C89.
2.  **Different scopes**: The same name can be used for different entities in non-overlapping scopes without causing a collision.

## Implementation Details

The `NameCollisionDetector` is a dedicated AST traversal pass that runs after parsing and before type checking. It uses a scope-aware stack to track all declared function and variable names, reporting any violations via the `ErrorHandler`.

By moving these checks to a separate pass and removing immediate aborts from the `Parser`, the compiler can now:
-   Identify and report all name collisions in a single pass.
-   Provide more detailed diagnostics, including the location and type of the conflicting entities.
-   Catalog all function signatures and names before proceeding to subsequent compilation stages.

## Examples

### Rejected (Causes compilation error)
```zig
// Same scope collision
fn foo() void {}
fn foo() i32 { return 0; }  // ERROR: Redeclaration of name 'foo'

// Function-variable collision
fn bar() void {}
var bar: i32 = 5;  // ERROR: Redeclaration of name 'bar'
```

### Allowed
```zig
// Shadowing
fn outer() void {
    const x = 1;
    {
        const x = 2; // Shadows outer x, but allowed
    }
}

// Different scopes (no collision)
fn a() void {
    const name = 1;
}
fn b() void {
    const name = 2; // Different scope, allowed
}
```

## Zig Semantics for Reference
-   No function overloading.
-   Shadowing is generally allowed.
-   Zig uses separate namespaces for types, functions, and variables, but the bootstrap compiler enforces a stricter unified check for C89 compatibility.
