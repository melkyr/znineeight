# AST Lifting Strategies: Technical Design

This document describes the "lifting" mechanism used by the RetroZig bootstrap compiler to translate Zig expressions with control flow into C89-compliant code.

## 1. Overview

In Zig, constructs like `if`, `switch`, `try`, `catch`, and `orelse` are expressions that yield values. However, C89 does not support control flow within expressions. To bridge this gap, the compiler performs **AST Lifting**: it transforms these expressions into statement-based equivalents using temporary variables before code generation.

## 2. Core Mechanism: The `ControlFlowLifter` (Pass 5)

Lifting is performed by a dedicated AST pass, the `ControlFlowLifter`, which runs after type checking. This ensures that the code generator never encounters nested control-flow expressions, significantly simplifying C89 emission.

### 2.1 Parent-Slot Traversal Pattern
The lifter performs a post-order traversal of the AST using a "Parent-Slot" pattern. It receives pointers to AST node slots (`ASTNode**`), allowing it to replace nodes in-place without needing to manually track sibling indices or parent pointers.

### 2.2 Decision Logic (`needsLifting`)
The lifter identifies control-flow expressions that appear in "unsafe" contexts (e.g., nested inside a binary operation, a function call argument, or a struct initializer). Root expressions that are already statements (like the expression in an `NODE_EXPRESSION_STMT`) generally do not need lifting unless they contain further nested control flow.

### 2.3 Lifting Primitive (`liftNode`)
When an expression needs lifting, the lifter:
1.  **Generates a Temporary Variable**: Creates a unique, interned name like `__tmp_if_5_1`. The name includes the current lifting depth and a counter to ensure global uniqueness.
2.  **Symbol Registration**: Registers a new `Symbol` for the temporary in the current module's `SymbolTable`.
3.  **Statement Lowering**: Transforms the expression into a series of statements (variable declaration and primitive control flow) that assign the result to the temporary.
4.  **Insertion**: Inserts these statements into the enclosing block immediately before the current statement, preserving the original execution order of side effects.
5.  **Replacement**: Replaces the original expression node with a simple `NODE_IDENTIFIER` referencing the temporary variable.

## 3. Detailed Construct Strategies

### 3.1 `if` and `switch` Expressions
Lifted into their statement-form counterparts (`NODE_IF_STMT`, `NODE_SWITCH_STMT`).
- **Assignment**: Each yielding branch in the lifted construct is updated to assign its final value to the temporary variable.
- **Top-Down Transformation**: Input children (like the condition or switched expression) are transformed first to handle nested lifting correctly.

### 3.2 `try` Expressions
Lifted into an `if` statement that checks the `is_error` flag of the error union.
- **Propagation**: On error, it executes active `defer` statements and returns the error union.
- **Success**: On success, it unwraps the payload and assigns it to the temporary variable.

### 3.3 `catch` and `orelse` Expressions
Lifted into an `if-else` statement.
- **`catch`**: Checks `is_error`. If true, evaluates the fallback (potentially capturing the error). If false, yields the payload.
- **`orelse`**: Checks `has_value`. If false, evaluates the fallback. If true, yields the value.
- **Nesting**: Both constructs wrap their lowering logic in mandatory scoped blocks to handle potential nested lifting within the fallback branches.

## 4. Complex Lvalue Handling
For assignments to complex lvalues (like `s.field = try foo()`), the lifter evaluates the RHS first and stores it in a temporary. This ensures that the lvalue evaluation (which might have side effects) happens after the potentially-failing control flow, matching Zig's evaluation order.

## 5. C89 Mapping Decisions (Name Mangling)

To ensure that compiler-generated symbols never collide with user-defined identifiers, a specialized bypass mechanism is used in the `NameMangler` and `CVariableAllocator`:

- **Internal Identifiers**: Identified by prefixes like `__tmp_`, `__return_`, `__bootstrap_`. These bypass all mangling (module prefixing, keyword avoidance) and are emitted verbatim (truncated to 31 characters).
- **User Symbol Protection**: User-defined identifiers starting with `__` are automatically mangled (e.g., prepended with `z_`) to avoid collisions with internal compiler symbols.

## 6. Technical Constraints

### 6.1 Stack Usage
The lifter uses a recursion depth guard (`MAX_LIFTING_DEPTH = 200`) to prevent stack overflow on memory-constrained 1990s hardware.

### 6.2 Memory Overhead
Lifting increases the size of the AST and the number of local variables. Every generated temporary is allocated from the `ArenaAllocator` and persists for the lifetime of the module compilation.

## 7. Conclusion

By moving control-flow lifting to a dedicated AST pass, the RetroZig compiler achieves a clean separation between high-level language semantics and low-level C89 emission. This strategy improves robustness, simplifies the emitter, and provides a solid foundation for supporting more complex Zig features in a restricted target environment.
