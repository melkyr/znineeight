# Bug: `isTypeExpression()` broke by C89FeatureValidator fix attempt

## Summary

The attempted fix for the C89FeatureValidator false positive added a check
in `isTypeExpression()` (`ast_utils.cpp:33-52`) that only returns true for
`NODE_MEMBER_ACCESS` if the **base** identifier's symbol kind is
`SYMBOL_TYPE`/`SYMBOL_UNION_TYPE`/`SYMBOL_MODULE`. This fix broke `isTypeExpression`
for a SECOND caller: `codegen.cpp:451`, which uses it to decide if a global
`const` is a type alias and should be skipped during codegen.

**Result:** Assertion crash at `ast_utils.cpp:41` when any identifier lacks a
resolved symbol. Fixing the assertion to a null-check causes the import type
alias skip in codegen.cpp to stop working, regressing "global variable must
have constant initializer" errors.

## Assertion Fix

**File:** `src/bootstrap/ast_utils.cpp:41`

Replace the `Z98_ASSERT` with a null-guard:

```cpp
// BEFORE (crashes):
Z98_ASSERT(ma->base->as.identifier.symbol != NULL);

// AFTER (safe):
if (!ma->base->as.identifier.symbol) return false;
```

**Why this is safe:** `isTypeExpression` is called from
`registerAliasPlaceholderIfNeeded` (type_checker.cpp:916) during placeholder
registration, BEFORE all symbols are resolved. At this stage, some identifiers
in `NODE_IDENTIFIER` base nodes lack resolved symbols. Returning `false` from
`isTypeExpression` means "this expression is NOT a type expression (yet)" —
which is correct: if we can't tell whether it's a type, we conservatively say
it's not. The placeholder registration will fail gracefully and re-enter later.

**Crash call chain:**
```
TypeChecker::registerPlaceholders(type_checker.cpp:916)
  → isTypeExpression(vd->initializer, symbols)     (ast_utils.cpp:5)
    → NODE_MEMBER_ACCESS case (ast_utils.cpp:33)
      → NODE_IDENTIFIER base branch (ast_utils.cpp:39)
        → Z98_ASSERT(ma->base->as.identifier.symbol != NULL)   ← CRASH
```

**After the null-guard fix:** `isTypeExpression` returns false for unresolved
identifiers → `registerAliasPlaceholderIfNeeded` skips → placeholder
registration continues → symbols resolve later → subsequent passes work.

## Deeper Issue: Wrong Symbol Table Passed to `isTypeExpression`

After fixing the assertion, `isTypeExpression` still returns false for patterns
like `const Sand = alloc_mod.Sand` (where `alloc_mod` is a module import
defined in the same file). Root cause:

**`codegen.cpp:451` passes the GLOBAL symbol table, not the MODULE table:**

```cpp
// codegen.cpp:451
if (decl->is_const && isTypeExpression(decl->initializer, unit_.getSymbolTable())) {
```

`unit_.getSymbolTable()` returns the **global** symbol table, which only has
built-in types and runtime symbols — NOT module-specific declarations like
`alloc_mod`. The module-local `alloc_mod` symbol lives in `pal.zig`'s
module-level symbol table.

**Two approaches were tested and both fail:**

| Approach | Why it fails |
|----------|-------------|
| `symbols.lookup("alloc_mod")` in `isTypeExpression` | `symbols` is the global table — `alloc_mod` not found |
| Guard `ma->base->as.identifier.symbol` against NULL | Symbol pointer IS set at codegen time, but `SYMBOL_MODULE` check succeeds — the `NODE_MEMBER_ACCESS` returns true, BUT the `import` const itself (`alloc_mod`) has `vd->type` set to `TYPE_MODULE` so it's skipped by line 915 of `registerAliasPlaceholderIfNeeded` |

**The real fix: pass the correct symbol table.**

In `codegen.cpp:451`, the `isTypeExpression` call should use the MODULE's
symbol table for the declaration being processed, not the global table:

```cpp
// Get the module where this declaration lives
Module* mod = unit_.getModule(decl->module_name ? decl->module_name : unit_.getCurrentModule());
if (decl->is_const && isTypeExpression(decl->initializer, mod ? mod->symbols->getTable() : unit_.getSymbolTable())) {
    return;
}
```

Similarly, in `type_checker.cpp:916` (`registerAliasPlaceholderIfNeeded`),
the `isTypeExpression` call should pass the current module's symbol table
(which IS available during Phase 2, just not through the direct AST pointer).

## Root Cause

`isTypeExpression()` is called by TWO passes with different semantics:

### Caller 1: `codegen.cpp:451` — global const type alias detection

```cpp
if (decl->is_const && isTypeExpression(decl->initializer, unit_.getSymbolTable())) {
    return; // skip: this is a type alias, not a runtime variable
}
```

