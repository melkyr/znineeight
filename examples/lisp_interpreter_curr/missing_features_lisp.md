# Missing Features and Findings - Lisp Interpreter

This document records the issues, bugs, and limitations discovered while attempting to compile and run the Advanced Z98 Lisp interpreter.

## 1. Summary of Results
- **Advanced Interpreter (`examples/lisp_interpreter_adv`)**: Compiles but **FAILS** at runtime due to a code generation bug in `union(enum)` initializers with anonymous structs.
- **Current/Downgraded Interpreter (`examples/lisp_interpreter_curr`)**: **SUCCESS** after moving anonymous structs to named structs.

## 2. Identified Compiler Bugs

### Issue: Failed initialization of `union(enum)` with anonymous struct payloads
**Problem**: When a `union(enum)` variant is defined using an anonymous struct, the compiler fails to generate the initialization code for that variant when using the `.{ .Variant = .{ ... } }` syntax.

**Failing Code (`value.zig` in `adv` version)**:
```zig
pub const Value = union(enum) {
    Cons: struct { car: *Value, cdr: *Value },
    // ...
};

v.* = Value{ .Cons = .{ .car = car, .cdr = cdr } };
```

**Generated C Code (Incorrect)**:
```c
{
    struct zS_5ed3ca_Value* init_lval_tmp = &(*v);
    // MISSING: tag and data initialization
}
```

**Workaround (Applied in `curr` version)**:
Define a named struct for the payload and use it in the union definition.

```zig
pub const ConsData = struct { car: *Value, cdr: *Value };
pub const Value = union(enum) {
    Cons: ConsData,
    // ...
};

v.* = Value{ .Cons = ConsData{ .car = car, .cdr = cdr } };
```

**Generated C Code (Correct)**:
```c
{
    struct zS_5ed3ca_Value* init_lval_tmp = &(*v);
    (*init_lval_tmp).tag = zE_1a36c1_Value_Tag_Cons;
    (*init_lval_tmp).data.Cons.car = car;
    (*init_lval_tmp).data.Cons.cdr = cdr;
}
```

## 3. Syntax & Parser Observations
- **`switch` captures**: Working correctly for both simple types and named struct payloads.
- **`union(enum)`**: Working correctly as long as payloads are named types.
- **`try` / `catch`**: Working correctly across modules.
- **Arena allocation**: Pervasive use in the interpreter is stable.

## 4. Environment Notes
- **Target**: 32-bit (`-m32`) on Linux requires `gcc-multilib`.
- **Compiler**: `zig0` (bootstrap compiler) is the primary tool.
