# Baptism of Water: Lisp Interpreter - Missing Features and Compiler Challenges

This document details the challenges encountered while building the Z98 Lisp interpreter ("Baptism of Water") using the `retrozig` bootstrap compiler. It highlights the gaps between the current compiler implementation and the requirements of a multi-module project.

## 1. Type Consistency (Cross-Module Type Identity)

### The Problem
The current bootstrap compiler primarily relies on pointer equality (`Type*`) to determine if two types are the same. In a multi-module project, identical types (e.g., `?*LispSand` or `struct EnvNode`) are often instantiated multiple times in the `TypeRegistry` when imported by different modules.

### The Challenge
When `env.zig` returns a `?*EnvNode` and `main.zig` receives it, the compiler may report a "type mismatch" because the `Type*` in `env.zig` points to a different memory address than the `Type*` in `main.zig`, even if they are structurally identical.

### Required Fix
The `TypeChecker`'s `areTypesCompatible` and `IsTypeAssignableTo` methods must be updated to use **structural equality** (`areTypesEqual`) rather than pointer equality for nominal types and their derivatives (pointers, optionals, slices).

**Recommendation:** Implement a global interning mechanism in the `TypeRegistry` that ensures structural duplicates are never registered as distinct `Type` objects.

## 2. Placeholder Resolution and Circular Dependencies

### The Problem
Recursive types (like `Value` containing `Cons` which contains `Value`) and cross-module circular imports lead to the creation of `TYPE_PLACEHOLDER` objects.

### The Challenge
If a placeholder is not correctly finalized or if multiple placeholders for the same type are created, the `TypeChecker` can get stuck or fail to resolve the underlying structure. In some cases, `finalizePlaceholder` was found to lose the original type name, leading to anonymous types in the generated C code which causes compilation errors.

### Required Fix
- Ensure `finalizePlaceholder` unconditionally restores the `name` of the type.
- The `TypeRegistry` should unify placeholders before they are committed.
- Recursive resolution needs to be extremely careful not to enter infinite loops while verifying type completeness.

## 3. The `main` Function Return Type

### The Problem
In Z98, a `main` function returning `!void` is common. The compiler handles this by wrapping `main` in an error-handling structure. However, the C89 backend emits a C `main` function that is expected by the linker to return an `int`.

### The Challenge
The generated C code for a `!void main()` returns an `ErrorUnion_void` (a struct), which causes a C compiler error: `error: return type is an executable type`.

### Workaround
The `C89Emitter` needs a special case for the `main` function. Regardless of the Zig return type, the generated C `main` should always return `0` (success) at the end of its body, or handle the error union by printing the error and returning a non-zero exit code.

## 4. C Code Generation: Identifier Visibility and Lifting

### The Problem
Z98's `try` and `catch` expressions, along with complex control flow, require "expression lifting"—where nested expressions are turned into statements and temporary variables in the generated C code.

### The Challenge
In `main.zig`, the use of `try` inside the REPL loop often results in "use of undeclared identifier" errors in the generated C code. This happens when the compiler lifts an expression into a temporary variable but fails to emit the declaration of that variable in the correct scope or order.

### Required Fix
Improve the `ControlFlowLifter` and `C89Emitter` to ensure that all lifted temporary variables are declared at the top of the function block (C89 requirement) and are properly initialized before use.

## 5. General Recommendations for the Bootstrap Compiler

1. **Standard Library**: Many basic utilities (like `parseInt`, `skipWhitespace`) had to be manually implemented. A minimal `std` module would greatly accelerate development.
2. **Structural Type Registry**: Move from pointer-identity to structural-identity for all types at the registry level.
3. **C89 Compatibility**: Strictly enforce C89 variable declaration rules (at the start of blocks) in the emitter.
4. **Improved Error Reporting**: The compiler sometimes reports errors with garbage characters if strings are not persisted in the permanent arena. (Note: This was partially addressed during the Lisp task).
5. **Pointer to Array Bounds**: Fix the `emitFor` logic to correctly handle `* [N]T` as an iterable by using the fixed size `N`.
