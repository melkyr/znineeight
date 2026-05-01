# Deep Dive: `resolveCallSite` Cross-Module Type Resolution Bug

## 1. Summary
This document details the investigation into a logic flaw in `zig0`'s type checker where cross-module function calls trigger on-demand signature resolution without correctly switching the module context. This results in "use of undeclared type" errors when the called function's signature refers to types from modules that the caller has not imported.

## 2. Reproduction
The issue is most easily reproduced using a circular dependency or an ordering where a module is type-checked before its dependency's signatures are fully resolved.

### Test Case: `repro_bug`
**modules/c.zig**
```zig
pub const DataC = struct { v: u32 };
```

**modules/b.zig**
```zig
const c = @import("c.zig");
pub fn process(d: c.DataC) void { _ = d; }
```

**modules/a.zig**
```zig
const m = @import("../main.zig");
const b = @import("b.zig");
pub fn foo() void {
    // When a.zig is checked, it calls b.process.
    // If b.process signature isn't resolved yet, resolveCallSite triggers it.
    b.process(.{ .v = 1u });
}
```

**main.zig**
```zig
const a = @import("modules/a.zig");
pub fn main() void {
    a.foo();
}
```

### Observed Error
```
modules/b.zig:2:20: error: use of undeclared type
    pub fn process(d: c.DataC) void { _ = d; }
                      ^
    hint: use of undeclared type 'c'
```
Even though `b.zig` imports `c.zig`, the type checker fails to find `c` because it is looking in the context of `a.zig` (the caller).

## 3. Technical Analysis

### 3.1 Logic Flow
1. `TypeChecker::visitFunctionCall` is called for `b.process(...)` in `a.zig`.
2. It calls `resolveCallSite`.
3. `resolveCallSite` finds the symbol for `process` in module `b`.
4. Since `b` has not been fully type-checked yet (due to the topological sort order or circularity), `sym->symbol_type` is `NULL`.
5. `resolveCallSite` (at `type_checker.cpp:7223`) attempts to resolve the signature:
   ```cpp
   if (sym->kind == SYMBOL_FUNCTION) {
       visitFnSignature((ASTFnDeclNode*)sym->details);
   }
   ```
6. **The Bug**: `visitFnSignature` is called on the current `TypeChecker` instance. Crucially, the `CompilationUnit`'s "current module" state is still set to `a.zig`.
7. Inside `visitFnSignature`, when it encounters `d: c.DataC`, it tries to resolve `c`.
8. The lookup fails because `a.zig` does not import `c.zig`. Only `b.zig` does.

### 3.2 Comparison with Correct Pattern
The correct pattern for cross-module resolution is implemented in `TypeChecker::handleModuleMemberFound`. It explicitly saves the current module, switches to the target module, and uses a new `TypeChecker` instance or ensures the state is correct:

```cpp
const char* saved_module = unit_.getCurrentModule();
unit_.setCurrentModule(target_mod->name);
TypeChecker target_checker(unit_);

if (sym->kind == SYMBOL_FUNCTION) {
    ResolvingSignatureGuard guard(target_checker);
    target_checker.visitFnSignature((ASTFnDeclNode*)sym->details);
}
unit_.setCurrentModule(saved_module);
```

`resolveCallSite` lacks this context-switching logic, causing it to "leak" the caller's module scope into the callee's signature resolution.

## 4. Crash Analysis
While the primary symptom observed in this environment was a diagnostic error, the original bug report mentions segfaults.
- **Hypothesis**: If `sym->module_name` is accessed without a NULL check, or if the recursive call to `visitFnSignature` triggers a secondary resolution that encounters a partially initialized state, it could lead to memory corruption or stack exhaustion.
- **Observation**: In the Z98 architecture, `CompilationUnit`'s `current_module_` is a global state used by various helpers. Mismatched module context during recursive type resolution is a known source of instability in the Milestone 11 compiler.

## 5. Proposed Remediation

The `resolveCallSite` function should be updated to switch the module context before triggering signature resolution.

### Proposed Fix in `src/bootstrap/type_checker.cpp`:
```cpp
<<<<<<< SEARCH
    /* Guard 4: Forward Reference / Not resolved yet */
    if (!sym->symbol_type && sym->details) {
        if (sym->kind == SYMBOL_FUNCTION) {
            visitFnSignature((ASTFnDeclNode*)sym->details);
        } else if (sym->kind == SYMBOL_VARIABLE) {
            visitVarDecl(NULL, (ASTVarDeclNode*)sym->details);
        }
    }
=======
    /* Guard 4: Forward Reference / Not resolved yet */
    if (!sym->symbol_type && sym->details) {
        const char* saved_module = unit_.getCurrentModule();
        if (sym->module_name) {
            unit_.setCurrentModule(sym->module_name);
        }

        if (sym->kind == SYMBOL_FUNCTION) {
            ResolvingSignatureGuard guard(*this);
            visitFnSignature((ASTFnDeclNode*)sym->details);
        } else if (sym->kind == SYMBOL_VARIABLE) {
            ResolvingSignatureGuard guard(*this);
            visitVarDecl(NULL, (ASTVarDeclNode*)sym->details);
        }

        unit_.setCurrentModule(saved_module);
    }
>>>>>>> REPLACE
```

### Why this works:
1. **Context Switching**: `unit_.setCurrentModule(sym->module_name)` ensures that subsequent identifier lookups (like `c.DataC`) are performed relative to the module where the function is defined.
2. **Signature Guard**: `ResolvingSignatureGuard` ensures that `is_resolving_signature_` is true, preventing the types from being incorrectly tagged as "local" to the caller's function body.
3. **State Restoration**: `unit_.setCurrentModule(saved_module)` restores the caller's context so that the rest of the caller's body is checked correctly.

## 6. Conclusion
This is a **Real Bug** in the `zig0` compiler. It stems from an oversight in maintaining the module context during on-demand semantic analysis of cross-module dependencies. Implementing the proposed remediation will align `resolveCallSite` with the established and correct pattern used elsewhere in the `TypeChecker`.
