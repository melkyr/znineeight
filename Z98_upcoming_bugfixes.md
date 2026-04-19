# Z98 Upcoming Bugfixes & Investigations

## Investigation: Aggregate Initializer Lifting in Expression Contexts

### Problem Description
Currently, the Z98 compiler emits C99-style compound literals (e.g., `(struct S){.x = 1}`) or braced initializers (e.g., `{.tag = ...}`) directly at the call site when an aggregate (struct, union, tagged union, or array) is passed as a function argument. Standard C89 does not support compound literals or braced initializers in expression contexts; they are only permitted in variable declarations.

### Minimal Reproduction
The following Zig code demonstrates the issue:

```zig
const MyType = union(enum) {
    A: i32,
    B: f32,
};

const MyStruct = struct {
    x: i32,
    y: i32,
};

fn takeTaggedUnion(u: MyType) void { _ = u; }
fn takeStruct(s: MyStruct) void { _ = s; }

pub fn main() void {
    // Both of these currently emit invalid C89
    takeTaggedUnion(.{ .A = 42 });
    takeStruct(.{ .x = 1, .y = 2 });
}
```

### Observed Output (Invalid C89)
The `C89Emitter` generates the following call sites:

```c
int main(void) {
    zF_b3368a_takeTaggedUnion({.tag = zE_8aa302_MyType_Tag_A, .data = {.A = 42}});
    zF_b3368a_takeStruct({1, 2});
    return 0;
}
```

Legacy compilers like MSVC 6.0 will reject this syntax with "error C2059: syntax error : '{'".

### Proposed Fix Strategy

The fix involves extending the `ControlFlowLifter` pass to treat aggregate initializers as "lifting candidates" when they appear in expression contexts that are not direct assignments or variable initializers.

#### 1. Identification of Lifting Candidates
Update `isControlFlowExpr` in `src/include/ast_utils.hpp` or create a new `isLiftingCandidate` helper to include aggregate literals:

```cpp
inline bool isLiftingCandidate(NodeType type) {
    return isControlFlowExpr(type) ||
           type == NODE_STRUCT_INITIALIZER ||
           type == NODE_TUPLE_LITERAL;
}
```

#### 2. Update `ControlFlowLifter`
Modify `ControlFlowLifter::needsLifting` and `ControlFlowLifter::transformNode` to recognize these nodes. When an aggregate initializer is found in an "unsafe" context (like a function call argument), the lifter should:
1.  Generate a unique temporary name (e.g., `__tmp_agg_1`).
2.  Create a `NODE_VAR_DECL` for the temporary, using the aggregate initializer as the init expression.
3.  Insert the declaration before the current statement.
4.  Replace the initializer in the expression with an identifier referencing the temporary.

#### 3. Leverage Existing Emitter Logic
The `C89Emitter` already contains robust logic for "lifting" initializers in `emitLocalVarDecl` and `emitAssignmentWithLifting`. By lifting the aggregate to a temporary variable at the AST level, we ensure that:
-   The emitter sees a simple `NODE_VAR_DECL`.
-   `emitLocalVarDecl` will trigger `emitAssignmentWithLifting`.
-   `emitAssignmentWithLifting` will correctly decompose the initializer into field-by-field assignments (e.g., `tmp.x = 1; tmp.y = 2;`), which is perfectly valid C89.

### Impact on Emitter
This change allows `C89Emitter::emitExpression` to be simplified. It can eventually report an internal error if it encounters a `NODE_STRUCT_INITIALIZER` or `NODE_TUPLE_LITERAL`, as the lifter should have already removed them from expression contexts.

### Estimated Effort
-   **Effort**: Low (1-2 hours)
-   **Risk**: Low (Relies on proven lifting infrastructure)
-   **Verification**: Batch 76 (to be created) should verify that all aggregate initializers in function arguments are lifted and decomposed.

---

## Investigation: Tagged Union Coercion in Expressions

### Problem Description
The Z98 bootstrap compiler does not currently support implicit coercion from an enum tag literal (e.g., `.Alive`) or a qualified enum member (e.g., `Cell.Alive`) to its corresponding tagged union type when used within branches of control-flow expressions like `if` or `switch`.

### Minimal Reproduction
```zig
const Cell = union(enum) {
    Alive: void,
    Dead: void,
};

pub fn main() void {
    var cond: bool = true;
    // This currently fails or causes an internal compiler error
    var next_state: Cell = if (cond) .Alive else .Dead;
    _ = next_state;
}
```

