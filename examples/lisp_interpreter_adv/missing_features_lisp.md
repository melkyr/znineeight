# Detailed Findings from the Lisp Interpreter "Baptism of Water"

This document records the issues, bugs, and limitations discovered while attempting to compile and run both downgraded and advanced Z98 Lisp interpreters.

## 1. Summary of Performance
- **Peak Memory Usage (Compiler)**: ~2.85 MB during compilation of the advanced multi-file interpreter.
- **Limit Verification**: Well within the 16MB technical constraint.

## 2. Syntax & Parser Constraints

### `anyerror` Keyword
- **Status**: **LIMITATION**
- **Observation**: The compiler explicitly rejects the `anyerror` keyword in function signatures.
- **Workaround**: Use `!T` for inferred error sets or define a specific error set (e.g., `const LispError = error { ... };`).

### `pub const` Function Aliasing
- **Status**: **BUG**
- **Observation**: Code like `pub const deep_copy = boat_copy;` causes the compiler to treat `deep_copy` as a variable during C emission, leading to "function is initialized like a variable" errors in the generated C code.
- **Workaround**: Use a wrapper function: `pub fn deep_copy(...) !T { return try boat_copy(...); }`.

### Struct + Union Decomposition
- **Status**: **REQUIRED FOR STABILITY**
- **Observation**: While `union(enum)` is theoretically supported, several codegen bugs (see below) make it unreliable for complex types like a Lisp `Value`.
- **Workaround**: Use a `struct` with a `tag` field and a separate `union` for data.

## 3. Type System & Semantic Analysis

### Tagged Union Equality and Assignment
- **Status**: **BUG/LIMITATION**
- **Observation**: Direct assignment to a tagged union (e.g., `v.* = Value{ .Int = 10 };`) often fails in the C backend because of how it tries to wrap or initialize the union.
- **Workaround**: Manually assign the tag and then the specific union member: `v.tag = .Int; v.data.Int = 10;`.

## 4. Code Generation & Runtime (C89 Backend)

### `union(enum)` Assignment (BLOCKER)
- **Status**: **BUG**
- **Observation**: Assigning a tag literal to a `union(enum)` variable (e.g., `v = .Nil;`) generates C code that attempts to assign an `int` to a `union` member named `payload`, which does not exist or is incompatible.
- **Root Cause**: `C89Emitter::emitAssignmentWithLifting` incorrectly handles tag literals for tagged unions.

### `switch` Payload Captures (BLOCKER)
- **Status**: **C89 COMPATIBILITY BUG**
- **Observation**: Switch captures (e.g., `.Cons => |data| ...`) generate anonymous struct initializers in C: `struct { ... } data = switch_tmp.data.Cons;`. C89 does not support initializing a struct from a non-constant expression in this manner.
- **Fix**: Separate declaration and assignment, or use field-by-field copy.

### Pointer Dereference Precedence (BUG)
- **Status**: **BUG**
- **Observation**: Accessing a member through a pointer (e.g., `v.tag` where `v` is a pointer) sometimes generates `*v.tag` instead of `(*v).tag` or `v->tag`. In C, `.` binds tighter than `*`, so `*v.tag` is interpreted as `*(v.tag)`.
- **Impact**: C compilation fails.

## 5. Successful Features Verified
- **Manual Tagged Unions**: `struct` + `union` pattern works robustly.
- **Error Unions & `try`/`catch`**: Successfully handles propagated errors across multiple modules.
- **Modular @import**: Multi-file architecture (8+ files) resolves and compiles correctly.
- **32-bit Compatibility**: Generated code runs correctly in `-m32` mode.
- **Arena Allocation**: Bump allocator implementation (`sand.zig`) is functional and used for all interpreter memory.
