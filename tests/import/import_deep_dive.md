# Bug Deep Dive: zig0 Cross-Module Import Type Resolution

## Problem Statement

When compiling multi-module Z98 projects with `zig0`, specifically projects with bottom-of-file imports like `lexer.zig`, the compiler sometimes reports "use of undeclared type" for types that are clearly defined in the same file.

Example: `error: use of undeclared type 'Sand'` at `sf/src/lexer.zig:12`.

## Reproduction

1. Build `zig0` in 32-bit mode: `g++ -m32 -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0`
2. Run compilation on the main entry point: `./zig0 -o out/zig1.c sf/src/main.zig`
3. Result: `sf/src/lexer.zig:12:115: error: use of undeclared type` for `Sand`.

## Root Cause Analysis

Based on the deep dive using debug logs and source analysis of `src/bootstrap/`, the following issues were identified:

### 1. Module Context Mismatch during Import Resolution
In `CompilationUnit::resolveImportsRecursive`, the compiler iterates through `@import` nodes in an AST. While it correctly loads and parses imported files, it **does not update the current module context** (`current_module_`) before recursing or registering the module symbol in the symbol table.

This leads to "module alias" symbols (like `allocator` from `const allocator = @import("allocator.zig");`) being injected into the wrong module's symbol table. Specifically, when `main.zig` imports `lexer.zig`, which in turn imports `allocator.zig`, the `allocator` symbol may end up in `main`'s symbol table instead of `lexer`'s.

### 2. Pass 1 / Pass 2 Race Condition
The `TypeChecker` uses a two-pass approach:
- **Pass 1**: Registers top-level `const`/`var` declarations and types as placeholders.
- **Pass 2**: Resolves function bodies and complex expressions.

The bug triggers when a module (like `lexer.zig`) has its types (like `Sand`) defined via a `const` import at the bottom of the file.

If `main.zig` triggers Pass 2 (signature checking) of a function in `lexer.zig` (like `lexerInit`) **before** Pass 1 of `lexer.zig` has reached the bottom of the file to register the `Sand` symbol, the lookup fails.

### 3. Consolidated vs. Distributed Imports
The bug report noted that multiple function-local `@import` calls worked, but a single consolidated one failed. This is because distributed imports in separate code paths may "hide" the issue by ensuring Pass 1 of the imported module completes in a different context, or by bypassing the caching mechanism that fails when the consolidated import is processed during `main`'s Pass 2.

## Proposed Remediation

To resolve this issue and improve the robustness of the `zig0` bootstrap compiler, the following remediation steps are proposed:

### Remediation A: Correct Module Context in `resolveImportsRecursive`
Modify `src/bootstrap/compilation_unit.cpp` to ensure that `setCurrentModule` is called with the imported module's name before processing its imports, and restored afterward.

```cpp
// Proposed fix in resolveImportsRecursive
const char* old_mod = current_module_;
setCurrentModule(imported_mod->name);
// ... process imports ...
setCurrentModule(old_mod);
```

### Remediation B: Ensure Pass 1 Completion for Dependencies
Update `CompilationUnit::performFullPipeline` to ensure that **all** modules have completed Pass 1 (placeholder registration) before **any** module begins Pass 2 (full checking). Currently, the loop structure might allow Pass 2 of an early module in the topological sort to trigger recursive resolution of a later module's symbols that haven't been registered yet.

### Remediation C: Improve `TypeChecker::visitTypeName` Lookup
Enhance the identifier lookup in `TypeChecker::visitTypeName` to explicitly check if the current module has any pending Pass 1 declarations that match the requested name before reporting it as undeclared.

## Conclusion

This is a **Real zig0 Bug** caused by a combination of improper module context management during the import phase and a race condition between the registration of symbols in Pass 1 and their use in function signatures in Pass 2. It is not a misinterpretation of Z98 syntax.
