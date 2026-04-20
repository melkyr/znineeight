# Missing Features and Quirks - Rogue MUD Stress Test

During the implementation of the `rogue_mud` example as a stress test for `zig0` Milestone 11, several compiler limitations and quirks were identified.

## 1. Lifetime Violation on Slice Returns
Returning a slice derived from a many-item pointer stored in a struct field (e.g., `self.ptr[0..self.len]`) is incorrectly flagged as a lifetime violation: "Returning pointer to local variable creates dangling pointer".

### Status of Reproduction
The following pattern consistently triggers the `ERR_LIFETIME_VIOLATION` in `zig0`.

```zig
// ❌ FAILS: Triggers Lifetime Violation
// Found in ArrayListRoom_toSlice (src/dungeon/room.zig)
// and ArrayListBspNodePtr_toSlice (src/dungeon/bsp.zig)
pub fn toSlice(self: *List) []u8 {
    return self.ptr[0..self.len];
}
```

### Working Workaround
Using an out-parameter to "return" the slice bypasses the analyzer and produces valid C code.

```zig
// ✅ WORKS: Verified in examples/rogue_mud/test/lifetime_repro.zig
pub fn toSlice(self: *List, out: *[]u8) void {
    if (out != null) {
        out.* = self.ptr[0..self.len];
    }
}
```

## 2. Naming Conflicts: Modules vs Variables
The bootstrap compiler fails if a module (file) name is identical to a variable or type name used in the code.
For example, a file named `dungeon.zig` containing a `const Dungeon = struct { ... }` will cause redefinition or unresolved identifier errors.

### Workaround
Rename either the file or the internal symbol. In this project, `dungeon.zig` was renamed to `scenario.zig` and types often use a `_t` suffix (e.g., `Dungeon_t`, `Room_t`).

## 3. No Struct Methods
Z98 does not support declaring functions inside a struct (method syntax).
```zig
// ❌ Fails
const S = struct {
    pub fn init() S { ... }
};

// ✅ Works
const S = struct { ... };
pub fn S_init() S { ... }
```

## 4. Unresolved Call Warnings and Aborts
The compiler frequently issues "Unresolved call at ... in context ..." warnings. These seem to occur when the `TypeChecker` has not fully resolved all nodes during its traversal, especially with multi-level cross-module dependencies.

In the Rogue MUD project, the main `dungeon_test.zig` currently triggers a compiler `Aborted` state during the codegen phase. This indicates that the project complexity (BSP tree logic + multiple custom ArrayLists + cross-module imports) has exceeded the current stability limits of the `zig0` bootstrap compiler for Milestone 11.

While smaller examples like `lifetime_repro.zig` (which tested the out-parameter workaround) produce valid C code that compiles with `gcc -m32`, the full `dungeon_test.zig` cannot yet be successfully lowered to C89.

## 5. Pointer Captures in If/While
Payload captures in `if` and `while` statements do not yet support pointers (e.g., `if (opt) |*p|`).
Only value captures are supported.

## 6. Optional Unwrap Syntax
The `opt.?` syntax can sometimes trigger "Expected ';' after variable declaration" if used in certain expression contexts.

### Workaround
Use explicit `if (opt) |val|` or `if (opt != null) { const val = opt.?; }`.

## 7. Explicit Integer Casting
Z98 requires explicit `@intCast` for almost all integer conversions, including literals to `usize` or `u8`.
```zig
const x: usize = @intCast(usize, 10); // Required
```

## 8. Modulo Operator quirk
The modulo operator `%` on large integers can sometimes cause issues. It is recommended to cast to `u32` before performing modulo operations if possible.
