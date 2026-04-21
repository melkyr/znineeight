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

## 9. Naked Tag Comparisons in Binary Operations
Currently, `zig0` may abort or fail to resolve types when a naked tag (e.g., `.Wall`) is used in a binary operation (e.g., `tile == .Wall`).

### Workaround
Use an idiomatic `switch` statement instead of binary equality for tagged unions.

```zig
// ❌ May trigger compiler abort
if (tile == .Wall) { ... }

// ✅ Works correctly
switch (tile) {
    .Wall => { ... },
    else => {},
}
```

## 10. Recursive Type Dependencies in C Headers
The `CBackend` may sometimes generate C headers where a struct field uses a type that is not yet fully defined (e.g., circular dependencies between modules or nested optionals/error unions).

### Workaround
If a struct field triggers "field has incomplete type" in C, try changing the field to a pointer (`*T`) or an optional pointer (`?*T`). Pointers do not require the full type definition at the point of declaration in C.

Example from `bsp.zig`:
```zig
pub const BspNode = struct {
    // ...
    room: ?*room_mod.Room_t, // Changed from ?room_mod.Room_t to avoid incomplete type error
};
```

### Reproduction
A minimal reproduction of this issue can be found in `examples/rogue_mud/test/header_repro.zig`.
## 11. Aggregate Initialization Quirks
Anonymous aggregate initialization (e.g., `.{ .x = 0 }`) sometimes fails to coerce correctly when used in nested structures or if types are imported from other modules.

### Workaround
Initialize fields individually after declaration if possible, or use explicit intermediate variables for sub-structures.

## 12. Type Mismatches with Literals
Z98 is very strict about types in assignments. A literal `0` is often treated as `i32` and will not implicitly coerce to `u8` or `usize` in a struct initializer.

### Workaround
Always use `@intCast` even for constants in initializers: `.field = @intCast(u8, 0)`.

## 13. Unresolved Calls in cross-module code
Function calls across modules can sometimes result in "Unresolved call" warnings if the `TypeChecker` hasn't reached the target function's definition yet. This is especially prevalent in larger projects. It doesn't always prevent compilation but can lead to incorrect code generation or compiler aborts in complex scenarios.

### Example
```zig
// lib/a.zig
const b = @import("b.zig");
pub fn callB() void {
    b.doSomething(); // ⚠️ Warning: Unresolved call at ... in context 'doSomething'
}

// lib/b.zig
pub fn doSomething() void { ... }
```

### What is happening?
The `zig0` `TypeChecker` operates in passes. In complex cross-module scenarios, it might attempt to validate a function call before the target function's signature has been fully catalogued in the symbol table's cross-module cache. This is often triggered by deep import chains or circular dependencies.

### Workarounds
1. **Signature Simplification**: Reduce the complexity of the function arguments (e.g., use pointers instead of passing large structs by value).
2. **Module Reorganization**: Move the frequently called utility functions into a "leaf" module that doesn't import other project modules.
3. **Explicit Typing**: Ensure all variables involved in the call have explicit types to help the `TypeChecker` infer the call signature even if the target is not yet fully "resolved".
4. **Ignore if compiles**: If the compiler produces a warning but still generates a valid `.c` file that compiles with `gcc`, the warning can often be ignored as the `CBackend` might still find the symbol during the final emission phase.

## 14. Phase 2: Milestone 11 Stress Test Findings (Week 4)

During the completion of Week 4 (Polish & UI), more severe compiler stability issues were identified that prevent linking of the generated C89 code.

### A. Cross-module Symbol Hash Inconsistency
The compiler uses hashes in mangled names (e.g., `zV_1c8b95_ANSI_GREEN`). In the Milestone 11 stress test, different modules are assigned different hashes for the same imported symbols, leading to link-time "undefined reference" errors.

**Evidence:**
- `ui.h` declares: `extern unsigned char const (* zV_1c8b95_ANSI_GREEN)[5];`
- `ui.c` defines: `const unsigned char const (* zC_43327b_ANSI_GREEN)[5] = ...`
- `main.c` attempts to use `zC_43327b_ANSI_GREEN`.

The inconsistency between `1c8b95` and `43327b` causes the linker to fail. This appears to be triggered by deep or complex import chains.

### B. Missing Empty Tuple Definition in Importers
Functions like `std.debug.print` desugar to code using anonymous tuples. If no arguments are passed or if the lowering triggers an empty tuple, `zig0` desugars this to `struct Tuple_empty`.

**The Bug:**
The definition of `struct Tuple_empty` is emitted in the module where the empty tuple is first encountered (e.g., `ui.c`), but other modules that use it (e.g., `main.c`) do not receive the definition, nor is it exported in the module's header. This leads to "storage size of ... isn't known" errors in C.

**Workaround:**
Avoid calling `std.debug.print` with patterns that trigger empty tuple desugaring, or ensure all files have a dummy tuple definition.

### C. Const vs Var Mangling Inconsistency
`pub const` symbols sometimes get mangled with `zC_` (Constant) in the definition file but `zV_` (Variable) in the header or importing files. This mismatch (`zC_` vs `zV_`) prevents linking.

**Workaround:**
Change `pub const` to `pub var` for global configuration or constant strings that need to be shared across modules.

### D. Path Length and Name warnings
The compiler emits warnings for non-8.3 filenames (e.g., `array_list.zig`). While just a warning, it indicates the compiler's strict focus on 1998-era compatibility.

### E. Failed Workaround: Getter Functions for Constants
To solve the symbol hash inconsistency (Issue A), an attempt was made to use "getter" functions (e.g., `pub fn getAnsiGreen() []const u8`).

**The Result:**
The inconsistency persisted. The getter function itself (`zF_43327b_getAnsiGreen`) was correctly resolved by the importer, but the underlying data it returned or referenced often triggered further mangling issues or "Unresolved call" warnings at the C level during linking because the internal state of the `TypeChecker` for that module remained inconsistent with the importer's view.

### F. Successful Workaround (C-level): Direct Runtime Calls
Bypassing the Zig `std.debug.print` (which uses anonymous tuples) in favor of direct `extern "c" fn __bootstrap_print(s: *const c_char) void` calls successfully resolved the "Missing Empty Tuple Definition" (Issue B). This confirms that the issue is specifically in the lowering of anonymous aggregate literals used in `anytype` parameters.

### G. Hard Blocker: Cross-module Project Scaling
Milestone 11's `zig0` compiler currently fails to scale to projects with more than ~5-7 interacting modules where symbols are shared across the module graph. The mangling hash becomes non-deterministic or context-dependent, making it impossible to link a large project into a single binary without manually editing the generated C headers.

**Recommendation for Self-Hosting (zig1):**
The symbol mangling and cross-module resolution logic in `zig1` MUST use a more deterministic approach (e.g., fully qualified names or a stable hash based purely on the canonical path) to avoid these "mangling drift" issues.
