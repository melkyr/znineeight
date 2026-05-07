# Z98 Test Suite Status Report - Forward (Post-Milestone 11 Deep Dive)

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 81 | 81 |
| Passed Batches | 73 | - |
| Failed Batches | 8 | - |
| Compilation Failed | 1 | - |
| Total Pass Rate | 90.1% | - |

*Note: Results obtained on Linux using a custom bash runner and `g++ -m32`.*

---

## Progress Report (32-bit)

- **Compiler Stability**: **VERIFIED**. `zig0` correctly identifies most memory safety violations.
- **Lifetime Analyzer**: **STALLED**. Deep dive reveals expressions like `&x` fail to resolve symbols in the post-check phase, causing missed `ERR_LIFETIME_VIOLATION` errors.
- **Symbol Table Soundness**: **VERIFIED**. Recent hardening of `SymbolTable::findInAnyScope` ensures soundness during the post-check phase. Previous regressions in Batches 7 and 12 have been resolved.
- **Standard Library**: **REGRESSION**. Strict tuple requirements for `std.debug.print` cause failures in older tests (Batches 44, 46, 55).
- **Name Mangling**: **VERIFIED**. Deterministic cross-module symbol hashing is stable.
- **Example Programs**: **REGRESSION**. `rogue_mud` and `lisp_interpreter_curr` currently fail to compile with `zig0`. `mud_server`, `days_in_month`, `func_ptr_return`, and `mandelbrot` remain verified.

---

## Failure Analysis (32-bit)

### 1. Batch 2 (AST/Parser)
- **Status**: **COMPILATION FAILED**
- **Cause**: Parser constructor mismatch in `test_parser_lifecycle.cpp` due to recent Phase B memory optimizations (splitting arena into ast_arena and perm_arena).

### 2. Batch 4 (Lifetime Analyzer)
- **Status**: **FAIL**
- **Test**: `test_lifetime_analyzer_test`
- **Cause**: Missing `ERR_LIFETIME_VIOLATION`. System functions like `malloc` and `calloc` are undeclared in the test context, causing earlier failures.

### 3. Batch 31, 32 (Integration/Call Resolution)
- **Status**: **FAIL**
- **Cause**: Cross-module type inference and call resolution failures. Symbols from imported modules are not being found or their types cannot be inferred.

### 4. Batch 44, 46, 55 (std.debug.print / try-catch)
- **Status**: **FAIL**
- **Cause**: `std.debug.print` fails because the bootstrap compiler returns `TYPE_UNDEFINED` for anonymous literals in `anytype` contexts. Integration tests for `try-catch` and `try-return` also show type mismatches.

### 5. Batch 66 (Codegen/Slices)
- **Status**: **FAIL**
- **Cause**: Missing slice definitions (`Slice_u8`, `Slice_i32`) in generated C code for nested pointer usage.

---


## Examples Status (32-bit)

| Example | Status | Compilation | Correctness | C89 Warnings | Zig0 Warnings |
|---------|--------|-------------|-------------|--------------|---------------|
| `hello` | PASS | OK | OK | 0 | 2 |
| `prime` | PASS | OK | OK | 0 | 1 |
| `days_in_month` | PASS | OK | OK | 0 | 1 |
| `fibonacci` | PASS | OK | OK | 0 | 1 |
| `heapsort` | PASS | OK | OK | 6 | 21 |
| `quicksort` | PASS | OK | OK | 0 | 11 |
| `sort_strings` | PASS | OK | OK | 0 | 14 |
| `func_ptr_return`| PASS | OK | OK | 0 | 0 |
| `lzw` | PASS | OK | OK | 0 | 13 |
| `mandelbrot` | PASS | OK | OK | 0 | 5 |
| `lisp_interpreter_curr` | FAIL | CRASH | - | - | - |
| `game_of_life` | PASS | OK | OK | 0 | 4 |
| `mud_server` | PASS | OK | RUNS | 0 | 18 |
| `rogue_mud` | FAIL | ERROR | - | - | - |

---

## Stage 1 (sf/) Deep Dive Findings

