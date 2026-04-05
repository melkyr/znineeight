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
