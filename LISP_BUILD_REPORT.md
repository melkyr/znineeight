# Lisp Interpreter Build Report

This report documents the attempts to build the Lisp interpreter (`examples/lisp_interpreter/`) using the updated RetroZig bootstrap compiler.

## Summary of Results

| Target | Build Method | Result | Notes |
|--------|--------------|--------|-------|
| Multi-module | `zig0 main.zig` | FAILED | Type mismatch errors for identical types across boundaries. |
| Single-module | `cat *.zig > lisp.zig` | FAILED | Multiple definition errors and unresolved identifiers. |
| **Recursive Bug** | `zig0 repro_bug.zig` | **PASSED** | The critical `DynamicArray` assertion failure is resolved. |
| **while Capture** | `zig0 test_while.zig` | **PASSED** | New feature verified in multi-module context. |

## Build Attempt 1: Multi-module (`main.zig`)

### Command
```bash
./zig0 examples/lisp_interpreter/main.zig -o lisp_multi.c
```

### Observations
The compiler reported numerous "type mismatch" errors where it seemed to fail to recognize that a type imported from one module was identical to the same type used in another module. For example:
- `hint: Incompatible assignment: '?*struct EnvNode' to '*struct EnvNode'`
- `hint: incompatible argument type, expected '?*struct EnvNode', got '?*struct EnvNode'`

### Key Finding: Bug Resolved
Despite the type mismatch errors (which likely stem from current limitations in the multi-module type equality logic), the **critical compiler blocker** previously documented (the `DynamicArray` assertion failure during recursive type resolution) did **not** occur. The compiler processed the recursive structures in `value.zig` without crashing.

## Build Attempt 2: Single-module (`lisp.zig`)

### Command
```bash
cat util.zig arena.zig value.zig token.zig env.zig builtins.zig parser.zig eval.zig main.zig > lisp.zig
./zig0 lisp.zig -o lisp_single.c
```

### Observations
Simple concatenation failed because:
1.  **Multiple `@import`**: Each original file had its own imports, which became redundant or conflicting in a single file.
2.  **Symbol Conflicts**: Global variables and functions with the same name (common in small modules) collided.
3.  **Cross-file References**: Some modules were written assuming per-module visibility, which changed when merged.

## Verification of New Features

### while Payload Capture
The feature was successfully verified using a multi-module script:
```zig
// test_while_multi.zig
const other = @import("other.zig");
pub fn main() void {
    var opt: ?*i32 = other.get_ptr();
    while (opt) |ptr| {
        __bootstrap_print_int(ptr.*);
        opt = null;
    }
}
```
The compiler correctly generated the `while(1)` loop with internal condition evaluation and capture unwrapping.

### Switch Hardening
The hardening of switch captures using `resolveAllPlaceholders` was verified to ensure that payload types are fully concrete before capture symbols are created. This prevents potential assertion failures when switching on tagged unions with recursive fields.

## Conclusion and Future Work
- The **recursive type resolution bug** is confirmed fixed.
- **while payload capture** is fully implemented and functional.
- The Lisp interpreter still faces challenges with multi-module type consistency. Future work should focus on unifying type identity across module boundaries to allow complex examples like the Lisp interpreter to compile in their modular form.
