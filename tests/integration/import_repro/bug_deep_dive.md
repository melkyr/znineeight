# Bug Deep Dive: Transitive Alias Blockades in Global Scope

## 1. Bug Summary
The Z98 bootstrap compiler (`zig0`) fails to compile global constant declarations that use module member access as their initializer, such as `const Foo = @import("a.zig").Foo;`. This happens because the C89 code generator incorrectly identifies these initializers as non-constant, triggering the `ERR_GLOBAL_VAR_NON_CONSTANT_INIT` error. This issue pervasive across the `sf/src/` codebase, preventing it from bootstrapping.

## 2. Reproduction Analysis
Using the minimal reproduction in `tests/integration/import_repro/`:

**a.zig**:
```zig
pub const Foo = struct { x: u32 };
```

**b.zig**:
```zig
const Foo = @import("a.zig").Foo; // Error: global variable must have constant initializer
```

### Tracing the failure:
1.  The `Parser` identifies `@import("a.zig").Foo` as a `NODE_MEMBER_ACCESS` where the base is a `NODE_IMPORT_STMT`.
2.  During semantic analysis (`Phase 0.5` and `Phase 2`), the `TypeChecker` correctly resolves this member access. It finds that `Foo` in `a.zig` is a type, so it sets the `resolved_type` of the `NODE_MEMBER_ACCESS` to `TYPE_TYPE` (and caches the actual struct type).
3.  In the Code Generation phase, `C89Emitter::emitGlobalVarDecl` (src/bootstrap/codegen.cpp:425) is called for the declaration of `Foo`.
4.  It performs two critical checks on the initializer:
    -   `isTypeExpression(decl->initializer, ...)`: This is intended to skip type declarations so they don't emit C code.
    -   `isConstantInitializer(decl->initializer)`: This ensures global variables have C-compatible constant initializers.

Both checks fail for `NODE_MEMBER_ACCESS`.

## 3. Root Cause Identification

### A. `isTypeExpression` Incompleteness
Located in `src/bootstrap/ast_utils.cpp`:
```cpp
bool isTypeExpression(ASTNode* node, SymbolTable& symbols) {
    if (!node) return false;
    switch (node->type) {
        case NODE_TYPE_NAME:
        case NODE_POINTER_TYPE:
        // ... (other type nodes)
            return true;
        case NODE_IDENTIFIER: {
            // ... (checks for primitives and SYMBOL_TYPE)
        }
        default:
            return false; // NODE_MEMBER_ACCESS falls through here!
    }
}
```
`isTypeExpression` does not account for `NODE_MEMBER_ACCESS`. Even if the member access resolves to a type (like `mod.Type`), it returns `false`. Consequently, `emitGlobalVarDecl` does not skip the type alias and proceeds to validate it as a variable initializer.

### B. `isConstantInitializer` Limitations
Located in `src/bootstrap/codegen.cpp`:
```cpp
case NODE_MEMBER_ACCESS: {
    /* Enum member access is constant */
    if (node->as.member_access->base->resolved_type) {
        Type* t = node->as.member_access->base->resolved_type;
        if (t->kind == TYPE_ENUM) {
            return true;
        }
    }
    return false;
}
```
`isConstantInitializer` only returns `true` for `NODE_MEMBER_ACCESS` if it's an enum member. It doesn't recognize that a member access resolving to `TYPE_TYPE` (a type alias) or `TYPE_MODULE` (a module alias) is also "constant" in the context of Z98 global scope (where these aliases are handled as metadata).

## 4. Proposed Fix

The fix involves updating these utility functions to correctly recognize module-qualified types and constants.

### Step 1: Update `isTypeExpression` in `src/bootstrap/ast_utils.cpp`
Add a case for `NODE_MEMBER_ACCESS` that checks if it resolves to a type:
```cpp
case NODE_MEMBER_ACCESS: {
    if (node->resolved_type && node->resolved_type->kind == TYPE_TYPE) {
        return true;
    }
    // Fallback: check the symbol if it's already resolved
    if (node->as.member_access && node->as.member_access->symbol) {
        Symbol* sym = node->as.member_access->symbol;
        return (sym->kind == SYMBOL_TYPE || sym->kind == SYMBOL_UNION_TYPE);
    }
    return false;
}
```

### Step 2: Update `isConstantInitializer` in `src/bootstrap/codegen.cpp`
Expand `NODE_MEMBER_ACCESS` handling to include types and modules:
```cpp
case NODE_MEMBER_ACCESS: {
    if (node->resolved_type) {
        if (node->resolved_type->kind == TYPE_TYPE || node->resolved_type->kind == TYPE_MODULE) {
            return true;
        }
        // ... existing enum check ...
    }
    return false;
}
```

### Step 3: Harden `emitGlobalVarDecl` in `src/bootstrap/codegen.cpp`
Ensure that constant aliases to types are always skipped:
```cpp
if (decl->is_const) {
    if (isTypeExpression(decl->initializer, unit_.getSymbolTable())) return;

    // Also check if it resolved to TYPE_TYPE during semantic analysis
    if (decl->initializer->resolved_type && decl->initializer->resolved_type->kind == TYPE_TYPE) {
        return;
    }
}
```

## 5. Impact on Stage 1 Bootstrap
By allowing global type aliases via member access, we unblock the compilation of `sf/src/pal.zig`, `sf/src/ast.zig`, and most other files in the Stage 1 compiler. These files rely heavily on the pattern:
```zig
const Sand = @import("allocator.zig").Sand;
```
Once the codegen correctly identifies these as type aliases (and thus skips emitting C variable declarations for them), the "global variable must have constant initializer" error will be resolved for these cases.
