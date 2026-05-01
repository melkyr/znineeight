# Bug Deep Dive: `resolveCallSite` Cross-Module Context Switch

## Overview

This document details the exploration and analysis of a critical bug in the Z98 bootstrap compiler (`zig0`) related to on-demand function signature resolution during cross-module calls. This investigation was prompted by reports of segmentation faults when compiling the multi-module "SF" compiler.

## Problem Statement

The Z98 compiler uses a modular architecture where each `.zig` file is a separate module with its own symbol table. When a module (the *caller*) invokes a function defined in another module (the *callee*), the compiler may need to resolve the callee's function signature on-demand if that module hasn't been fully type-checked yet (which can happen during the interleaved Pass 2 type-checking phase).

The core of the issue lies in `TypeChecker::resolveCallSite` (located at `src/bootstrap/type_checker.cpp:7172`). When it encounters a symbol that hasn't been resolved yet, it attempts to resolve it by calling `visitFnSignature` (for functions) or `visitVarDecl` (for variables). However, it does so **without switching the compilation unit's current module context** to the module where the symbol is actually defined.

## Reproduction Analysis

### Target Case: `sf/src/main.zig`

The reproduction target is the "SF" compiler source located in `sf/src/`. The failure occurs when `main.zig` calls a function from another module that uses types defined in a third module.

**In `sf/src/main.zig`:**
```zig
const lexer_mod = @import("lexer.zig");
// ...
var lex = lexer_mod.lexerInit(source, 0, &interner, &diag, &compiler_alloc.module);
```

**In `sf/src/lexer.zig`:**
```zig
const Sand = @import("allocator.zig").Sand;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;

pub fn lexerInit(source: []const u8, file_id: u32, interner: *StringInterner, diag: *DiagnosticCollector, alloc: *Sand) Lexer {
    // ...
}
```

### Failure Mechanism (Step-by-Step)

1.  **Context:** The `TypeChecker` is currently processing `main.zig`. `unit_.getCurrentModule()` returns `"main"`.
2.  **Call Site:** The compiler reaches the call to `lexer_mod.lexerInit`.
3.  **Symbol Lookup:** `resolveCallSite` correctly identifies that `lexerInit` belongs to the `lexer` module.
4.  **On-Demand Resolution:** Because `lexer.zig` might not be fully type-checked yet, `lexerInit->symbol_type` is `NULL`.
5.  **The Bug:** `resolveCallSite` calls `visitFnSignature((ASTFnDeclNode*)sym->details)`.
6.  **Incorrect Scope:** `visitFnSignature` begins resolving the types in the signature (`StringInterner`, `DiagnosticCollector`, `Sand`).
7.  **Lookup Failure:** Because the `current_module_` is still set to `"main"`, the type lookup looks for these names in the scope of `main.zig`.
8.  **Mismatch/Absence:**
    - In `main.zig`, `StringInterner` is not a top-level name; it's accessed via `interner_mod.StringInterner`.
    - `lexer.zig`'s own imports are invisible because the context is wrong.
9.  **Corruption:** The type resolution returns `TYPE_UNDEFINED` for the parameters.
10. **Crash:** The compiler eventually encounters a `NULL` pointer or an inconsistent state when attempting to use this malformed signature, leading to the observed **Segmentation Fault**.

## Findings from Debugging

### Compilation Environment
As suggested by the Zig0Labs team, the compiler was built with full debug symbols and logs enabled:
- `g++ -g -Isrc/include -DDEBUG -DMEASURE_MEMORY -DDEBUG_HEADER_GEN -DZ98_ENABLE_DEBUG_LOGS`
- Building as a 64-bit binary allowed for better `valgrind` integration on the host system, confirming that the crash is indeed a memory access violation resulting from the failed type resolution.

### L-Value Side Bug
During reproduction, a secondary issue was identified. The code:
```zig
&compiler_alloc.module
```
failed with `error: l-value expected`. This indicates that `NODE_MEMBER_ACCESS` was not being treated as a valid l-value by the address-of operator (`&`) in the `TypeChecker`. While separate from the `resolveCallSite` logic, it prevents the SF compiler from progressing.

### Verification of Bug Nature
This is confirmed to be a **genuine bug** in the `zig0` compiler's cross-module resolution logic. It is not a syntax misunderstanding; the Zig code in `sf/src` is standard Z98 syntax. The compiler's failure to maintain context during on-demand resolution violates the principle of modular isolation.

## Proposed Remediation

The remediation involves wrapping the deferred resolution logic in `resolveCallSite` with a module context swap, mirroring the successful pattern used in `handleModuleMemberFound`.

### Implementation Proposal

Update `src/bootstrap/type_checker.cpp` at the deferred resolution block:

```cpp
/* Guard 4: Forward Reference / Not resolved yet */
if (!sym->symbol_type && sym->details) {
    // 1. Save the caller's module context
    const char* saved_module = unit_.getCurrentModule();

    // 2. Switch to the callee's module context
    if (sym->module_name) {
        unit_.setCurrentModule(sym->module_name);
    }

    // 3. Resolve the signature in the correct context
    if (sym->kind == SYMBOL_FUNCTION) {
        ResolvingSignatureGuard guard(*this);
        visitFnSignature((ASTFnDeclNode*)sym->details);
    } else if (sym->kind == SYMBOL_VARIABLE) {
        ResolvingSignatureGuard guard(*this);
        visitVarDecl(NULL, (ASTVarDeclNode*)sym->details);
    }

    // 4. Restore the original context
    unit_.setCurrentModule(saved_module);
}
```

### Additional Recommendations
- **L-Value Fix:** Update `TypeChecker::visitUnaryOp` for `TOKEN_AMPERSAND` to include `NODE_MEMBER_ACCESS` as a valid l-value.
- **Null Safety:** Add more robust null checks in `visitFnSignature` to ensure that if a type fails to resolve, it doesn't lead to a segfault.

## Conclusion

The `resolveCallSite` bug is a fundamental flaw in how the bootstrap compiler handles transitive dependencies during on-demand resolution. Implementing the proposed context-switch fix is essential for the stability of the bootstrap process and the successful compilation of the self-hosted compiler stages.
