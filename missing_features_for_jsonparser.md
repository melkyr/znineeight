# Comprehensive Findings: "Baptism of Fire" JSON Parser

The attempt to compile a non-trivial JSON parser in Z98 revealed significant architectural and implementation gaps in the RetroZig bootstrap compiler. While individual features (like tagged unions or ranges) pass isolated unit tests, they fail to work together in a complex, multi-module application.

## Peak Memory Usage
- **Tiny Program**: ~18 KB
- **JSON Parser (Full Run)**: ~524 KB
- **Limit**: 16 MB (PASS)

## 1. Feature Status & Integration Gaps

### Tagged Unions (`union(enum)`)
- **Status**: Implemented but broken in integration.
- **Problem**: The compiler correctly identifies tagged unions as `TYPE_UNION` (with `is_tagged=true`) and emits them as C `struct`s. However, the code generator consistently uses the `union` keyword for variable declarations of these types.
- **Result**: `error: ‘z_repro_union_U’ defined as wrong kind of tag` (in C compiler).
- **Workaround**: Manually implement tagged unions using a `struct` with an `enum` tag and a bare `union` data field.

### Switch Captures (`|capture|`)
- **Status**: Implemented but unstable.
- **Problem**: Captured symbols often fail to resolve in the prong body or trigger internal compiler errors when the condition type is not recognized as a tagged union due to placeholder resolution delays.
- **Workaround**: Use manual tag checks and field access (e.g., `if (val.tag == .Foo) { const x = val.data.Foo; ... }`).

### Range-based Switch Arms (`0...9`)
- **Status**: Implemented but restricted.
- **Problem**: `switch` ranges using character literals (e.g., `'0'...'9'`) are rejected because `evaluateConstantExpression` lacks a case for `NODE_CHAR_LITERAL`.
- **Workaround**: Use manual integer constants in ranges or `if-else` chains.

### Recursive Types
- **Status**: Partially Supported.
- **Problem**: Indirectly recursive types (e.g., `union { Array: []Self }`) trigger `field 'value' has incomplete type` because the layout calculation for slices/arrays requires the element size before the placeholder is fully mutated.
- **Workaround**: Use single-item pointers (`*Self`) for recursion, as pointers have fixed sizes (4 bytes) regardless of target completeness.

## 2. Stability & Coercion Bugs

### String to Slice Coercion
- **Problem**: Implicitly converting `"literal"` to `[]const u8` fails when passed as a function argument.
- **Result**: `error: incompatible argument type ... expected '[]const u8', got '*const u8'`.
- **Workaround**: Use manual slice construction or `@ptrCast` for C interop functions.

### Array-to-Pointer Coercion
- **Problem**: Passing a pointer to an array (`&buf`) where a many-item pointer (`[*]u8`) is expected fails during type checking or produces invalid C.
- **Workaround**: Use `@ptrCast` to convert explicitly.

### Multi-Module / @import Instability
- **Problem**: Frequent `use of undeclared identifier` or `Function symbol not found` for symbols imported from other modules in complex dependency graphs.
- **Root Cause**: Symbol table merging across multiple `CompilationUnit` passes appears to lose visibility or mangling information.

### Braceless Control Flow Syntax
- **Problem**: Semicolon requirements in braceless bodies are inconsistent. `=> continue,` triggers a syntax error while `=> continue;,` (or with braces) passes.

## 3. Toolchain Limitations
- **32-bit Compilation**: `gcc -m32` is the target for 1998-era software, but local verification is currently blocked by missing 32-bit system headers (e.g., `bits/libc-header-start.h`) in the modern Ubuntu environment.

## Summary
The compiler is currently in a "feature-complete but integration-failed" state for Z98. The Milestone 9 features exist in the codebase but are not robust enough for a production-level application like a JSON parser. Immediate focus should be on fixing the C89 keyword mismatch for tagged unions, adding character literal support to constant evaluation, and stabilizing cross-module symbol resolution.
