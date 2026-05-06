# Z98 Test Suite Status Report - Forward (Post-Milestone 11 Deep Dive)

## Summary

| Metric | 32-bit Value | 64-bit Value |
|--------|--------------|--------------|
| Total Test Batches | 82 | 82 |
| Passed Batches | 70 | - |
| Failed Batches | 11 | - |
| Compilation Failed | 1 | - |
| Total Pass Rate | 85.3% | - |

*Note: Results obtained on Linux using a custom bash runner and `g++ -m32`.*

---

## Progress Report (32-bit)

- **Compiler Stability**: **VERIFIED**. `zig0` correctly identifies most memory safety violations.
- **Lifetime Analyzer**: **STALLED**. Deep dive reveals expressions like `&x` fail to resolve symbols in the post-check phase, causing missed `ERR_LIFETIME_VIOLATION` errors.
- **Symbol Table Soundness**: **REGRESSION**. Several batches (7, 12) trigger `Assertion failed: !g_post_check_phase`, indicating unsound lookups after scopes are discarded.
- **Standard Library**: **REGRESSION**. Strict tuple requirements for `std.debug.print` cause failures in older tests (Batches 44, 46, 55).
- **Name Mangling**: **VERIFIED**. Deterministic cross-module symbol hashing is stable.
- **Example Programs**: **VERIFIED**. `rogue_mud`, `mud_server`, `days_in_month`, `lisp_interpreter_curr`, and `mandelbrot` compile and execute correctly under `-m32` and C89 constraints.

---

## Failure Analysis (32-bit)

### 1. Batch 2 (AST/Parser)
- **Status**: **COMPILATION FAILED**
- **Cause**: Issues with the broad automated test runner script and complex test function return types.

### 2. Batch 4 (Lifetime Analyzer)
- **Status**: **FAIL**
- **Test**: `test_lifetime_analyzer_test`
- **Cause**: Missing `ERR_LIFETIME_VIOLATION`. Expressions of type `NODE_UNARY_OP` (address-of) do not have their symbols checked correctly in `isDangerousLocalPointer` during the post-check phase.

### 3. Batch 7, 7_debug, 12 (Symbol Table)
- **Status**: **FAIL**
- **Cause**: `Assertion failed: !g_post_check_phase`. Tests are attempting to use `findInAnyScope` during the post-check phase, which is strictly forbidden to ensure soundness.

### 4. Batch 23 (CVariableAllocator)
- **Status**: **FAIL**
- **Test**: `test_CVariableAllocator_Truncation`
- **Cause**: The test expects identifiers to be truncated at 31 characters. However, the compiler now supports up to 63 characters.
- **Result**: **TEST OUTDATED**.

### 5. Batch 31, 32 (Integration/Call Resolution)
- **Status**: **FAIL**
- **Cause**: `Unresolved call ... Reason: Symbol not found`. Possible issues with module discovery or cross-module visibility in the Linux environment.

### 6. Batch 44, 46, 55 (std.debug.print)
- **Status**: **FAIL**
- **Cause**: `found that these tests already use the .{val} syntax for std.debug.print, but they are failing because the bootstrap compiler explicitly returns TYPE_UNDEFINED when it encounters an anonymous literal in an anytype context (like std.debug.print arguments).

### 7. Batch 66 (Codegen/Slices)
- **Status**: **FAIL**
- **Cause**: Missing slice definitions or typedefs in generated C code for nested pointer usage.

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
| `lisp_interpreter_curr` | PASS | OK | OK | 12 | 14 |
| `game_of_life` | PASS | OK | OK | 0 | 4 |
| `mud_server` | PASS | OK | RUNS | 0 | 18 |
| `rogue_mud` | PASS | OK | RUNS | 0 | 78 |

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