### 1. The Transitive Alias Blockade
The primary failure in `sf/src/lexer.zig` is the resolution of transitive type aliases:
```zig
const ga_mod = @import("growable_array.zig");
const U8ArrayList = ga_mod.U8ArrayList; // Placeholder created here
...
string_buf: *U8ArrayList, // ERROR: use of undeclared type 'U8ArrayList'
```

**Anatomy of the Failure**:
1. **Phase 0 (Registration)**: `U8ArrayList` is correctly identified as a module member alias and a `TYPE_PLACEHOLDER` is registered in `lexer.zig`'s scope.
2. **Phase 0.5 (Fixed-Point Resolution)**: `CompilationUnit` attempts to resolve the placeholder via `TypeChecker::resolveNamedPlaceholder`.
3. **Phase 0.7 (Flattening)**: `flattenTransitiveAliases` attempts to unwrap the chain.
4. **The Stalling Mechanism**: In large projects like `sf/`, the `base` of the member access (`ga_mod`) is often another placeholder. If `ga_mod` is not fully "baked" (i.e., its AST not fully parsed or its own placeholders not resolved), the resolution of `ga_mod.U8ArrayList` returns `TYPE_UNDEFINED`.
5. **The Regression**: Recent instrumentation shows that while `ga_mod` resolves to a `TYPE_MODULE`, the subsequent `visitMemberAccess` for `U8ArrayList` within that module fails because the `TypeRegistry` for `growable_array.zig` hasn't been populated with the concrete `U8ArrayList` struct yet, or the cross-module lookup is desyncing.

### 2. Local Symbol "Latent Loss"
In `sf/src/allocator.zig`, local variables like `aligned` are reported as undeclared.
- **Root Cause**: `TypeChecker::visitVarDecl` for local variables with inferred types. If the initializer contains a complex expression that triggers a multi-pass stall (e.g. bitwise ops on casts), the visitor returns `TYPE_UNDEFINED` early.
- **Consequence**: The symbol is never inserted into the current scope's symbol table. Subsequent lines in the same block fail to find the identifier.
- **Verification**: This was confirmed by adding `[TYPE] visitVarDecl ... EARLY RETURN` logs.

---

## Compiler Deep Dive Findings (Milestone 11)

### 1. Lifetime Analyzer Blindness
The `LifetimeAnalyzer` relies on `getPointerProvenance` to resolve names, but `isDangerousLocalPointer` fails to lookup the corresponding `Symbol` in the post-check phase for any node that isn't a direct `NODE_IDENTIFIER`. This prevents detection of returning addresses of locals (e.g., `return &x`).

### 2. Post-Check Phase Assertions
The hardening of `SymbolTable::findInAnyScope` with `Z98_ASSERT(!g_post_check_phase)` has exposed several places in the test suite and potentially the compiler where lookups are still being performed after lexical scopes are discarded. While this ensures soundness, it requires updating existing tests or analysis paths.

---

## Compiler Instrumentation (Added)

The following debug logs have been permanently added to `src/bootstrap/type_checker.cpp` to aid in further Stage 1 debugging (enabled via `-DZ98_ENABLE_DEBUG_LOGS`):

- `[PH] Found module member alias '...'`: Traces the registration of module member placeholders during Phase 0.
- `[PH] resolveNamedPlaceholder '...'`: Traces the attempts to resolve these placeholders during Phase 0.5.
- `[TYPE] visitTypeName failed for '...'`: pinpoints exactly which type lookups are failing and in which module context.
- `[TYPE] visitVarDecl '...' EARLY RETURN`: Traces local symbol insertion failures due to unresolved initializers.

---

## Next Steps for Stage 1

1. **Phase 0.5 Hardening**: Modify `resolveNamedPlaceholder` to be more aggressive. If the base of a member access is a placeholder, it should force its resolution recursively rather than waiting for the next iteration of the fixed-point loop.
2. **Registry Force-Sync**: Ensure that `TypeRegistry::insert` for structs/enums happens as early as possible in Phase 1, even before the body is checked, to allow other modules to "see" the type's existence.
3. **Local Symbol Pre-insertion**: Ensure `visitVarDecl` always inserts the symbol into the table *before* visiting the initializer, even if the type is initially `TYPE_UNDEFINED`.
