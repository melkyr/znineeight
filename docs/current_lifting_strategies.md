# C89 Lifting Strategies: Technical Design

This document describes the "lifting" mechanism used by the RetroZig bootstrap compiler to translate Zig expressions with control flow into C89-compliant code.

## 1. Overview

In Zig, constructs like `if`, `switch`, `try`, `catch`, and `orelse` are expressions that yield values. However, C89 does not support control flow within expressions. To bridge this gap, the `C89Emitter` performs **lifting**: it transforms these expressions into one or more C statements (typically inside a scoped block) that assign the result to a temporary variable or a direct target.

## 2. Core Mechanism

### 2.1 The `emitAssignmentWithLifting` Hub
Lifting logic is centralized in `C89Emitter::emitAssignmentWithLifting`. This function serves as a unified dispatcher for any operation that behaves like an assignment (variable declaration, return statement, or explicit assignment) where the right-hand side (RHS) might require control-flow lifting or type coercion.

Key responsibilities:
- **Lifting Dispatch**: If the RHS is an `if`, `switch`, `try`, `catch`, or `orelse` expression, it delegates to the corresponding `emit*Expr` function, passing the target variable and target type.
- **Type Coercion**: If the target type is an `ErrorUnion` or `Optional` but the RHS is a compatible payload type, it automatically invokes wrapping logic (`emitErrorUnionWrapping` or `emitOptionalWrapping`).
- **Initializer Decomposition**: If the RHS is a struct or array initializer, it decomposes it into individual C field assignments.
- **Discard Handling**: If the target is the blank identifier `_` or NULL, it evaluates the RHS for side effects, using `(void)` casts or side-effect-only lifting.

### 2.2 The `target_var` Strategy
Lifting functions (e.g., `emitTryExpr`, `emitIfExpr`) take a `const char* target_var` and an optional `Type* target_type`.
- If `target_var` is **non-NULL**, the logic generates an assignment to that variable.
- If `target_var` is **NULL**, the expression is evaluated solely for its side effects.
- `target_type` ensures that nested results are correctly coerced into the top-level target type (e.g., a payload inside a branch being wrapped into an error union return).

### 2.2 Scoped Blocks
Most lifted expressions are wrapped in a C block `{ ... }`. This allows the emitter to:
1. Declare temporary variables (like `__try_res`) that are local to the lifting operation.
2. Comply with C89's rule that all declarations must appear at the start of a block.

### 2.3 Temporary Result Variables
For complex contexts like `return try foo()`, the emitter generates a temporary result variable (e.g., `__return_val`) to hold the expression's value while other logic (like `defer` statements) is executed.

## 3. Detailed Construct Strategies

### 3.1 `if` Expressions
Lifted into a C `if-else` statement.
- **Nesting**: Each branch body is emitted via `emitAssignmentWithLifting`. This provides **full recursive support** for nested `if`, `switch`, `try`, `catch`, and `orelse` within both `then` and `else` branches.
- **Divergence**: If a branch ends in `return`, `break`, or `continue`, the assignment is skipped for that branch as the code path diverges.
- **Optional Capture**: If the condition is an optional type, a temporary `opt_tmp` is used to prevent double-evaluation of the condition.

### 3.2 `switch` Expressions
Lifted into a C `switch` statement.
- **Nesting**: Each prong body is emitted via `emitAssignmentWithLifting`, enabling uniform nesting of all lifted constructs.
- **Divergence**: Like `if` branches, divergent prongs skip the assignment to `target_var`.

### 3.3 `try` Expressions
Lifted into an `if` check for the `is_error` flag.
- **Propagation**: If an error is detected, the emitter executes active `defer` statements and returns the error.
- **Success**: The payload is assigned to `target_var`, potentially involving wrapping if `target_type` is itself an error union or optional.
- **Limitation**: The operand of `try` (the expression being tried) must currently be a simple expression, though it can be a function call.

### 3.4 `catch` and `orelse` Expressions
Lifted into an `if-else` check.
- **Success/Value**: The payload/value is assigned to `target_var`, with support for type coercion.
- **Fallback/Nesting**: The fallback branch is emitted via `emitAssignmentWithLifting`, providing **full recursive support** for all other lifted constructs.

## 4. Nesting Support Matrix

The following table describes which constructs can be nested inside others. As of Task 9.5.5, the implementation provides uniform support for nesting all lifted constructs within branches, prongs, and fallbacks.

| Outer \ Inner | `if` | `switch` | `try` | `catch` | `orelse` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **`if` branch** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **`switch` prong** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **`catch` fallback** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **`orelse` fallback** | ✓ | ✓ | ✓ | ✓ | ✓ |
| **`try` operand** | ✗ | ✗ | ✗ | ✗ | ✗ |

**Note**: Recursive nesting is achieved by having each construct call back into `emitAssignmentWithLifting` for its result-yielding paths. This ensures that even deeply nested constructs are correctly flattened into C statement blocks.

## 5. Current Implementation Limitations

### 5.1 Assignments to Non-Identifiers
Lifting is currently only triggered for assignments where the left-hand side is a simple identifier (e.g., `x = try foo();`). Assignments to struct members or array elements (e.g., `s.x = try foo();`) do not trigger lifting and will result in invalid C code containing error comments.

### 5.2 Control Flow Conditions and Iterables
Expressions used as conditions for `if` or `while`, or as iterables for `for`, do not support lifting.
- **Unsupported**: `while (try foo()) { ... }`
- **Unsupported**: `for (try getList()) |item| { ... }`

### 5.3 Fixed: Omission of `orelse`
The `orelse` expression is now fully integrated into the unified assignment logic and is correctly supported as the final value of a block in `emitBlockWithAssignment`.

## 6. Technical Constraints

### 6.1 Stack Usage
Since lifting functions can call each other recursively (e.g., a `switch` containing an `if` containing a `block` containing a `switch`), deep nesting of control flow expressions can lead to significant C++ stack usage.
- **Constraint**: The parser implements a 255-level recursion limit, which indirectly protects the codegen phase.
- **Legacy Limit**: On Windows 9x, the stack is typically 1MB. Developers should avoid extremely deep expression nesting.

### 6.2 Memory Overhead
Lifting generates temporary variables and scoped blocks, which increases the size of the generated C code and the number of local variables the C89 compiler must track.
- **Impact**: Heavy use of lifting can increase the memory pressure on the host C compiler (e.g., MSVC 6.0).

## 7. Conclusion

The current lifting strategy provides a pragmatic way to support Zig's expression-oriented control flow in a C89 environment. While there are inconsistencies in recursive nesting and assignment targets, most common patterns are supported. Future improvements should focus on unifying the recursive calls across all lifting functions and extending support to non-identifier assignment targets.
