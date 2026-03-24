# Lisp Interpreter Advanced Syntax Compilation Report

This document details the issues encountered while attempting to compile an advanced version of the Lisp interpreter using the RetroZig bootstrap compiler (`zig0`). The advanced version uses idiomatic Z98 features like `union(enum)` with payload captures, `try`, and `orelse`.

## Summary of Encountered Issues

| Category | Description | Impact |
| --- | --- | --- |
| **C89 Codegen** | **Invalid Initializer**: The compiler generates anonymous struct initializers in `switch` captures that C89 rejects. | **BLOCKER**: C compilation fails for all modules using `switch` captures. |
| **C89 Codegen** | **Pointer Precedence**: The compiler emits `*ptr.tag = ...` instead of `(*ptr).tag` or `ptr->tag` in struct/union pointers. | **BLOCKER**: C compilation fails for pointer-based assignments. |
| **C89 Codegen** | **Tag/Payload Mismatch**: Attempting to assign a tag value directly to a union's `payload` field when the variant has no payload. | **BLOCKER**: C compilation fails for `void` payload variants. |

---

## 1. Issue: Invalid Initializer in `switch` Captures

### Z98 Source Example
```zig
switch (v.*) {
    .Cons => |data| return data.car,
}
```

### Generated C Code
```c
{
    /* DEBUG: capture data */
    struct {
        struct z_value_Value* car;
        struct z_value_Value* cdr;
    } data = switch_tmp.data.Cons;
    return data.car;
}
```

### C Compiler Error (`gcc -m32`)
```text
examples/lisp_interpreter_adv/builtins.c:75:26: error: invalid initializer
   75 |                 } data = switch_tmp.data.Cons;
      |                          ^~~~~~~~~~
```
**Insight**: Instrumentation in `src/bootstrap/codegen.cpp:emitSwitch` shows that the compiler emits a local `struct` definition and attempts to initialize it using a single assignment. C89 does not support this "struct copy" initialization for anonymous structures in this context.

**Root Cause Location**: `C89Emitter::emitSwitch` in `src/bootstrap/codegen.cpp`.
**Potential Fix**: Use a named typedef for the capture or emit field-by-field assignments.

---

## 2. Issue: Pointer Dereference Precedence

### Z98 Source Example
```zig
v.tag = .Int;
```
where `v` is a pointer `*Value`.

### Generated C Code
```c
*z_value_v.tag = z_value_Value_Tag_Int;
```

### C Compiler Error (`gcc -m32`)
```text
examples/lisp_interpreter_adv/value.c:84:15: error: ‘z_value_v’ is a pointer; did you mean to use ‘->’?
   84 |     *z_value_v.tag = z_value_Value_Tag_Int;
      |               ^
      |               ->
```
**Insight**: The `C89Emitter` seems to decompose pointer assignments by prepending `*` to the expression but fails to add parentheses. In C, `.` binds tighter than `*`, so `*v.tag` means `*(v.tag)`.

**Root Cause Location**: `C89Emitter::emitAssignmentWithLifting` or `emitExpression` for identifiers with pointer types.
**Potential Fix**: Always wrap dereferences in parentheses or use `->` for member access on pointers.

---

## 3. Issue: Tag/Payload Assignment Mismatch

### Z98 Source Example
```zig
return Token.Eof;
```
where `Eof` is a `void` payload variant in a tagged union.

### Generated C Code
```c
__return_val.data.payload = z_token_Token_Tag_Eof;
```

### C Compiler Error (`gcc -m32`)
```text
examples/lisp_interpreter_adv/token.c:66:41: error: incompatible types when assigning to type ‘struct z_token_Token’ from type ‘int’
```
**Insight**: For `void` payload variants, the compiler should only assign the `tag` field of the tagged union struct. Instead, it attempts to assign the tag value to a non-existent or incompatible `payload` member in the `data` union.

**Root Cause Location**: `C89Emitter::emitAssignmentWithLifting` (specifically `emitErrorUnionWrapping` or `emitOptionalWrapping` logic when applied to tagged unions).

---

## 4. Reproduction Cases

Reliable reproduction Zig files have been created in `examples/lisp_interpreter_adv/repros/`:
- `repro_struct_init.zig`
- `repro_ptr_precedence.zig`
- `repro_union_void_payload.zig`

To trigger these, run:
```bash
./zig0 examples/lisp_interpreter_adv/repros/<file>.zig -o test.c
gcc -m32 test.c src/runtime/zig_runtime.c -Isrc/runtime -o test
```

## Conclusion

The advanced Lisp interpreter has successfully served as a "baptism of water," identifying key deficiencies in the bootstrap compiler's C89 code generation. Fixing these will allow idiomatic Z98 code to compile and run correctly.
