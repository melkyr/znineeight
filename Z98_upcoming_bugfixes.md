## Phased Plan to Resolve JSON Parser Issues

The following phased plan prioritises critical code generation bugs and type system gaps that currently prevent the JSON parser from compiling without workarounds. Each phase is self‑contained and should be verified with integration tests.

---

### Phase 0: Baseline & ABI Documentation

- **Goal**: Establish a clear understanding of the target platform.
- **Actions**:
  1. Add a prominent note to `README.md` and `docs/design/COMPATIBILITY.md` that the compiler is hardcoded for **32‑bit** targets (pointers 4 bytes, `size_t` 4 bytes, slice struct 8 bytes).
  2. Instruct users to compile generated C with `-m32` (or use a 32‑bit C compiler).
  3. (Optional) Add a compile‑time check in `zig0` that detects if the host is 64‑bit and prints a warning: “Generated C must be compiled with -m32”.
- **Outcome**: Users are aware of the 32‑bit requirement, avoiding runtime corruption.

---

### Phase 1: Tagged Union Forward Declaration Bug [RESOLVED]

- **Issue**: Tagged unions are forward‑declared as `union` instead of `struct` in headers, causing “wrong kind of tag” errors.
- **Fix**: Implemented centralized `C89Emitter::ensureForwardDeclaration`. For tagged unions (both `TYPE_UNION` with `is_tagged` and `TYPE_TAGGED_UNION`), it correctly emits `struct` instead of `union`.
- **Verification**:
  - New test case `Phase1_TaggedUnion_ForwardDecl` in `tests/integration/phase1_tagged_union_verification.cpp` verifies correct keyword usage.
  - Header files now use `struct` for tagged union forward declarations.

---

### Phase 2: `unreachable` Statement Emission [RESOLVED]

- **Issue**: `unreachable;` as a statement emits a comment instead of a panic call.
- **Fix**:
  - Integrated `NODE_UNREACHABLE` into the `ControlFlowLifter` to ensure correct behavior when used as an expression (e.g., in `if` expressions).
  - Enhanced `allPathsExit` to correctly identify `NODE_UNREACHABLE` and `NODE_VAR_DECL` with diverging initializers, enabling proper dead code elimination in the emitter.
  - Implemented minimal `errdefer` support in `C89Emitter` to ensure that `unreachable` statements inside `errdefer` are not lost.
  - Unified `unreachable` emission to always produce a `__bootstrap_panic` call.
- **Verification**:
  - New test batch `Batch 70` (`tests/integration/unreachable_tests.cpp`) verifies standalone statements, variable initializers, `defer`/`errdefer` blocks, and divergent `if` expressions.
- **Outcome**: `unreachable` now consistently triggers a panic at runtime and enables better compile-time dead code elimination in generated C.

---

### Phase 3: Header Dependency Cycle with Error Unions [RESOLVED]

- **Issue**: When a function returns an error union containing a recursive struct by value, the header emits the error union typedef before the struct definition, causing “incomplete type” errors.
- **Root cause**: Header generation emitted all special types (error unions, slices, optionals) immediately at the top of the file, without ensuring that all dependent structs were defined first.
- **Fix**:
  - In `CBackend::generateHeaderFile`, the early scanning and emission of special types was removed.
  - Emission of special types is now handled lazily during the main type definition loop and subsequent prototype/global emission.
  - `emitter.emitBufferedTypeDefinitions()` is called after each named type definition to ensure any special types it depends on (like slices of itself) are emitted immediately after the struct is defined.
- **Verification**:
  - Created an integration test `Phase3_ErrorUnionRecursion` in `tests/integration/phase3_error_union_recursion.cpp`.
  - Verified that `struct Node` is defined before `ErrorUnion_Node` in the generated header.
  - Confirmed the fix with `gcc -std=c89 -pedantic`.
- **Outcome**: Special types now correctly follow the topological order of the named types they depend on in headers.

---

### Phase 4: Recursive Type Completeness (Slices of Self) [RESOLVED]

- **Issue**: Types containing slices of themselves (e.g., `Node = struct { children: []Node }`) sometimes fail with “incomplete type” errors during layout calculation.
- **Fix**:
  - Confirmed that `isTypeComplete` already returns `true` for `TYPE_SLICE` (since size/align are fixed 8/4).
  - Audited `visitArrayType` and `createSliceType` to ensure element completeness is NOT required during slice creation.
  - Hardened `TypeChecker` to aggressively resolve placeholders during all slice-related operations:
    - Indexing (`visitArrayAccess`)
    - Iteration (`visitForStmt`)
    - Member access (`visitMemberAccess` for `.ptr`)
    - Compatibility and Coercion (`areTypesCompatible`, `coerceNode`, `needsStringLiteralCoercion`)
