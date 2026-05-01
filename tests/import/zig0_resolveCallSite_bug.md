# Bug: `resolveCallSite()` doesn't switch module context for cross-module type resolution

## Summary

When module A calls a function from module B whose signature references types
defined in yet other modules (e.g., `Token` from `token.zig`, `Sand` from
`allocator.zig`), `resolveCallSite()` at `type_checker.cpp:7223-7228` calls
`visitFnSignature()` without switching `current_module_` to module B's context.
Types from module C become unresolvable, causing "undeclared type" or segfault.

## Environment

- **Repo root:** `/workspace/znineeight`
- **Commit:** `86b3978` (Merge PR #740 "Fix cross-module type resolution bug")
- **C++ Driver:** `bootstrap_all.cpp` → `g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0`
- **Target file:** `sf/src/main.zig` (16-module compiler with `--dump-tokens` flag)
- **Output:** `./zig0 -o sf/build/zig1.c sf/src/main.zig`

## Reproduction (sf/src compiler)

```bash
cd /workspace/znineeight
g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0
rm -f sf/build/*.c sf/build/*.h
./sf/build/zig0 -o sf/build/zig1.c sf/src/main.zig
```

**Expected:** Clean exit with ALL of the following emitted:
```
sf/build/main.c  sf/build/dump.c  sf/build/lexer.c  sf/build/token.c
sf/build/pal.c  sf/build/allocator.c  sf/build/growable_array.c
sf/build/string_interner.c  sf/build/source_manager.c
sf/build/diagnostics.c  sf/build/name_mangler.c
```
Plus corresponding `.h` files.

**Actual:** Exit code 139 (segfault). 7x `Unresolved call at 11:17 in context
'dumpTokens'` errors emitted. NO `.c`/`.h` files produced (stale output from
previous successful builds may remain in `sf/build/`).

Error message:
```
Unresolved call at 11:17 in context 'dumpTokens' Reason: Forward reference could not be resolved
```

## Import Chain (root cause location)

```
sf/src/main.zig
  └── const dump_mod = @import("dump.zig");          (line 13, WORKS)
  └── const lexer_mod = @import("lexer.zig");         (line 14, WORKS)

sf/src/dump.zig
  ├── const lexerNextToken = @import("lexer.zig").lexerNextToken;  (line 3, FAILS)
  └── fn dumpTokens(lex: *Lexer, interner: *StringInterner) void
        └── var t = lexerNextToken(lex);  (line 13, "Forward reference could not be resolved")

sf/src/lexer.zig
  ├── const Lexer = @import("lexer.zig").Lexer;  (PUB - used as return type)  
  ├── const Token = @import("token.zig").Token;  (PUB - part of return type chain)
  └── const token_mod = @import("token.zig");    (PUB)

sf/src/token.zig
  └── pub const Token = struct {
        pub const TokenKind = enum(u8) { ... };
        pub const TokenValue = union { ... };
      };
```

Line numbers at time of writing:
| File | Line | Code |
|------|------|------|
| `sf/src/dump.zig` | 3 | `const lexerNextToken = @import("lexer.zig").lexerNextToken;` |
| `sf/src/dump.zig` | 10 | `pub fn dumpTokens(lex: *Lexer, interner: *StringInterner) void {` |
| `sf/src/dump.zig` | 13 | `var t = lexerNextToken(lex);` |
| `sf/src/lexer.zig` | 1-15 | (import block) |
| `sf/src/lexer.zig` | 44 | `pub fn lexerNextToken(self: *Lexer) Token {` |
| `sf/src/token.zig` | 106 | `pub const TokenValue = union {` |

## Files Affected (in sf/src/)

ALL files using direct-type-import or direct-function-import patterns trigger
this bug when transitively imported:

| File | Direct Imports | Type Count | Function Count |
|------|---------------|------------|----------------|
| `dump.zig` | `Lexer`, `lexerNextToken`, `StringInterner`, `stringInternerGet`, `TokenKind` | 3 types | 2 functions |
| `test_runner.zig` | `Sand`, `StringInterner`, `Lexer`, `lexerInit`, `lexerNextToken` | 3 types | 2 functions |
| `strip_main.zig` | `NameMangler`, `nameManglerInit` | 1 type | 1 function |
| `parser.zig` | `Token`, `TokenKind`, `AstStore`, `StringInterner`, `DiagnosticCollector` | 5 types | 0 functions |
| `c89_emit.zig` | `TypeRegistry`, `TypeId`, `StringInterner`, `LirFunction`, etc. | 9 types | 0 functions |
| `semantic.zig` | `TypeId`, `TypeRegistry`, `StringInterner`, etc. | 7 types | 0 functions |
| `lower.zig` | `LirFunction`, `LirInst`, `TypeId`, etc. | 11 types | 0 functions |

Note: `test_runner.zig` only WORKS because it is NOT imported by `main.zig`
(direct compilation, not transitive). It's compiled standalone.

## Bug Fix Status (Commit 86b3978)

The fix described below HAS been merged in commit 86b3978. The code at
`type_checker.cpp:7225-7241` now correctly switches `current_module_`:

```cpp
/* Guard 4: Forward Reference / Not resolved yet */  
if (!sym->symbol_type && sym->details) {
    const char* saved_module = unit_.getCurrentModule();
    if (sym->module_name) {
        unit_.setCurrentModule(sym->module_name);
    }
    ...
    unit_.setCurrentModule(saved_module);
}
```

## Still Failing: `sym->module_name` is NULL for imported function symbols

The fix works for module-namespace calls (e.g. `lexer_mod.lexerNextToken(lex)`)
where the Symbol is looked up inside the target module's symbol table.

But when using **direct function imports**:
```zig
const lexerNextToken = @import("lexer.zig").lexerNextToken;
```

The Symbol created in `dump.zig`'s module table for `lexerNextToken` has
`module_name = NULL` because it's a local alias. When `resolveCallSite()` tries
to resolve the function signature, `sym->module_name` is NULL, so the
`setCurrentModule()` call is skipped, and type resolution fails with the same
"Forward reference could not be resolved" error.

**Root cause:** The direct-import mechanism (`@import("mod.zig").fnName`)
creates a Symbol that references the target function but does not set
`module_name`. This Symbol then enters `dump.zig`'s module table. When
`resolveCallSite` encounters it, `module_name` is NULL.

Compare with module-namespace calls:
```zig
const lexer_mod = @import("lexer.zig");
// ...
lexer_mod.lexerNextToken(lex);
```
Here the Symbol for `lexerNextToken` is looked up from `lexer_mod`'s module
symbol table, where it has `module_name` set to `"lexer"`.

## Fix for direct-function-import case

Two distinct issues:

### Issue 1: `sym->module_name` is NULL

When `@import("mod.zig").fnName` resolves, it calls `handleModuleMemberFound`
(line 8555) which resolves the target function and returns its type. The
caller then creates a local `const` alias in the importing module's symbol
table (e.g. `lexerNextToken` in dump.zig's module). This alias has
`module_name = NULL` because `visitVarDecl` sets it:

```cpp
// type_checker.cpp:3729
existing_sym->module_name = is_local ? NULL : unit_.getCurrentModule();
```

Since the alias is in the importing module's scope, `is_local` is false, so
`module_name` gets set to the IMPORTING module's name, not the DEFINING
module. The fix: when the initializer is a member-access into another module
(`NODE_MEMBER_ACCESS` with module base type), propagate the target module's
name:

```cpp
// type_checker.cpp ~3729, in visitVarDecl
if (node->initializer && node->initializer->type == NODE_MEMBER_ACCESS) {
    ASTMemberAccessNode* ma = node->initializer->as.member_access;
    if (ma->base && ma->base->resolved_type &&
        ma->base->resolved_type->kind == TYPE_MODULE) {
        Module* target_mod = (Module*)ma->base->resolved_type->as.module.module_ptr;
        if (target_mod) {
            existing_sym->module_name = target_mod->name;
        }
    }
}
```

### Issue 2: Wrong TypeChecker instance in resolveCallSite

Even when `module_name` is set correctly, `resolveCallSite` (line 7234) calls
`visitFnSignature` on `*this` (the calling module's TypeChecker), while
`handleModuleMemberFound` (line 8623) creates a NEW TypeChecker for the
target module. These are semantically different — a TypeChecker holds mutable
state (symbol table, block structure, etc.) that may have different content
across modules.

Fix:
```cpp
// type_checker.cpp:7232-7234
if (sym->kind == SYMBOL_FUNCTION) {
    const char* saved_module = unit_.getCurrentModule();
    if (sym->module_name) {
        unit_.setCurrentModule(sym->module_name);
    }
    TypeChecker target_checker(unit_);
    ResolvingSignatureGuard guard(target_checker);
    target_checker.visitFnSignature((ASTFnDeclNode*)sym->details);
    unit_.setCurrentModule(saved_module);
}
```

## Workaround

Use module-namespace calls instead of direct function imports:
```zig
// BROKEN:
const lexerNextToken = @import("lexer.zig").lexerNextToken;
// ...
var t = lexerNextToken(lex);

// WORKS:
const lexer_mod = @import("lexer.zig");
// ...
var t = lexer_mod.lexerNextToken(lex);
```

This requires the target file to have a `pub` visibility on all referenced
items.

## Workarounds Tested (all FAIL)

1. **Function-level `@import` inside body** — "undeclared type 'Sand'"
2. **Top-level `const mod = @import(...)`** — "undeclared type" persists
3. **Wrapper module re-exporting** — same error
4. **Bottom-of-file imports** — same error
5. **Top-of-file imports (before struct definition)** — fixes some types but
   module identifier doesn't propagate back to importing file
6. **Direct function import** `const fn = @import("mod.zig").fn;` — same error

## Recent Commits

```
dcac229 Merge pull request #744 — "cross-module-fix-4873876983121201545"
39f0146 Fix cross-module resolution and member access l-value status
86b3978 Merge pull request #740 — "fix-cross-module-type-resolution-13427547564434901852"
0519d3f Merge pull request #741 — "update-docs-cross-module-resolution"
```

The fix in this PR (`dcac229` + `39f0146`) addresses Issue 2 above (wrong
TypeChecker instance in `resolveCallSite`) but does NOT fix Issue 1
(`module_name` propagation for direct-function-import aliases).

## Build Commands (for zig0 maker)

```bash
# 1. Build zig0
g++ -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0

# 2. Reproduce bug (expect sigsegv)
rm -f sf/build/*.c sf/build/*.h
./sf/build/zig0 -o sf/build/zig1.c sf/src/main.zig
echo "Exit: $?"

# 3. If working, compile zig1 and test
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -Iinclude \
    sf/build/*.c -o sf/build/zig1
./sf/build/zig1 --test
```

## Related Docs

- `tests/import/import_deep_dive.md` — describes a different facet (Pass 1/Pass 2
  ordering during forward declarations)
- `nasty_bugs_zig0.md` Bug 5 — cross-module name mangling (unrelated mechanism)