### Observed Behavior
The `TypeChecker` currently resolves naked tags (`.Alive`) to `TYPE_UNDEFINED` during the initial visitation of `if` expression branches. When both branches are `TYPE_UNDEFINED`, the unification logic in `visitIfExpr` fails to determine a common result type, even if the parent assignment provides a clear `expected_type`.

### Root Cause Analysis
1.  **Naked Tag Resolution**: In `visitMemberAccess`, tags with no base (naked tags) are explicitly returned as `get_g_type_undefined()`.
2.  **Unification Failure**: `visitIfExpr` and `validateSwitch` rely on `areTypesCompatible` or `areTypesEqual` to find a common type between branches. If branches are `TYPE_UNDEFINED`, they cannot be unified to a specific tagged union unless that union is already the `expected_type` and distributive coercion is applied.
3.  **Distributive Coercion Interaction**: While `coerceNode` has logic to transform tags into unions, it is often called after the initial visitation has already failed or returned an ambiguous type.

### Proposed Fix Strategy

The goal is to allow the `TypeChecker` to recognize that a tag literal is a "potential" tagged union value during the unification phase.

#### 1. Improve Tag Literal Typing
Modify `visitMemberAccess` to return a specialized sentinel type (e.g., `TYPE_TAG_LITERAL`) for naked tags, or ensure they carry the field name for later resolution.

#### 2. Enhance Unification Logic
Update `areTypesCompatible` to recognize that:
-   A tag literal is compatible with a tagged union if the union has a matching `void` variant.
-   Two tag literals are compatible with each other if they belong to the same expected tagged union type.

#### 3. Proactive Coercion in Control-Flow
Update `visitIfExpr` and `validateSwitch` to check if branches are tag literals. If an `expected_type` (which is a tagged union) is available, proactively call `coerceNode` on the branches *before* final unification. This will transform `.Alive` into a synthetic `Cell{ .Alive = {} }` AST node, which already has proven support in the emitter.

### Estimated Effort
-   **Effort**: Medium (3-5 hours)
-   **Risk**: Medium (Requires careful changes to type unification and compatibility rules)
-   **Verification**: Add tests for `if` and `switch` expressions returning both qualified and unqualified tags.

---
[Previous content of Z98_upcoming_bugfixes.md continues here...]
## Issue 4: Loop State & Capture Sensitivity

**Effort:** Low to Medium (2-4 hours) – this is a compiler bug that may affect some complex loops.

**Plan:**

1. **Create a minimal repro** that isolates the problem. For example, a loop that captures a tagged union payload and uses it across iterations.

2. **Analyze the generated C code** for the loop. Look for:
   - Temporaries declared outside the loop (should be inside).
   - Payload captures being reused incorrectly.
   - Missing `break` or `continue` labels.

3. **Fix the `ControlFlowLifter`** to ensure that temporaries for `switch` captures inside loops are declared **inside the loop body**, not outside. The lifter already inserts temporaries at the position of the node; if the node is inside a loop, the temporary should be inside the loop’s block. Verify that the lifter correctly handles this.

4. **If the issue is specific to the Lisp interpreter**, you can restructure the interpreter’s code to avoid the problematic pattern (e.g., move the loop body into a separate function). That is a workaround.

**Assessment:** This issue is rare and not a blocker for self‑hosting. Most compiler loops are simple (AST traversal) and do not involve complex captures. You can safely defer it.


# Master Plan for C89/C++98 Compatibility

This plan addresses all issues identified in the compatibility report, ensuring the Z98 bootstrap compiler (`zig0`) can be built with legacy C++98 compilers (MSVC 6.0, OpenWatcom) and that the generated C code is C89‑compliant and runs on Windows 98 / MSVC 6.0.

The plan is divided into **phases**. Each phase is self‑contained and can be implemented incrementally.

---

## Phase 0: Preprocessor Compatibility Layer

**Goal:** Create a single header that abstracts compiler and target differences.

**File:** `src/include/compat.hpp` (new)

