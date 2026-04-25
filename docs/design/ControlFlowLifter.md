# Control Flow Lifter

## Overview
The `ControlFlowLifter` is a mandatory pass in the Z98 compiler that transforms expression-form control flow (`if`, `switch`, `try`, `catch`, `orelse`) into statement-form equivalents. This simplifies the C89 backend by ensuring that the code generator never encounters nested control-flow expressions, which are not supported in standard C.

## Transformation Strategy
For each expression-form control flow node, the lifter:
1. Generates a unique temporary variable name (e.g., `__tmp_if_1_5`).
2. Inserts a declaration for this temporary variable in the current block.
3. Transforms the control flow node into its statement-form equivalent.
4. Updates each branch of the control flow to assign its result to the temporary variable.
5. Replaces the original expression node with an identifier referencing the temporary variable.

## Void Result Handling (Milestone 11 Fix)
A critical fix was implemented in Milestone 11 to handle `void`-returning control flow, specifically for `try`, `catch`, and `orelse` expressions that are used for their side effects rather than their values.

### The Problem
Previously, the lifter would skip nodes with a `void` resolved type. While this was safe for `if`/`switch` (which are already valid statements if they yield `void`), it was incorrect for `try`/`catch`/`orelse`. These expressions often encapsulate critical logic (like returning on error) that must be lowered to C even if they don't produce a value.

### The Solution
1. **Always Lift `try`/`catch`/`orelse`**: `needsLifting()` was updated to always return `true` for these node types, regardless of their result type.
2. **No Temporary for `void`**: In `liftNode()`, if the node yields `void`, the lifter proceeds with the transformation but skips the creation of a temporary variable and the assignment logic. Instead, it transforms the expression into a block of statements and replaces the original node with a dummy void identifier that is ignored by the emitter.

## Memory Management
The lifter relies heavily on the `ArenaAllocator`. Since it clones AST nodes and creates new statement nodes, it can be memory-intensive. The 16MB peak memory usage limit is strictly enforced, and the lifter is designed to be as efficient as possible by reusing nodes where safe.
