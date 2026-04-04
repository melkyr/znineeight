# Diagnostic Analysis: Tagged Union Initializer with Anonymous Struct Payload

This document records the analysis of a code generation bug in the Z98 bootstrap compiler (`zig0`).

## Problem Description

The compiler fails to generate C code for assignments to `union(enum)` variables when the initializer uses an anonymous struct for the payload.

**Example Code:**
```zig
const Value = union(enum) {
    Cons: struct { car: *Value, cdr: *Value },
    Nil: void,
};

pub fn main() void {
    var v: Value = undefined;
    v = Value{ .Cons = .{ .car = undefined, .cdr = undefined } };
}
```

**Symptom:** The assignment to `v` is completely missing from the generated `main` function in C.

## Deep Diagnostic Findings

### 0. Symbol and Module Resolution
Instrumentation of `SymbolTable` and `TypeRegistry` confirms that the tagged union `Value` and its associated tag enum `Value_Tag` are correctly resolved and mangled within the `test_anon_union` module. The issue is not related to module name resolution or symbol lookup, but rather to the type resolution state passed to the code generator.

### 1. Root Cause: `TYPE_UNDEFINED` Propagation
The core issue is that `TypeChecker::visitStructInitializer` returns `TYPE_UNDEFINED` for the outer tagged union initializer if ANY of its nested fields fail to resolve to a concrete type during the initial `visit()` pass.

For anonymous struct payloads (e.g., `.{ .car = car, ... }`), a context-free `visit()` **correctly** returns `TYPE_UNDEFINED` because the type cannot be known without the parent's context. However, `TypeChecker::checkStructInitializerFields` (which is called by the outer struct) incorrectly treats this `TYPE_UNDEFINED` as a fatal resolution failure and returns `false` to its caller, causing the outer struct to also be marked as `TYPE_UNDEFINED`.

### 2. Impact on Codegen
When the codegen (`C89Emitter`) encounters a `NODE_STRUCT_INITIALIZER` with `resolved_type->kind == TYPE_UNDEFINED` (value 17):

1.  **Assignments**: `emitInitializerAssignments` checks `type->kind`. Since `TYPE_UNDEFINED` is not an aggregate kind, it returns early. The entire assignment is silently omitted.
2.  **Declarations**: `emitExpression` falls back to a "positional" emission mode because it doesn't recognize the type. It emits raw values in braces, e.g., `{{1, 2}}`, which is incorrect for a tagged union (missing the tag and correct data union wrapping).

### 3. Detailed Trace (Reproduction: `test_anon_union.zig`)
1.  **Assignment `v = Value{ .Cons = .{ ... } }`**:
    - `visitAssignment` calls `visit(rvalue)`.
    - `visitStructInitializer(outer)` calls `checkStructInitializerFields(outer)`.
    - Field `.Cons` is processed. Its value is the inner anonymous struct.
    - `visit(inner)` returns `TYPE_UNDEFINED`.
    - `checkStructInitializerFields(outer)` sees `TYPE_UNDEFINED` and returns `false`.
    - `visitStructInitializer(outer)` returns `TYPE_UNDEFINED`.
    - `node->resolved_type` for the outer node is set to `TYPE_UNDEFINED`.
2.  **Codegen Phase**:
    - `emitAssignmentWithLifting` calls `emitInitializerAssignments("v", outer)`.
    - `emitInitializerAssignments` sees `type->kind == 17`.
    - **Logic skipped**. No C code emitted for the assignment.

### 4. Verification of `Nil` Tag Issue
In the Lisp interpreter's `Value` union, `Nil` is the first variant (index 0). Because the compiler fails to emit the tag assignment (and the payload assignments), the zeroed memory allocated by `sand_alloc` defaults to a tag of `0`, which the interpreter correctly (but unintentionally) interprets as `Nil`. This explains why `alloc_cons` "randomly" returns `Nil`.

### 5. Why Existing Tests Passed
Existing integration tests (e.g., Batch 57) for anonymous structs often used them in simple assignments or as part of larger struct initializers that didn't involve tagged unions in this specific nested way, or they were used in variable declarations where a different code path (that didn't return early as aggressively) was taken. The bug is most prominent when an anonymous literal is used to initialize a *variant* payload of a tagged union.

## Proposed Solution (Fix Strategy)

Modify `TypeChecker::checkStructInitializerFields` to allow `TYPE_UNDEFINED` results from `visit(field_value)` if the field value is a `NODE_STRUCT_INITIALIZER` (anonymous) or a `NODE_UNDEFINED_LITERAL`. Rely on the subsequent `coerceNode` call within the same loop to perform the actual resolution and type-checking once the target field type is known.

```cpp
// src/bootstrap/type_checker.cpp

bool TypeChecker::checkStructInitializerFields(...) {
    ...
    for (...) {
        Type* val_type = visit(init->value);
        if (val_type && is_type_undefined(val_type)) {
            // FIX: Allow anonymous structs and 'undefined' to proceed to coercion
            if (init->value->type != NODE_STRUCT_INITIALIZER &&
                init->value->type != NODE_UNDEFINED_LITERAL) {
                return false;
            }
        }
        ...
        coerceNode(&init->value, field_type); // This will resolve the type!
        ...
    }
}
```