- **Verification**:
  - Expanded `Batch 50` (`tests/integration/recursive_slice_tests.cpp`) to cover:
    - Struct containing a slice of itself.
    - Mutually recursive structs via slices.
    - Slice of self inside a tagged union.
    - Cross-module recursive slices (mutually recursive modules).
  - All tests pass and verify that placeholders are correctly resolved on-demand.
- **Outcome**: Recursive slices are now robust across single-module, multi-module, and union contexts.

---

### Phase 5: Strict Assignment Compatibility (i32 → usize Coercion)

- **Issue**: Integer literals (`0`) do not implicitly coerce to `usize` in assignments or struct initializers.
- **Fix**:
  - In `TypeChecker::canLiteralFitInType`, add cases for `TYPE_USIZE` and `TYPE_ISIZE` that check the value against 32‑bit range.
  - In `IsTypeAssignableTo`, allow integer literals to coerce to `usize`/`isize` if the value fits.
- **Verification**:
  - Write a test that assigns `0` to a `usize` variable and uses it in a struct initializer.
  - Ensure no type mismatch error occurs.
- **Effort**: 0.5 day.

---

### Phase 6: Braceless Switch Prong Semicolon Requirement [RESOLVED]

- **Issue**: When a switch prong body is a statement (e.g., `return`), a semicolon is required before the comma, which deviates from Zig’s grammar.
- **Fix**: Refactored switch prong parsing into `Parser::parseSwitchProng`. Prong bodies are now parsed as expressions using `parseExpression()`, which naturally handles `return`, `break`, and `continue` without requiring a semicolon. Implemented Zig-style comma rules: comma is required after non-block expressions (unless it's the last prong) and optional after blocks.
- **Verification**:
  - New test batch `Batch 72` (`tests/integration/switch_prong_tests.cpp`) verifies:
    - `return 1,` without semicolon.
    - Optional comma after blocks.
    - Required comma for non-last expression prongs.
    - Rejection of variable declarations in prongs (requiring blocks instead).
- **Outcome**: Switch prong syntax now fully aligns with Zig's grammar.

---

### Phase 7: Incomplete Type Definition Order (Structs Referring to Unions) [RESOLVED]

- **Issue**: Even with pointers, if a struct refers back to a union that is still being defined, header emission order can cause issues.
- **Root cause**: Similar to Phase 3, but with structs referring to unions (or vice‑versa). Mutual recursion via pointers was previously blocked by strict TypeChecker completeness checks.
- **Fix**:
  - Relaxed `TypeChecker` to allow incomplete types in fields if they are reached through a pointer indirection.
  - Implemented explicit value-dependency cycle detection in the `TypeChecker`.
  - Enhanced `MetadataPreparationPass` to perform a two-phase traversal: value dependencies are visited first to establish a topological definition order, while pointer/function dependencies are found for forward declarations.
  - Updated `CBackend` to emit forward declarations for all aggregate types defined in the module at the top of the header.
- **Verification**:
  - Created Batch 73 (`tests/integration/phase7_tests.cpp`) verifying valid pointer recursion, invalid value cycles, and correct topological ordering for both structs and tagged unions.
  - Verified full test suite passes.
- **Outcome**: Mutually recursive types via pointers are now fully supported and correctly emitted in C89 headers.

---

### Phase 8: Documentation and Release

- **Goal**: Update all relevant documentation to reflect the fixes and the 32‑bit requirement.
- **Actions**:
  - Update `docs/design/C89_Codegen.md` with details on tagged union emission, `unreachable` handling, and header order.
  - Update `docs/design/Bootstrap_type_system_and_semantics.md` with notes on recursive slices and integer literal coercions.
  - Update `README.md` with the 32‑bit requirement and how to use `-m32`.
  - Update `Z98_upcoming_bugfixes.md` to mark these issues as resolved.
- **Outcome**: Comprehensive documentation for future developers.

---

## Summary of Phases

| Phase | Description | Effort |
|-------|-------------|--------|
| 0 | 32‑bit ABI documentation | 0.5 day |
| 1 | Tagged union forward declaration | 1 day |
| 2 | `unreachable` emission | 0.5 day |
| 3 | Error union header order | 1 day |
| 4 | Recursive slice completeness | 2 days |
| 5 | i32 → usize coercion | 0.5 day |
| 6 | Braceless switch semicolon | 0.5 day |
| 7 | Incomplete type order (contingent) | 1 day |
| 8 | Documentation | 1 day |

**Total** ≈ 7–8 days of focused work.

After completing these phases, the JSON parser should compile without any of the workarounds listed, and the compiler will be robust enough to tackle `zig1`. Each phase can be implemented and tested independently, and the fixes are isolated.
