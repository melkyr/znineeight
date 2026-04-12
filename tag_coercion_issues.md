# Tagged Union Coercion Investigation Report

This report documents the current issues and failure modes identified during the investigation of tagged union coercion (naked and qualified tags) in the Z98 bootstrap compiler.

## Summary of Findings

The current partial implementation of Phase B (Tagged Union Coercion) works for simple, direct contexts such as assignments and function arguments but fails significantly in complex expression contexts, particularly `if` and `switch` expressions. The failures range from compiler segmentation faults to the generation of invalid C code.

---

## 1. Segmentation Fault in `if` and `switch` Expressions

### Zig Source
```zig
const Cell = union(enum) { Alive: void, Dead: void };
pub fn main() void {
    var c: Cell = if (true) .Alive else .Dead;
}
```

### Observed Behaviour
The compiler crashes with a **Segmentation Fault** during the code generation phase.

### Debug Trace Analysis
1.  **Type Checking**: `visitVarDecl` correctly identifies the target type as `Cell`. It calls `coerceNode` on the `if` expression.
2.  **Coercion**: `coerceNode` distributes itself to the branches. It transforms `.Alive` and `.Dead` (naked tags) into `NODE_STRUCT_INITIALIZER` nodes with the resolved type `Cell`.
3.  **Lifting**: The `ControlFlowLifter` transforms the `if` expression into a statement block.
4.  **Emission**: During emission of the lifted `if` statement, the `C89Emitter` encounters a node that it expects to be a valid expression.
5.  **Root Cause**: In `C89Emitter::emitAccess`, the compiler attempts to process a `NODE_MEMBER_ACCESS` where the `base` is `NULL` (a naked tag that was NOT correctly transformed or was cloned back to its original state during lifting). The trace shows:
    `[EMITTER] emitAccess NODE_MEMBER_ACCESS field='Alive' base=(nil)`
    This leads to a null pointer dereference when accessing `member->base->resolved_type`.

### Impact
Affects all control-flow expressions used as initializers or in other contexts where lifting is required.

---

## 2. Invalid C Code for Arrays of Tagged Unions

### Zig Source
```zig
const Cell = union(enum) { Alive: void, Dead: void };
pub fn main() void {
    var arr: [2]Cell = .{ .Alive, .Dead };
}
```

### Observed Behaviour
The compiler generates **Invalid C Code**:
```c
struct zS_284d57_Cell arr[2] = {, };
```

### Root Cause
1.  **Decomposition Failure**: `C89Emitter::emitInitializerAssignments` is responsible for decomposing aggregate initializers into C89-compatible field assignments.
2.  **Missing Type Support**: The implementation currently handles `TYPE_STRUCT`, `TYPE_UNION`, `TYPE_TAGGED_UNION`, and `TYPE_TUPLE`, but it **completely lacks handling for `TYPE_ARRAY`**.
3.  **Garbage Access**: When it encounters `TYPE_ARRAY`, it falls through to logic that assumes a struct/union and attempts to access `type->as.struct_details.fields`, which contains garbage for an array type.
4.  **Local Array Limitation**: In C89, local arrays cannot be initialized with non-constant aggregates. The emitter must decompose these into individual element assignments, but for `TYPE_ARRAY`, it fails to do so.

---

## 3. Type Inference Failure for `var` (Missing Error)

### Zig Source
```zig
var c2 = if (true) .Alive else .Dead;
```

### Observed Behaviour
Instead of reporting a "type mismatch" or "ambiguous coercion" error, the compiler crashes.

### Expected Behaviour
The compiler should report a compile-time error because naked tags (`.Alive`) require a target type for coercion. Since `c2` has no explicit type and both branches are ambiguous naked tags, the type cannot be inferred.

---

## 4. Loop State and Capture Sensitivity

### Zig Source
```zig
var v: Cell = .Alive;
while (true) {
    switch (v) {
        .Alive => { v = .Dead; continue; },
        .Dead => break,
    }
}
```

### Observed Behaviour
Segmentation fault during `emitSwitch`.

### Analysis
The `switch` on a tagged union variable `v` in a loop triggers the emission of a `switch_tmp` variable. The interaction between loop control flow (`continue`, `break`), `defer` blocks, and the temporary variables generated for tagged union switching appears to be unstable, leading to invalid AST states during emission.

---

## 5. Qualified Tags (`Cell.Alive`)

### Status
Qualified tags seem more stable than naked tags because they are folded into `NODE_INTEGER_LITERAL` with an `original_name` during the initial visit. This allows the emitter to handle them as simple integers in some cases, although they still fail when they need to be wrapped into a union struct within a complex expression.

---

## Actionable Fix Plan

Based on the investigation, the following steps are required to fix tagged union coercion:

### Phase 1: TypeChecker Robustness
1.  **If-Expression Coercion Integration**: Update `TypeChecker::visitIfExpr` to follow the pattern used in `validateSwitch`. It should explicitly call `coerceNode` on `then_expr` and `else_expr` if an `expected_type` is available, especially when the branches are ambiguous naked tags or anonymous literals.
2.  **VarDecl Fallback**: Modify `TypeChecker::visitVarDecl` to allow `NODE_IF_EXPR` and `NODE_SWITCH_EXPR` initializers to proceed to the coercion phase even if they return `TYPE_UNDEFINED` (as long as a `declared_type` is present to guide them).
3.  **Ambiguity Guard**: Implement a strict check in `coerceNode`. If a naked tag (`NODE_MEMBER_ACCESS` with `base == NULL`) or anonymous literal reaches a point where `target_type` is `anytype`, `NULL`, or otherwise non-structural, report a clear `ERR_TYPE_MISMATCH` instead of allowing it to proceed.
4.  **Local Inference Block**: Specifically in `visitVarDecl`, if the declared type is missing and the initializer is an ambiguous `if`/`switch` expression, return an error early.

### Phase 2: ControlFlowLifter Integrity
1.  **Type Preservation**: Ensure `ControlFlowLifter::lowerIfExpr` and `lowerSwitchExpr` copy the `resolved_type` from the original expression node to the generated temporary variable and the final identifier node.
2.  **Clone Audit**: Verify that `cloneASTNode` correctly preserves all semantic metadata, including `resolved_type` and any synthetic nodes injected during coercion.

### Phase 3: C89Emitter Enhancements
1.  **Array Decomposition**: Update `C89Emitter::emitInitializerAssignments` to handle `TYPE_ARRAY`. It should loop through the elements of the `NODE_TUPLE_LITERAL` or `NODE_STRUCT_INITIALIZER` and emit assignments to `base_name[i]`.
2.  **Safety Assertions**: Add internal assertions in `C89Emitter::emitAccess` and `emitExpression` to catch naked tags (`base == NULL`) and report them as internal compiler errors with file/line information, preventing silent segfaults.

### Phase 4: Validation
1.  **Test Suite Expansion**: Incorporate the reproduction cases from this investigation into the permanent test suite (`tests/integration/union_tests.cpp`).
2.  **32-bit/m32 Verification**: All generated code must be verified with `gcc -m32 -std=c89` to ensure standard compliance on the target architecture.

---
*Report generated by Z98 Investigation Agent*