For `const Sand = @import("allocator.zig").Sand;`:
- Initializer is `NODE_MEMBER_ACCESS` with `base = @import(...)`, `field = Sand`
- The OLD code returned true because `ma->symbol->kind == SYMBOL_TYPE` (Sand is a type)
- **This is correct** — `const Sand` is a type alias, skip it in codegen
- The engineer's fix made this return false because `@import()` doesn't have
  an identifier symbol with kind SYMBOL_TYPE/MODULE at that point

### Caller 2: `c89_feature_validator.cpp:540` — function argument type check

```cpp
if (isTypeExpression((*call->args)[i], unit.getSymbolTable())) {
    reportNonC89Feature(...); // reject generic function calls
}
```

For `getInfixInfo(tok.kind)`:
- Argument is `NODE_MEMBER_ACCESS` with `base = tok` (local var), `field = kind`
- The OLD code returned true because `ma->symbol->kind == SYMBOL_TYPE` (kind's type is TokenKind enum)
- **This is wrong** — `tok.kind` is a VALUE, not a type
- The engineer's fix correctly returns false because `tok` is a `SYMBOL_VARIABLE`

### The conflict

The old code worked correctly for Caller 1 but failed for Caller 2.
The engineer's fix correctly handles Caller 2 but breaks Caller 1.
Both conditions are needed.

## Fix

The `NODE_MEMBER_ACCESS` handler needs to return true if **either** condition holds:

```cpp
case NODE_MEMBER_ACCESS: {
    const ASTMemberAccessNode* ma = node->as.member_access;
    if (!ma || !ma->base) return false;

    // Condition A: The base is itself a type/module identifier
    // (handles: token_mod.TokenKind, alloc_mod.Sand where mod is a module)
    if (ma->base->type == NODE_IDENTIFIER && ma->base->as.identifier.symbol) {
        Symbol* base_sym = ma->base->as.identifier.symbol;
        if (base_sym->kind == SYMBOL_TYPE ||
            base_sym->kind == SYMBOL_UNION_TYPE ||
            base_sym->kind == SYMBOL_MODULE) {
            return true;
        }
        // Also check const variables with TYPE_MODULE type
        // (handles: const alloc_mod = @import("allocator.zig"))
        if (base_sym->kind == SYMBOL_VARIABLE &&
            (base_sym->flags & SYMBOL_FLAG_CONST) &&
            base_sym->symbol_type &&
            base_sym->symbol_type->kind == TYPE_MODULE) {
            if (ma->symbol && (ma->symbol->kind == SYMBOL_TYPE ||
                               ma->symbol->kind == SYMBOL_UNION_TYPE)) {
                return true;
            }
        }
    } else if (ma->base->type == NODE_TYPE_NAME ||
               ma->base->type == NODE_POINTER_TYPE ||
               ma->base->type == NODE_ARRAY_TYPE ||
               ma->base->type == NODE_OPTIONAL_TYPE ||
               ma->base->type == NODE_ERROR_UNION_TYPE) {
        // Base is a type construction/annotation (handles: *T, [N]T, ?T)
        if (ma->symbol && (ma->symbol->kind == SYMBOL_TYPE ||
                           ma->symbol->kind == SYMBOL_UNION_TYPE)) {
            return true;
        }
    }

    // Condition B: The member access resolved to a type at the AST level
    // (handles: @import("mod.zig").Field where Field is a type)
    // This is needed for codegen.cpp:451 to recognize type aliases
    if (ma->base->type == NODE_IMPORT_STMT || ma->base->type == NODE_STRING_LITERAL) {
        if (ma->symbol && (ma->symbol->kind == SYMBOL_TYPE ||
                           ma->symbol->kind == SYMBOL_UNION_TYPE)) {
            return true;
        }
    }

    // Legacy fallback: check resolved_type for aggregate types
    if (node->resolved_type) {
        if (node->resolved_type->kind == TYPE_STRUCT  ||
            node->resolved_type->kind == TYPE_UNION   ||
            node->resolved_type->kind == TYPE_TAGGED_UNION ||
            node->resolved_type->kind == TYPE_ENUM    ||
            node->resolved_type->kind == TYPE_TUPLE) {
            return true;
        }
    }
    return false;
}
```

### Explanation

- **Condition A** (base is type/module identifier): Prevents false positive
  for `tok.kind` where `tok` is a variable. Only matches when the base itself
  is a type name or module. Also handles `const alloc_mod = @import(...)`
  by checking for CONST_VARIABLE with TYPE_MODULE.

- **Condition B** (`@import()` based type aliases): Ensures that
  `const Sand = @import("allocator.zig").Sand;` is recognized as a type
  expression. The `NODE_IMPORT_STMT` check covers direct `@import().Field`,
  and the `NODE_STRING_LITERAL` check covers module paths.

- **Legacy fallback**: The original resolved_type check for struct/enum types.
  Kept for backward compatibility.

## Reproduction

```bash
git checkout src/bootstrap/ast_utils.cpp  # ensure clean state
g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0
./sf/build/zig0 -o sf/build/out.c sf/src/main.zig
```

**Current result:** Assertion crash at `ast_utils.cpp:41` OR "global variable
must have constant initializer" errors (depending on fix attempt).

**Expected result:** Clean compilation, 19+ `.c` files emitted.

## Files Affected

- `src/bootstrap/ast_utils.cpp` — `isTypeExpression()`, `NODE_MEMBER_ACCESS` case
- `src/bootstrap/c89_feature_validator.cpp` — call loop at line 540
- `src/bootstrap/codegen.cpp` — type alias skip at line 451 (indirect via shared isTypeExpression)

## Verification

```bash
# Build test binary
rm -f sf/build/*.c sf/build/*.h
./sf/build/zig0 -o sf/build/out.c sf/src/test_main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Iinclude sf/build/*.c -o sf/build/zig1_test
./sf/build/zig1_test
# Expected: "All lexer tests passed." + "All ast/parser tests passed."
```

## What Was Tried (experimental fixes and results)

All fixes applied to `ast_utils.cpp`'s `isTypeExpression()` and
`type_checker.cpp`'s `registerAliasPlaceholderIfNeeded()`.

### Fix A: Null-guard Z98_ASSERT → if-guard
**File:** `ast_utils.cpp:41`
**Change:** `if (!ma->base->as.identifier.symbol) return false;`
**Result:** Assertion silenced, but all `const X = mod.X` type aliases
rejected by codegen. `isTypeExpression` returns false during both placeholder
registration AND codegen (global symbol table can't find module-local names).
**FAIL**

### Fix B: Use `symbols.lookup(name)` instead of AST pointer
**File:** `ast_utils.cpp:41`
**Change:** Replace `ma->base->as.identifier.symbol` with
`symbols.lookup(ma->base->as.identifier.name)`
**Result:** Same as Fix A. The `symbols` parameter is the GLOBAL table.
Module-level names like `alloc_mod` not found. **FAIL**

### Fix C: Guard registerAliasPlaceholder by AST type
**File:** `type_checker.cpp:916`
**Change:** Only call `isTypeExpression` for `NODE_MEMBER_ACCESS` with
`NODE_IMPORT_STMT` base. Skip `NODE_IDENTIFIER` base patterns.
**Result:** Still fails. codegen.cpp:451 also calls `isTypeExpression` with
global symbol table, can't find `alloc_mod`. **FAIL**

### Root cause of all failures

`isTypeExpression` is called from TWO passes, both with the GLOBAL symbol
table (unit_.getSymbolTable()):

1. **registerAliasPlaceholderIfNeeded** (type_checker.cpp:916) — Phase 2
2. **generateVarDecl** (codegen.cpp:451) — codegen

Module-specific names like `alloc_mod` are NOT in the global table — they
live in each module's local scope. The fix requires passing the module-level
symbol table to `isTypeExpression` from both call sites.

### Fix D: Engineer's fix (dd040ae3)
**File:** `ast_utils.cpp` — multiple changes
**Change:** NULL symbol fallback + warning + expanded CONST_VARIABLE checks
**Result:** Assertion crash fixed (replaced with warning). But `isTypeExpression`
still returns false for `mod.X` patterns when called with global symbol table.
Same 20+ "global variable must have constant initializer" errors persist.
**FAIL** — root cause (wrong symbol table) not addressed.

## Summary for Engineer

The assertion crash is fixed (commit dd040ae3), but the deeper issue remains:

```
codegen.cpp:451  →  isTypeExpression(init, unit_.getSymbolTable())
```

`unit_.getSymbolTable()` returns the GLOBAL symbol table. Module-level
declarations like `alloc_mod` (a `const` module import) are NOT in it.
Two fixes needed:

1. **codegen.cpp:451** — pass the DECLARING MODULE's symbol table:
   `getModule(decl->module_name)->symbols->getTable()`

2. **type_checker.cpp:916** — same fix for `registerAliasPlaceholderIfNeeded`

## Root Cause (per the engineer)

`isTypeExpression` is called with the GLOBAL symbol table
(`unit_.getSymbolTable()`), but the per-module arena strategy (Phase A, commit
`da46cef`) moved each module's symbol table into its OWN arena. Module-level
names like `alloc_mod` no longer exist in the global table — they live in
`mod->symbols` which is per-module arena-allocated.

**Two call sites need per-module symbol tables:**

| Call site | Module source | Fix |
|-----------|--------------|-----|
| `codegen.cpp:451` | `decl->module_name` | `unit_.getSymbolTable(decl->module_name)` |
| `type_checker.cpp:916` | current module context | `unit_.getSymbolTable(unit_.getCurrentModule())` |

`CompilationUnit::getSymbolTable(const char* module_name)` already exists
(compilation_unit.hpp:90) and accepts an optional module name. When called
with a module name, it should return that module's symbol table.
