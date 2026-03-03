# Missing Features for JSON Parser ("Baptism of Fire" Report)

This document details the findings from testing the Z98 compiler against a modular JSON parser implementation.

## Critical Failures (Blockers)

### 1. Multi-Module Error Type Resolution
**Issue**: Defining an error set in an imported module and using it in a function signature within that same module causes "use of undeclared type" errors in the importer.
**Minimal Example**:
```zig
// file.zig
pub const MyError = error { Foo };
pub fn foo() MyError!void { return; }

// main.zig
const f = @import("file.zig");
pub fn main() void { f.foo() catch {}; }
```
**Result**: Compiler reports `use of undeclared type 'MyError'` when analyzing `file.zig` from the context of `main.zig`.

### 2. Compiler Aborts on Complex Modules
**Issue**: The full JSON parser implementation causes the bootstrap compiler to `plat_abort()`. This likely stems from recursive type resolution or complex expression lifting in the C89 backend that hasn't been hardened.

## Missing Language Features & Deficiencies

### 1. String Literal Coercion
**Issue**: String literals (type `*const u8`) do not implicitly coerce to slices (`[]const u8`).
**Workaround**: Use manual slicing ` "foo"[0..3] ` or explicit construction.

### 2. Mandatory `return;` for `Error!void`
**Issue**: Functions returning an error union with a `void` payload must have an explicit `return;` even if they naturally reach the end of the block.
**Diagnostic**: `error: missing return value - hint: not all control paths return a value`.

### 3. Array Indexing on Captured Slices
**Issue**: Indexing into a slice obtained via member access (e.g., `input[pos]`) often triggers "Potential null pointer dereference" warnings from the `NullPointerAnalyzer`.

## Stability Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Modular Imports | ⚠️ Buggy | Basic imports work, but type resolution across modules is fragile for non-primitive types. |
| Recursive Types | ✅ Stable | Using pointers to break cycles (`*JsonData`) works correctly in isolated tests. |
| Error Unions | ⚠️ Buggy | Work in single-file tests; fail in multi-module imports. |
| Slices | ✅ Works | Slicing syntax `[start..end]` is supported but coercion from pointers is missing. |
| Bare Unions | ✅ Stable | Manual tagging with `enum` and `struct` works as expected. |

## Recommendations for Phase 8

1.  **Harden Multi-Module Resolution**: Fix the symbol lookup for types defined in imported modules. The parser/type-checker seems to lose track of module-local types during signature resolution of dependencies.
2.  **Implement String to Slice Coercion**: Add implicit coercion for string literals to `[]const u8` to simplify common operations.
3.  **Improve Parser Synchronization**: Replace `plat_abort()` with a synchronization mechanism so multiple errors can be reported.
4.  **Refine Null Pointer Analyzer**: Reduce false positives for slice indexing where the underlying pointer is guaranteed by the slice's length.
