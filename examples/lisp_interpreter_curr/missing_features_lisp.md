# Detailed Findings from the Lisp Interpreter "Baptism of Water"

This document records the issues, bugs, and limitations discovered while attempting to compile and run the Z98 Lisp interpreter versions.

## 1. Summary of Results (Milestone 11)

| Version | Status | Notes |
|---------|--------|-------|
| Downgraded (`lisp_interpreter`) | **SUCCESS** | Baseline stable in 32-bit mode. |
| Current (`lisp_interpreter_curr`) | **SUCCESS** | Idiomatic Z98 features (unions, switches) work perfectly. |
| Advanced (`lisp_interpreter_adv`) | **SUCCESS** | Anonymous struct payloads in unions are now verified working. |

## 2. Resolved Issues & Milestone 11 Fixes

### C Code Bugs & Warnings

#### FIXED: String Literal Slice Mismatch
**Observation**: The compiler's implicit conversion of string literals to `[]const u8` triggered signedness warnings.
**Resolution**: `CBackend::generateSpecialTypesHeader` now specializes `__make_slice_u8` to accept `const char*` with an internal cast to `unsigned char*`.

#### FIXED: Anonymous Structs in `union(enum)` Initializers
**Observation**: Initializing a tagged union variant with an anonymous struct payload `.{ .Variant = .{ ... } }` failed to generate data member assignments.
**Resolution**: Milestone 11 introduced `TYPE_ANONYMOUS_INIT` and updated `coerceNode` to correctly resolve nested anonymous initializers. `C89Emitter` now correctly decomposes these into tag and field assignments.

#### FIXED: Local `const` Aggregate Declarations
**Observation**: Local variables declared as `const` with aggregate initializers were sometimes skipped or caused C compilation errors.
**Resolution**: `C89Emitter` now conditionally omits `const` in C for variables with runtime initializers, allowing them to be assigned correctly in C89 while maintaining Zig's immutability at the frontend.

### Z98 Syntax & Codegen Improvements

#### FIXED: Lisp Interpreter Recursion
**Observation**: Recursive Lisp functions originally failed to resolve due to environment capture timing.
**Resolution**: Implemented a "mutable slot" strategy in `eval.zig`. `define` now pre-binds a name to a `Nil` slot in the environment before evaluating the RHS. If the RHS is a lambda, the resulting closure captures the environment containing this stable slot. After evaluation, the slot is updated in-place with the actual closure/value. This allows circular references required for recursion.

#### FIXED: Direct Tagged Union Member Access
**Observation**: Static access to tagged union tags via aliases was problematic.
**Resolution**: `TypeChecker::visitMemberAccess` and `resolveTypeAlias` were updated to robustly follow alias chains and resolve static members (tags).

#### FIXED: Loop State & Capture Sensitivity
**Observation**: Switch captures inside loops could lead to state corruption.
**Resolution**: Improved `ControlFlowLifter` and `C89Emitter` to ensure temporary variables for captures are correctly scoped and initialized within loop bodies.

## 3. Portability & Compatibility Reports

### 32-bit Compatibility (`-m32`)
- **Status**: **SUCCESS**.
- **Observations**: Essential for the 1998 target. Both compiler and generated code are stable in 32-bit.

### Windows Compatibility (Mingw-w64 + Wine)
- **Status**: **SUCCESS**.
- **Observations**: Cross-compilation to 32-bit Windows works. Deep recursion requires increased stack size (`-Wl,--stack,16777216`).

### 64-bit Note
- **Warning**: The Lisp interpreter may segfault in 64-bit mode due to `@sizeOf(Value)` mismatches between `zig0` (which assumes 32-bit alignment) and 64-bit C compilers. **Always target 32-bit for the Lisp interpreter examples.**

## 4. Technical Achievements
- **Arena Alignment**: `sand_alloc` enforces 8-byte alignment via `@intCast(usize, 8)` to support `i64` and pointers on 32-bit systems.
- **Braceless Control Flow**: Full support for braceless `if`, `while`, `for`, and `defer`.
- **Switch Range Support**: Support for character and integer ranges (e.g., `'a'...'z'`) in switch prongs.

## 5. Workarounds & Syntax Quirks

### Manual Tail-Call Optimization (TCO)
**Workaround**: The `eval` function in `eval.zig` was manually refactored from a recursive tree-walker into a `while (true)` loop with explicit state management for tail positions (e.g., in `if` prongs and `lambda` calls).
**Rationale**: Even with Milestone 11 optimizations, deep recursion in a 32-bit environment with fixed arena sizes quickly exhausts the C stack or arena memory if every call is recursive. Manual TCO is necessary for robust Lisp execution.

### Pointer-Sign Mitigation
**Workaround**: In `main.zig`, strings are passed to `print_str` using slice literals or explicit `[*]u8` to `[]u8` conversions to satisfy the Z98/C89 strict typing rules and avoid compiler warnings.
**Rationale**: Z98 is very strict about `[]u8` vs `const char*`. The interpreter uses a helper `print_str` that takes a slice to remain idiomatic while interfacing with the runtime.

### Single Expression REPL
**Workaround**: `main.zig` reads a line and evaluates only the first parsed expression.
**Rationale**: Multi-expression line parsing would require more complex tokenizer state management or a sequence (`begin`) wrapper. For this bootstrap phase, one expression per line is sufficient and documented as a known limitation.

### Mutable Slot for Recursion
**Workaround**: `define` uses a two-step process: it first creates an environment node with a `Nil` placeholder, then evaluates the body, and finally updates the placeholder in-place.
**Rationale**: This enables recursive closures (like `fact` calling `fact`) where the closure needs to capture an environment that already contains itself.
