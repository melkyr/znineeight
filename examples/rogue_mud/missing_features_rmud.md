# Missing Features and Quirks - Rogue MUD Stress Test

During the implementation of the `rogue_mud` example as a stress test for `zig0` Milestone 11, several compiler limitations and quirks were identified.

## C89 Compliance and Milestone 11 Fixes (NEW)

The following issues were resolved during the final verification of the `rogue_mud` example:

### 1. Void-Returning `try`/`catch` (FIXED)
Previously, `try` or `catch` expressions returning `void` were skipped by the `ControlFlowLifter`. This caused critical side effects (like dungeon carving) to be omitted from the generated C code, leading to the "Error: no dungeons" issue.
**Status**: ✅ FIXED in `zig0`. The lifter now always processes these nodes and uses a safe `0;` statement in C.

### 2. Union Definitions inside Structs (FIXED)
Previously, the compiler emitted union definitions separately from member declarations, triggering "declaration does not declare anything" warnings in strict C89.
**Status**: ✅ FIXED in `zig0`. Combined definitions/declarations are now used.

### 3. RNG Robustness
Added checks to `Random_range` to prevent division-by-zero (Floating Point Exceptions) during dungeon generation when `max < min`.

---

## 1. Lifetime Violation on Slice Returns
Returning a slice derived from a many-item pointer stored in a struct field (e.g., `self.ptr[0..self.len]`) is incorrectly flagged as a lifetime violation: "Returning pointer to local variable creates dangling pointer".

### Working Workaround
Using an out-parameter to "return" the slice bypasses the analyzer and produces valid C code.
```zig
pub fn toSlice(self: *List, out: *[]u8) void {
    if (out != null) {
        out.* = self.ptr[0..self.len];
    }
}
```

## 2. Naming Conflicts: Modules vs Variables
The bootstrap compiler fails if a module (file) name is identical to a variable or type name.
### Workaround
Rename either the file or the internal symbol (e.g., use `_t` suffix).

## 3. No Struct Methods
Z98 does not support declaring functions inside a struct. Use prefixed standalone functions.

## 4. Unresolved Call Warnings
The compiler issues "Unresolved call" warnings in complex cross-module scenarios.
**Note**: The "no dungeons" issue previously associated with this was actually the `void try` lifter bug (see above).

## 5. Pointer Captures in If/While
Payload captures in `if` and `while` statements do not yet support pointers (e.g., `if (opt) |*p|`).

## 6. Optional Unwrap Syntax
The `opt.?` syntax can sometimes trigger syntax errors. Use explicit `if (opt) |val|` instead.

## 7. Explicit Integer Casting
Z98 requires explicit `@intCast` for almost all integer conversions, including literals.

## 8. Modulo Operator quirk
The modulo operator `%` on large integers can cause issues; cast to `u32` first.

## 9. Naked Tag Comparisons in Binary Operations
Using naked tags in binary ops (e.g., `tile == .Wall`) may trigger compiler aborts. Use `switch` instead.

## 10. Recursive Type Dependencies in C Headers
Can trigger "field has incomplete type" in C. Use pointers or optional pointers to break the dependency.

## 11. Aggregate Initialization Quirks
Anonymous aggregate initialization (`.{ .x = 0 }`) can fail in nested structures.

## 12. Type Mismatches with Literals
Literal `0` is often treated as `i32` and won't coerce to `u8` automatically in initializers.

## 13. C89 Compliance Report Findings (Pedantic)
- **Tagged Union Initializers**: The compiler uses designated initializers (`.tag = ...`) in expression contexts, which is a C99 feature. For strict C89, these are non-compliant, but local variables use a safe decomposition strategy.
- **Long Long**: Usage of `long long` for 64-bit support is a common extension accepted by the project.