```cpp
#ifndef ZIG_COMPAT_HPP
#define ZIG_COMPAT_HPP

// Detect compilers
#ifdef _MSC_VER
    #define ZIG_COMPILER_MSVC
    #if _MSC_VER == 1200 // MSVC 6.0
        #define ZIG_COMPILER_MSVC6
    #endif
#elif defined(__WATCOMC__)
    #define ZIG_COMPILER_OPENWATCOM
#endif

// inline keyword
#ifdef ZIG_COMPILER_MSVC
    #define ZIG_INLINE __inline
#else
    #define ZIG_INLINE inline
#endif

// 64-bit integer suffix for literals in generated C
#ifdef ZIG_COMPILER_MSVC
    #define ZIG_I64_SUFFIX "i64"
    #define ZIG_UI64_SUFFIX "ui64"
#else
    #define ZIG_I64_SUFFIX "LL"
    #define ZIG_UI64_SUFFIX "ULL"
#endif

// Unused parameter/variable macro (already exists in utils.hpp)
#ifndef RETR_UNUSED
    #define RETR_UNUSED(x) (void)(x)
#endif

// Boolean type for C89 (generated code)
#ifndef ZIG_BOOL_DEFINED
    #define ZIG_BOOL_DEFINED
    typedef int bool;
    #define true 1
    #define false 0
#endif

#endif // ZIG_COMPAT_HPP
```

**Action:** Create `compat.hpp` and include it in `common.hpp` and `codegen.hpp`.

---

## Phase 1: Fix C++98 Non‑Compliant Issues (Compiler Source)

### 1.1 Replace `unsigned long long` casts with `u64`

**File:** `src/bootstrap/type_checker.cpp` (line ~6830)

```cpp
// Before
(unsigned long long)node->as.integer_literal.value

// After
(u64)node->as.integer_literal.value
```

**Also** search for any other `long long` or `unsigned long long` usage in the compiler source and replace with `i64`/`u64` (defined in `common.hpp`).

### 1.2 Ensure `<cstddef>` / `<stdint.h>` not used directly

`common.hpp` already provides fallbacks. Verify that no file includes `<stdint.h>` or `<cstdint>` unconditionally. If found, replace with `#include "common.hpp"`.

### 1.3 Apply `RETR_UNUSED` consistently

Run a quick scan for functions with unused parameters. Use the macro to silence warnings:

```cpp
void myFunc(int a, int b) {
    RETR_UNUSED(b);
    // use a only
}
```

**Action:** Add `RETR_UNUSED` in `type_checker.cpp`, `parser.cpp`, `codegen.cpp` where needed.

---

## Phase 2: Fix C89 Compliance Issues (Generated Code)

### 2.1 Remove `long long` from Runtime Headers

**File:** `src/include/zig_runtime.h`

Replace:

```c
#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
#else
    typedef long long i64;
    typedef unsigned long long u64;
#endif
```

with:

```c
#include "zig_compat.h"  // (new header for generated C)
```

`zig_compat.h` (to be copied to output directory) will contain:

```c
#ifndef ZIG_COMPAT_H
#define ZIG_COMPAT_H

#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
#elif defined(__WATCOMC__)
    typedef long long i64;    // OpenWatcom supports long long as extension
    typedef unsigned long long u64;
#else
    typedef long long i64;
    typedef unsigned long long u64;
#endif

typedef int bool;
#define true 1
#define false 0

#endif
```

**Action:** Modify `CBackend::copyRuntimeFiles` to also copy `zig_compat.h` to the output directory.

### 2.2 Function Pointer to `void*` Conversion

**Issue:** The Lisp interpreter stores builtins as `void*` and casts back. This triggers a pedantic warning. For the compiler’s own generated code, we can suppress the warning or change the runtime.

**Short‑term fix:** In `C89Emitter::emitExpression` for builtin calls, emit a cast to the correct function pointer type instead of `void*`. However, the builtin is stored in a `void*` field. The warning is harmless. For true compliance, we would need to change the interpreter’s `Value` union to store a function pointer. This is outside the compiler’s scope. **Accept the warning** or add `#pragma` to disable it in MSVC.

**Long‑term fix:** Update the interpreter (separate task) to use a tagged union with a function pointer type.

### 2.3 Signedness Mismatch in `__bootstrap_print`

**Files:** `src/include/zig_runtime.h`, `src/runtime/zig_runtime.c`

Change prototype:

```c
void __bootstrap_print(const char* s);
```

In `zig_runtime.c`, cast to `unsigned char*` internally:

```c
void __bootstrap_print(const char* s) {
    const unsigned char* us = (const unsigned char*)s;
    while (*us) {
        putchar(*us++);
    }
}
```

