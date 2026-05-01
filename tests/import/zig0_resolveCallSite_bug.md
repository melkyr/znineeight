# Bug: `resolveCallSite()` doesn't switch module context for cross-module type resolution

## Summary

When module A calls a function from module B whose signature references types
defined in yet other modules (e.g., `Token` from `token.zig`, `Sand` from
`allocator.zig`), `resolveCallSite()` at `type_checker.cpp:7223-7228` calls
`visitFnSignature()` without switching `current_module_` to module B's context.
Types from module C become unresolvable, causing "undeclared type" or segfault.

## Environment

- **Commit:** `86b3978` (Merge PR #740 "Fix cross-module type resolution bug")
- **C++ Driver:** `bootstrap_all.cpp` → `g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0`
- **Target:** `./zig0 -o out/zig1.c sf/src/main.zig` (multi-module compiler)

## Reproduction

```bash
cd /workspace/znineeight
g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0
./sf/build/zig0 -o sf/build/zig1.c sf/src/main.zig
```

**Expected:** Clean exit with `sf/build/main.c`, `sf/build/dump.c`,
`sf/build/lexer.c` etc. produced.

**Actual:** Segfault (exit 139) or "use of undeclared type 'Sand'" / "use of
undeclared type 'Token'" error when emitting C code for modules that import
dump.zig or lexer.zig transitively.

## Minimal Test Case

Create three files:

**modules/a.zig:**
```zig
pub const Foo = struct { x: u32 };
pub fn makeFoo() Foo {
    return Foo{ .x = 42 };
}
```

**modules/b.zig:**
```zig
const a = @import("a.zig");
pub fn useFoo() void {
    var f = a.makeFoo();
    _ = f;
}
```

**main.zig:**
```zig
const b = @import("modules/b.zig");
pub fn main() void {
    b.useFoo();
}
```

Then run:
```bash
./zig0 -o out.c main.zig
```

Expected: `makeFoo()` return type `Foo` (from a.zig) should be resolved when
b.zig calls it transitively through main.zig.

## Root Cause

In `type_checker.cpp:7223-7228`, `resolveCallSite()` defers function signature
resolution:

```cpp
/* Guard 4: Forward Reference / Not resolved yet */
if (!sym->symbol_type && sym->details) {
    if (sym->kind == SYMBOL_FUNCTION) {
        visitFnSignature((ASTFnDeclNode*)sym->details);  // <-- BUG
    } else if (sym->kind == SYMBOL_VARIABLE) {
        visitVarDecl(NULL, (ASTVarDeclNode*)sym->details);  // <-- BUG
    }
}
```

This calls `visitFnSignature()` on `this` (the calling module's TypeChecker).
`visitFnSignature()` uses `current_module_` to look up types referenced in the
signature. Since `current_module_` still points to the **calling** module, types
defined only in the **defining** module's dependency chain are unresolvable.

Compare with the **correct pattern** at `type_checker.cpp:8595-8619`
(`handleModuleMemberFound`), which **does** switch module context:

```cpp
const char* saved_module = unit_.getCurrentModule();
unit_.setCurrentModule(target_mod->name);      // ← switches context
TypeChecker target_checker(unit_);              // ← creates target-scoped checker

if (sym->kind == SYMBOL_FUNCTION) {
    ResolvingSignatureGuard guard(target_checker);
    target_checker.visitFnSignature((ASTFnDeclNode*)sym->details);
}

unit_.setCurrentModule(saved_module);           // ← restores context
```

The `Symbol` struct (`symbol_table.hpp:42`) already stores `module_name`:

```cpp
struct Symbol {
    const char* name;
    const char* module_name; // NULL for local or 'main' module
    ...
};
```

## Suggested Fix

Wrap the deferred-resolution block in `resolveCallSite()` with the same
module-switch pattern used in `handleModuleMemberFound()`:

```cpp
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
```

Note: unlike `handleModuleMemberFound`, this code runs inside the calling
module's TypeChecker (not a new one), so we use `ResolvingSignatureGuard` on
`*this` and only switch the `current_module_` context for type lookup.

## Workarounds Tested (all FAIL)

1. **Function-level `@import` inside body** — "undeclared type 'Sand'"
2. **Top-level `const mod = @import(...)`** — "undeclared type" persists
3. **Wrapper module re-exporting** — same error
4. **Bottom-of-file imports** — same error
5. **Top-of-file imports (before struct definition)** — fixes some types but
   module identifier doesn't propagate back to importing file
6. **Direct function import** `const fn = @import("mod.zig").fn;` — same error

## Related Docs

- `tests/imports/import_deep_dive.md` — describes a different facet (Pass 1/Pass 2
  ordering during forward declarations)
- `nasty_bugs_zig0.md` Bug 5 — cross-module name mangling (unrelated mechanism)
