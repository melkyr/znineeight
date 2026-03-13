# Comprehensive Findings: "Baptism of Fire" JSON Parser

The attempt to compile a non-trivial JSON parser in Z98 revealed significant architectural and implementation gaps in the RetroZig bootstrap compiler. While individual features (like tagged unions or ranges) pass isolated unit tests, they fail to work together in a complex, multi-module application.

## Peak Memory Usage
- **Tiny Program**: ~18 KB
- **JSON Parser (Full Run)**: ~83 KB
- **Limit**: 16 MB (PASS)

## 1. Tagged Union Critical Failures
### C89 Keyword Mismatch
- **Problem**: Tagged unions are correctly identified as `TYPE_UNION` (with `is_tagged=true`) and emitted as C `struct`s. However, the code generator consistently uses the `union` keyword for variable declarations of these types.
- **Result**: `error: ‘z_repro_union_U’ defined as wrong kind of tag`.
- **Root Cause**: `C89Emitter::emitBaseType` and related logic do not distinguish between bare unions and tagged unions when emitting the type keyword for declarations.

### Member Access Resolution
- **Problem**: Accessing union tags (e.g., `JsonValue.Null`) often fails during type checking with `member access '.' only allowed on structs, unions, enums...`.
- **Root Cause**: Inconsistent unwrapping of `TYPE_TYPE` and `TYPE_PLACEHOLDER` in `visitMemberAccess`.

## 2. Constant Evaluation Limitations
### Character Literals in Ranges
- **Problem**: `switch` ranges using character literals (e.g., `'0'...'9'`) are rejected.
- **Result**: `error: Range bounds must be compile-time constants`.
- **Root Cause**: `TypeChecker::evaluateConstantExpression` lacks a case for `NODE_CHAR_LITERAL`.

## 3. Slice and Coercion Bugs
### String to Slice Coercion
- **Problem**: Implicitly converting `"literal"` to `[]const u8` fails when passed as a function argument.
- **Result**: `error: incompatible argument type ... expected '[]const u8', got '*const u8'`.
- **Root Cause**: `TypeChecker::coerceNode` is not consistently applied in `visitFunctionCall` or assignment contexts for string literals.

### Missing Slice Definitions
- **Problem**: When a slice is used in a private function, the `typedef struct Slice_...` and its `__make_slice_...` helper are often missing from the generated `.c` file.
- **Root Cause**: The type emission cache/logic in `CBackend` and `C89Emitter` is too restrictive or fails to transitively identify needed slices for local scopes.

## 4. Multi-Module / @import Instability
### Cross-Module Symbols
- **Problem**: Frequent `use of undeclared identifier` for symbols imported from other modules.
- **Root Cause**: The symbol table merging/lookup logic across multiple `CompilationUnit` passes appears to lose or mis-mangled symbols during the code generation phase.

## 5. Implementation Sensitivity
### Braceless Syntax
- **Problem**: Semicolon requirements in braceless bodies are inconsistent. `=> continue,` triggers a syntax error while `=> { continue; }` passes.
- **Recommendation**: Formalize semicolon rules for braceless control flow in the language spec.

## 6. Recursive Type Gaps
### Incomplete Self-Reference
- **Problem**: Types like `struct { v: []Self }` fail with `field has incomplete type`.
- **Root Cause**: The aggressive resolution of placeholders in `visitArraySlice` and `visitArrayType` is insufficient when the recursion is indirect (through a slice or pointer).

## Summary
The compiler is currently in a "feature-complete but integration-failed" state for Z98. The Milestone 9 features exist in the codebase but are not robust enough for a production-level application like a JSON parser. Immediate focus should be on fixing the C89 keyword mismatch for tagged unions and stabilizing cross-module symbol resolution.