**Action:** Update both files.

### 2.4 Unused Continue Labels in Loops

**Files:** `src/bootstrap/codegen.cpp` (`emitFor`, `emitWhile`, `emitBreak`, `emitContinue`)

**Solution:** Add a flag `has_continue` to the loop context. Set it when `emitContinue` is called. Only emit the continue label if the flag is true.

**Implementation sketch:**

```cpp
// In C89Emitter class, add a stack of bools for loops
DynamicArray<bool> loop_has_continue_;

// In emitFor/emitWhile, before emitting body:
loop_has_continue_.append(false);

// ... emit body ...

// After body, if loop_has_continue_.back() is true, emit the continue label.
if (loop_has_continue_.back()) {
    writeIndent();
    writeString(cont_label);
    writeString(": ;\n");
}
loop_has_continue_.pop_back();

// In emitContinue, set the flag for the current loop:
if (loop_id_stack_.length() > 0) {
    loop_has_continue_[loop_id_stack_.length() - 1] = true;
}
```

**Action:** Implement this tracking.

---

## Phase 3: MSVC 6.0 / OpenWatcom Specifics

### 3.1 64‑bit Literal Suffixes

Already handled in `C89Emitter::emitIntegerLiteral`. Verify that for MSVC, suffixes are `i64`/`ui64`. For OpenWatcom, `LL`/`ULL` work.

### 3.2 Identifier Length Limit

The `NameMangler` already truncates to 31 characters and uses hashing. For external symbols, some linkers may only distinguish 6 characters. We currently use a 6‑character hash. This is sufficient.

**Action:** No change.

### 3.3 `inline` Keyword

In generated C, we should not use `inline` because C89 doesn’t have it. Instead, define a macro `ZIG_INLINE` that expands to empty for strict C89. For MSVC, use `__inline`.

**File:** `src/include/zig_compat.h` (in generated output)

```c
#ifdef _MSC_VER
    #define ZIG_INLINE __inline
#else
    #define ZIG_INLINE
#endif
```

**Action:** Update `C89Emitter::emitPrologue` to emit this macro definition, and replace any `static inline` with `static ZIG_INLINE` in generated code.

### 3.4 Mixed Declarations and Code

**Issue:** The compiler already uses a two‑pass approach for blocks, but temporaries created during expression lifting (e.g., in `if` conditions) may be declared after some code.

**Audit:** In `emitIf`, the temporary for the condition is declared before the condition evaluation. That is correct. In `emitWhile`, the temporary for the optional capture is declared before the loop. That is also correct.

**Potential problem:** When lifting a complex expression inside a block, the lifter inserts the temporary declaration at the position of the expression, which may be after some statements. To fix, we would need to hoist all temporaries to the top of the block. This is complex and not required for the current test suite.

**Action:** Document this as a known limitation. For now, the generated code works with MSVC 6.0 and OpenWatcom because they are lenient.

### 3.5 Boolean Type

We already define `bool` as `int`. Ensure no conflict with system headers by guarding with `#ifndef __cplusplus`.

**Action:** In `zig_compat.h`, add:

```c
#ifndef __cplusplus
    typedef int bool;
    #define true 1
    #define false 0
#endif
```

---

## Phase 4: Create and Distribute `zig_compat.h`

**Action:** Add a new file `src/include/zig_compat.h` (for runtime) and modify `CBackend::generateSpecialTypesHeader` to emit a similar header for every module. Alternatively, copy `zig_compat.h` to the output directory once. The runtime already uses `zig_runtime.h`; we can include `zig_compat.h` there.

**Simpler:** Add the compatibility macros directly in `zig_runtime.h` (guarded). That avoids an extra file.

---

## Phase 5: Testing and Validation

After each phase, compile `zig0` with MSVC 6.0 (or a modern compiler with `-std=c++98 -pedantic`) and run the test suite. For generated C, compile with `gcc -std=c89 -pedantic -Werror` and with MSVC 6.0 (if available) to verify no warnings/errors.

**Priority order:**

1. Phase 0 + Phase 1 (fix compiler source) – enables building zig0 on legacy C++98 compilers.
2. Phase 2.1 + 2.3 + 2.4 (fix common C89 issues) – reduces warnings in generated code.
3. Phase 3.3 + 3.5 – improves portability.
4. Phase 2.2 (function pointer cast) – low priority, can be deferred.
