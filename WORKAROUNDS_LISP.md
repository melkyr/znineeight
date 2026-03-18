# Findings and Workarounds for Lisp Interpreter (Baptism of Water)

This document summarizes the compiler bugs identified and the attempted workarounds during the implementation of the Lisp interpreter in Z98.

## 1. Cross-Module Recursive Type Resolution
**Status**: CRITICAL BLOCKER.
**Bug**: Importing a module with recursive structs (e.g., `Value` -> `ConsData` -> `Value`) triggers a `DynamicArray` assertion failure in the `TypeChecker`.
**Reproduction**: `examples/lisp_interpreter/repro_bug.zig`
**Example**:
```zig
// value.zig
pub const Value = struct {
    tag: i32,
    data: union {
        Cons: struct { car: *Value, cdr: *Value },
    },
};

// main.zig
const val = @import("value.zig");
pub fn main() void {
    var v: val.Value = undefined;
}
```

## 2. Missing `@intToPtr` Builtin
**Status**: BUG.
**Error**: `repro_inttoptr.zig:2:24: error: syntax error ... hint: Expected a primary expression`
**Bug**: The builtin `@intToPtr` is not implemented in the bootstrap compiler, preventing the conversion of `usize` or `u32` back to pointers.
**Reproduction**: `repro_inttoptr.zig`

## 3. Optional Pointer (`?*T`) Comparison with `null`
**Status**: BUG.
**Error**: `repro_optional_null.zig:3:13: error: type mismatch ... hint: invalid operands for comparison operator '!=': '?*i32' and 'null'`
**Bug**: Comparison of optional pointers with `null` using `==` or `!=` is not supported.
**Reproduction**: `repro_optional_null.zig`

## 4. `while` Payload Capture Failure
**Status**: BUG.
**Error**: `repro_while_capture.zig:3:17: error: syntax error ... hint: Expected a primary expression`
**Bug**: The `while (optional) |capture|` syntax is not correctly parsed/handled.
**Reproduction**: `repro_while_capture.zig`

## 5. Cross-Module Symbol Visibility
**Status**: BUG.
**Error**: `module 'X' has no member named 'Y'`
**Symptoms**: Functions marked `pub` in imported modules are intermittently reported as missing when accessed from other modules, especially when those modules involve complex or recursive types.
**Reproduction**: `examples/lisp_interpreter/vis_main.zig` (if it triggers the bug in a specific environment).
**Example**:
```zig
// mod_a.zig
pub fn foo() void {}

// main.zig
const a = @import("mod_a.zig");
pub fn main() void {
    a.foo(); // Sometimes errors: module 'mod_a' has no member named 'foo'
}
```

## 6. Strict Type Checking and `@ptrCast`
**Status**: LIMITATION / BUG.
**Symptoms**: The compiler is extremely strict about pointer types. It correctly allows `*T` -> `?*T` (implicit wrapping), but fails on many other valid Zig/Z98 patterns.
**Reproduction**: `examples/lisp_interpreter/repro_strict_assignment.zig`, `examples/lisp_interpreter/repro_ptrcast_optional.zig`

### Case A: `?*T` to `*T` requires explicit unwrap or cast
Direct assignment fails as expected in Zig, but since `@ptrCast` is also limited, there's no easy way to "force" it.
```zig
var opt: ?*i32 = null;
var raw: *i32 = opt; // Error: type mismatch
```

### Case B: `@ptrCast` rejects optional pointers
`@ptrCast` requires the source to be a strict pointer, but `?*T` (Optional Pointer) is implemented as a struct in the backend, and the TypeChecker refuses to treat it as a source for `@ptrCast`.
```zig
var opt: ?*i32 = null;
var raw: *i32 = @ptrCast(*i32, opt);
// Error: source of @ptrCast must be a pointer (opt is technically an Optional struct)
```

## Conclusion: Pausing Implementation
The "Baptism of Water" (Lisp Interpreter) implementation was paused as the number of required workarounds grew to a point that threatened the readability and stability of the interpreter. The focus has shifted to documenting these bugs to enable future compiler improvements.
