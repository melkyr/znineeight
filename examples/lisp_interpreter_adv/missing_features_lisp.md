# Z98 Lisp Interpreter Compilation Findings

This document tracks the features and issues discovered during the "Baptism of Water" with the Lisp interpreter.

## 1. Summary of Results
- **Downgraded Interpreter (`examples/lisp_interpreter`)**: SUCCESS after minor syntax fixes.
- **Advanced Interpreter (`examples/lisp_interpreter_adv`)**: FAILED due to compiler bugs in `union(enum)` and `switch` captures.
- **Intermediate Interpreter (`examples/lisp_interpreter_curr`)**: SUCCESS. This version uses manual `struct` + `union` for stability.

## 2. Verified Compiler Bugs & Code Generation

### Issue 1: `switch` Payload Captures (C89 Incompatibility)
**Problem**: The compiler generates anonymous struct initializers from non-constant expressions, which C89 rejects.

**Z98 Source (`repro_struct_init.zig`)**:
```zig
switch (v.*) {
    .Int => |val| return val,
    .Cons => |data| return test_switch_capture(data.car),
    else => unreachable,
}
```

**Generated C Code**:
```c
/* DEBUG: capture val */
i64 val;
val = switch_tmp.data.Int;
{
    return val;
}
/* ... */
/* DEBUG: capture data */
struct zS_0cb520_anon_1 data;
memcpy(&data, &switch_tmp.data.Cons, sizeof(struct zS_0cb520_anon_1));
{
    return zF_d3381c_test_switch_capture(data.car);
}
```
**Verification**: Instrumentation confirmed `[emitSwitch]` is hit. The current version of the compiler successfully uses `memcpy` for aggregate captures, which should be C89 compliant. However, the Lisp interpreter's failure suggests complex nested cases might still trigger issues.

---

### Issue 2: `union(enum)` Tag Assignment (Precedence Bug)
**Problem**: Assigning a tag literal to a dereferenced union pointer (e.g., `t.* = .Eof`) generates invalid C precedence.

**Z98 Source (`repro_union_void_payload.zig`)**:
```zig
t.* = .Eof;
```

**Generated C Code**:
```c
void zF_a80093_st_union_void_payload(struct zS_a80093_Token* t) {
    *t.tag = zE_06bb27_Token_Tag_Eof;
}
```
**Verification**:
- Instrumentation confirmed `[emitAssignmentWithLifting] Handling tag literal assignment` is hit.
- **Bypass**: This code path in `emitAssignmentWithLifting` manually appends `.tag` to the emitted l-value expression.
- **Bug**: Because it bypasses the `emitAccess` logic, it fails to wrap the dereference `*t` in parentheses, resulting in `*t.tag` (which C parses as `*(t.tag)`). This causes a C compiler error because `t` is a pointer.

---

### Issue 3: Pointer Dereference Precedence
**Problem**: Dereferenced pointer member access generates invalid C syntax like `*ptr.field`.

**Z98 Source (`repro_ptr_precedence.zig`)**:
```zig
v.*.tag = 42;
```

**Generated C Code**:
```c
void zF_7aff43_test_ptr_precedence(struct zS_7aff43_Value* v) {
    (*v).tag = 42;
}
```
**Verification**:
- Instrumentation confirmed `[emitAccess] Wrapping dereference base` is hit.
- The compiler correctly produces `(*v).tag`, which is valid C89. This confirms the fix in `emitAccess` is active and working for standard member access.

## 3. Syntax & Parser Limitations
- **`anyerror`**: Explicitly rejected by the compiler.
- **`pub const` Aliasing**: Cannot use `pub const name = function_name;` as it emits a variable assignment in C instead of a function alias.

## Conclusion
The compiler has existing logic to handle these issues, but specific patterns (likely involving pointers to unions or nested structures) are still bypassing the fixes or generating incorrect precedence for pointer operators.
