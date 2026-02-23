# C89 Lifting Strategies: Technical Design

This document describes the "lifting" mechanism used by the RetroZig bootstrap compiler to translate Zig expressions with control flow into C89-compliant code.

## 1. Overview

In Zig, constructs like `if`, `switch`, `try`, `catch`, and `orelse` are expressions that yield values. However, C89 does not support control flow within expressions. To bridge this gap, the `C89Emitter` performs **lifting**: it transforms these expressions into one or more C statements (typically inside a scoped block) that assign the result to a temporary variable or a direct target.

## 2. Core Mechanism

### 2.1 The `target_var` Strategy
Lifting functions in `C89Emitter` (e.g., `emitTryExpr`, `emitIfExpr`) take a `const char* target_var` parameter.
- If `target_var` is **non-NULL**, the lifting logic generates an assignment to that variable (e.g., `target = result;`).
- If `target_var` is **NULL**, the expression is evaluated solely for its side effects (common in expression statements).

### 2.2 Scoped Blocks
Most lifted expressions are wrapped in a C block `{ ... }`. This allows the emitter to:
1. Declare temporary variables (like `__try_res`) that are local to the lifting operation.
2. Comply with C89's rule that all declarations must appear at the start of a block.

### 2.3 Temporary Result Variables
For complex contexts like `return try foo()`, the emitter generates a temporary result variable (e.g., `__return_val`) to hold the expression's value while other logic (like `defer` statements) is executed.

## 3. Detailed Construct Strategies

### 3.1 `if` Expressions
Lifted into a C `if-else` statement.
- **Assignment**: Each branch assigns its final expression to `target_var`.
- **Divergence**: If a branch ends in `return`, `break`, or `continue`, the assignment is skipped for that branch as the code path diverges.
- **Optional Capture**: If the condition is an optional type, a temporary `opt_tmp` is used to prevent double-evaluation of the condition.

### 3.2 `switch` Expressions
Lifted into a C `switch` statement.
- **Prongs**: Each case prong ends with an assignment to `target_var` followed by a `break;`.
- **Recursive Support**: `switch` prongs explicitly support nested `if` and `switch` expressions by calling their lifting functions recursively.

### 3.3 `try` Expressions
Lifted into an `if` check for the `is_error` flag.
- **Propagation**: If an error is detected, the emitter executes active `defer` statements and returns the error.
- **Success**: The payload is assigned to `target_var`.
- **Limitation**: The operand of `try` (the expression being tried) is currently emitted via `emitExpression`, which does NOT support nesting other lifted constructs.

### 3.4 `catch` and `orelse` Expressions
Lifted into an `if-else` check.
- **Success/Value**: The payload/value is assigned to `target_var`.
- **Fallback**: The `else` branch (fallback) supports recursive lifting of `if` and `switch`, but generally lacks support for nested `try`, `catch`, or `orelse`.

## 4. Nesting Support Matrix

The following table describes which constructs can be nested inside others *without* using a block `{ ... }`.

| Outer \ Inner | `if` | `switch` | `try` | `catch` | `orelse` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **`if` branch** | ✗ [1] | ✗ [1] | ✗ [1] | ✗ [1] | ✗ [1] |
| **`switch` prong** | ✓ | ✓ | ✗ | ✗ | ✗ |
| **`catch` fallback** | ✓ | ✓ | ✗ | ✗ | ✗ |
| **`orelse` fallback** | ✓ | ✓ | ✗ | ✗ | ✗ |
| **`try` operand** | ✗ | ✗ | ✗ | ✗ | ✗ |

**[1] Note**: While direct nesting is unsupported for `if` branches, wrapping the inner expression in a block (e.g., `if (a) { if (b) 1 else 2 } else 3`) IS supported via `emitBlockWithAssignment`.

## 5. Current Implementation Limitations

### 5.1 Assignments to Non-Identifiers
Lifting is currently only triggered for assignments where the left-hand side is a simple identifier (e.g., `x = try foo();`). Assignments to struct members or array elements (e.g., `s.x = try foo();`) do not trigger lifting and will result in invalid C code containing error comments.

### 5.2 Control Flow Conditions and Iterables
Expressions used as conditions for `if` or `while`, or as iterables for `for`, do not support lifting.
- **Unsupported**: `while (try foo()) { ... }`
- **Unsupported**: `for (try getList()) |item| { ... }`

### 5.3 Omission of `orelse`
In the current version of `emitBlockWithAssignment`, the `orelse` expression is missing from the list of constructs that can be lifted as the final value of a block.

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
