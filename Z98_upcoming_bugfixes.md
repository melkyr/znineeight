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

### Phase 1: Tagged Union Forward Declaration Bug

- **Issue**: Tagged unions are forward‑declared as `union` instead of `struct` in headers, causing “wrong kind of tag” errors.
- **Fix**: In `C89Emitter::ensureForwardDeclaration`, for tagged unions (both `TYPE_UNION` with `is_tagged` and `TYPE_TAGGED_UNION`), emit `struct` instead of `union`.
- **Verification**:
  - Write a minimal test that uses a tagged union across two modules and compile the generated C.
  - Ensure the header contains `struct U;` (not `union U;`).
  - Verify that the JSON parser no longer needs the manual `struct`‑based tagged union workaround.
- **Effort**: 1 day.

---

### Phase 2: `unreachable` Statement Emission

- **Issue**: `unreachable;` as a statement emits a comment instead of a panic call.
- **Fix**:
  - In `C89Emitter::emitStatement`, add a case for `NODE_UNREACHABLE` (or ensure that `NODE_EXPRESSION_STMT` with an unreachable expression correctly emits `__bootstrap_panic(...);`).
  - The `emitExpression` already handles `NODE_UNREACHABLE` by generating a panic call; we just need to ensure the statement is terminated with a semicolon.
- **Verification**:
  - Write a test function that contains `unreachable;` as a statement.
  - Compile and verify that the generated C contains a call to `__bootstrap_panic`.
- **Effort**: 0.5 day.

---

### Phase 3: Header Dependency Cycle with Error Unions

- **Issue**: When a function returns an error union containing a recursive struct by value, the header emits the error union typedef before the struct definition, causing “incomplete type” errors.
- **Root cause**: Header generation emits all special types (error unions, slices, optionals) immediately, without ensuring that all dependent structs are defined first.
- **Fix**:
  - In `CBackend::generateModule`, after scanning for special types, first emit **all struct/union/enum definitions** (these may depend on each other via pointers, which are fine), **then** emit error unions, slices, and optionals.
  - This mirrors the order already used for `.c` files.
- **Verification**:
  - Create a test with a recursive struct and a function returning `!RecursiveStruct` by value.
  - Inspect the header: the struct definition must appear before the error union typedef.
  - Ensure the JSON parser’s `readFile` (which returns `FileError![]u8`) no longer triggers the cycle.
- **Effort**: 1 day.

---

### Phase 4: Recursive Type Completeness (Slices of Self)

- **Issue**: Types containing slices of themselves (e.g., `Node = struct { children: []Node }`) sometimes fail with “incomplete type” errors during layout calculation.
- **Current status**: Basic recursion already works, but the issue may appear in more complex scenarios (e.g., inside unions, or across modules). We need to ensure that the placeholder system correctly handles slices.
- **Fix**:
  - Audit `visitArrayType` for slices: ensure that it does **not** check completeness of the element type when creating a slice type.
  - In `createSliceType`, do **not** require the element type to be complete.
  - Verify that `isTypeComplete` for `TYPE_SLICE` always returns `true` (already does).
  - Ensure that when a slice is used, any operation that needs the element type (e.g., indexing) calls `resolvePlaceholder` on the element type first.
- **Verification**:
  - Expand existing tests to cover:
    - Struct containing a slice of itself.
    - Two mutually recursive structs each containing a slice of the other.
    - Slice of self inside a union.
    - Cross‑module recursive slices.
  - Run these tests and confirm they compile and run.
- **Effort**: 2 days.

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

### Phase 6: Braceless Switch Prong Semicolon Requirement

- **Issue**: When a switch prong body is a statement (e.g., `return`), a semicolon is required before the comma, which deviates from Zig’s grammar.
- **Fix**: Audit `parseSwitchProng` in the parser. The grammar should allow a statement (which already includes a trailing semicolon) and then a comma. The current code may be expecting a semicolon after the statement even though the statement already provides one. Likely a simple parser adjustment.
- **Verification**:
  - Write a test with a switch where a prong body is `return try foo();` without an extra semicolon.
  - Ensure it parses correctly.
- **Effort**: 0.5 day.

---

### Phase 7: Incomplete Type Definition Order (Structs Referring to Unions)

- **Issue**: Even with pointers, if a struct refers back to a union that is still being defined, header emission order can cause issues.
- **Root cause**: Similar to Phase 3, but with structs referring to unions (or vice‑versa). This should be addressed by the same fix (emit structs first, then unions, then other types). However, if a union contains a pointer to a struct, and that struct is defined later, forward declarations may be needed.
- **Fix**:
  - Ensure that during header generation, we emit forward declarations for all structs/unions before emitting any definitions that reference them.
  - The current `ensureForwardDeclaration` already does this for structs/unions. However, we must ensure it is called for **all** types that will be referenced, including those inside error unions etc.
  - In Phase 3, we already emit struct definitions first. That should solve this issue. After Phase 3, re‑evaluate.
- **Verification**: If any test still fails after Phase 3, investigate and add specific forward declarations.
- **Effort**: 1 day (contingent).

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
