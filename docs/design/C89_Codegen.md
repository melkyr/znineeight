> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# C89 Code Generation Infrastructure

This document describes the infrastructure used by the Z98 compiler to generate C89-compliant source code.

## 1. CBackend Class

The `CBackend` is the orchestration layer for code generation. It manages the creation of multiple C source and header files, one for each Zig module.

### Responsibilities:
- **Module Iteration**: Iterates over all compiled modules in a `CompilationUnit`.
- **File Management**: Creates `.c` and `.h` files for each module.
- **Metadata-Driven Emission**: Leverages the `MetadataPreparationPass` to emit headers that are guaranteed to be self-contained and free of "unknown type name" errors.
- **Ordered Emission**: Ensures that C types are defined in an order that respects dependencies.
    - In source files (`.c`), named aggregate definitions are emitted first, followed by special types (slices, error unions, optionals), then globals and functions.
    - In header files (`.h`), named aggregates are emitted in topological dependency order (provided by `module->header_types`). Special types are emitted lazily after the structs they depend on are fully defined, preventing "incomplete type" errors in recursive scenarios.
- **Orchestration**: Uses `C89Emitter` to write code to these files.
- **Interface Generation**: Generates public header files (`.h`) containing declarations for symbols marked as `pub` in Zig.
- **Implementation Generation**: Generates C source files (`.c`) containing all definitions, with non-`pub` symbols marked as `static`.

## 2. C89Emitter Class

The `C89Emitter` is the primary interface for writing C89 code to a file. It is designed for efficiency and adherence to the project's technical constraints.

### Key Features:
- **Buffered Output**: Uses a 4KB stack-based buffer to batch writes to the filesystem, minimizing system call overhead without requiring heap allocations in the hot path.
- **Indentation Management**: Maintains a simple indentation level counter and provides a `writeIndent()` helper to ensure consistent code formatting (fixed at 4 spaces).
- **C89-Compliant Comments**: Provides an `emitComment()` helper that ensures all comments use the `/* ... */` style, as `//` comments are not supported in standard C89.
- **Debugging**: Supports emission tracing via `--debug-codegen` to track variable declarations, identifier resolution, and scope management.
- **Platform Abstraction**: Relies on the `platform.hpp` file I/O primitives, ensuring compatibility with both Win32 (using `kernel32.dll` directly) and POSIX environments.
- **RAII State Guards**: Uses stack-based RAII objects (`IndentScope`, `DeferScopeGuard`) to manage critical state like indentation level and the `defer_stack_`. This ensures state is correctly restored even on early returns or errors, preventing desynchronization of the generated C code.
- **Flexible Statement Emission**: `emitStatement` is designed to be flexible. It handles standard statement nodes (like `NODE_IF_STMT`, `NODE_WHILE_STMT`) as well as expression nodes (like `NODE_FUNCTION_CALL`, `NODE_BINARY_OP`). When an expression node is passed to `emitStatement`, it is automatically treated as an expression-statement by calling `emitExpression` and appending a semicolon. This simplifies code generation for contexts like switch prong bodies, where Zig allows single expressions.
- **Modular Dispatch**: Large emission functions are decomposed into focused helpers to improve legibility and maintainability. For example, `emitExpression` dispatches to:
    - `emitLiteral`: Handles all numeric, string, char, bool, and null literals. String literals are emitted as C-style string literals (e.g. `"hello"`), which are treated as pointer values by C compilers. For MSVC 6.0 compatibility, long strings are automatically split (see Section 4.12).
    - `emitUnaryOp` / `emitBinaryOp`: Handles operator logic.
    - `emitCast`: Centralizes `@intCast`, `@floatCast`, and `@ptrCast` logic.
    - `emitAccess`: Manages array, member, and slice access.
    - `emitControlFlow`: Reports errors for control-flow expressions that have not been correctly lifted into statements.
    - `emitTaggedUnionDefinition`: Handles the emission of named tagged unions as C `struct`s.
    - `emitTaggedUnionBody`: Emits the full body (tag + data union) of a tagged union.
    - `emitTaggedUnionPayloadBody`: Emits the `union` part of a tagged union.

### C89 Compatibility Layer (`zig_compat.h`)
All generated C files include `zig_runtime.h`, which incorporates `zig_compat.h`. This header provides a unified abstraction for:
- **Fixed-width types**: Maps Zig types like `i64` and `u64` to their C89 equivalents (e.g., `__int64` on MSVC 6.0).
- **Boolean types**: Provides `bool`, `true`, and `false` for strict C89 compilers.
- **Inline keyword**: Defines `ZIG_INLINE` to handle compiler-specific inline syntax or lack thereof.
- **Unused labels**: Provides `ZIG_UNUSED` and other macros to suppress warnings.

### Unused Continue Labels
To reduce compiler warnings (`-Wunused-label`) in the generated C code, `C89Emitter` tracks whether a `continue` statement actually occurs within each loop.
- **Mechanism**: A stack `loop_has_continue_` is maintained alongside `loop_id_stack_`.
- **Flag Activation**: The flag for the current loop is set to `true` whenever `emitContinue` is called for that loop's ID.
- **Conditional Emission**: The continue label (e.g., `__loop_1_continue: ;`) is only emitted at the end of the loop body if the flag is true.

#### Base Type Mapping
- **c_char**: Mapped to C `char`. This is distinct from `u8` (mapped to `unsigned char`) to ensure compatibility with standard C library function signatures (e.g., `fopen` expects `const char*`).

#### C89 Compatibility Layer (`zig_compat.h`)
All generated C files include `zig_runtime.h`, which incorporates `zig_compat.h`. This header provides a unified abstraction for:
- **Fixed-width types**: Maps Zig types like `i64` and `u64` to their C89 equivalents (e.g., `__int64` on MSVC 6.0).
- **Boolean types**: Provides `bool`, `true`, and `false` for strict C89 compilers.
- **Inline keyword**: Defines `ZIG_INLINE` to handle compiler-specific inline syntax or lack thereof.

#### Sign-Correct IO Helpers
The runtime IO helpers `__bootstrap_print`, `__bootstrap_write`, and `__bootstrap_panic` accept `const char*` instead of `const unsigned char*`. This eliminates pointer-sign mismatch warnings when passing string literals (which are `char*` in C) to these functions. Internal casts to `unsigned char*` are performed within the runtime implementation where necessary.

To ensure compliance even when passing Zig's `u8` pointers (which map to `unsigned char*` in C), the `C89Emitter` automatically injects an explicit `(const char*)` cast at the call site for the string arguments of these functions.

### 2.1 Line Ending and Statement Terminator Abstraction
To improve portability (e.g., support for CRLF on Windows 98) and centralize formatting, the `C89Emitter` provides abstractions for common C89 terminators. Direct use of hardcoded `";\n"` or `"\n"` is discouraged in favor of these helpers:
- **`endStmt()`**: Appends a semicolon followed by the configured line ending.
- **`writeLine()`**: Appends the configured line ending.
- **`writeLine(const char* str)`**: Appends a string followed by the configured line ending.
- **`LE()`**: Returns the current line ending string (`\n` or `\r\n`).

This ensures that the generated C code respects the `win_friendly_line_endings` compilation option consistently across all modules.

### 2.2 C Keyword Constants
To ensure consistency and avoid hardcoding strings for standard C89 keywords, the `C89Emitter` uses centralized constants (`KW_BREAK`, `KW_IF`, `KW_INT`, etc.).
- **Usage**: Emitter methods should use `writeString(KW_...)` or the `writeKeyword(KW_...)` helper.
- **`writeKeyword(const char* kw)`**: Emits the keyword followed by a single space. This is the preferred method for keywords that act as prefixes (e.g., `static`, `extern`, `struct`).

Using these constants simplifies maintenance and ensures that any necessary mangling or platform-specific keyword variations can be handled in one place.

### 2.3 Temporary Variable Allocation
As of the "para-Cresol" release, `C89Emitter` employs a unified strategy for generating temporary variables via `makeTempVarForType`. This ensures that all compiler-generated symbols (like `opt_tmp` for optionals or `for_idx` for loops) are declared at the beginning of their respective C blocks, adhering to strict C89 rules.

### 2.4 Unused Continue Labels
To reduce compiler warnings (`-Wunused-label`) in the generated C code, `C89Emitter` tracks whether a `continue` statement actually occurs within each loop.
- **Mechanism**: A stack `loop_has_continue_` is maintained alongside `loop_id_stack_`.
- **Flag Activation**: The flag for the current loop is set to `true` whenever `emitContinue` is called for that loop's ID.
- **Conditional Emission**: The continue label (e.g., `__loop_1_continue: ;`) is only emitted at the end of the loop body if the flag is true.

### 2.5 Combined Block and Statement Helpers
To simplify the emission of control flow structures and ensure consistent formatting of blocks and expression-statements, the `C89Emitter` provides several higher-level helpers:

- **`writeBlockOpen()`**: Writes `{`, a line ending, and increments the indentation level.
- **`writeBlockClose()`**: Decrements the indentation level, writes an indented `}`, and a line ending.
- **`writeExprStmt(const ASTNode* expr)`**: Indents, emits the C representation of the provided expression node, and appents a statement terminator (`endStmt()`).

#### Example: Refactoring `while` loops
**Before:**
```cpp
writeIndent();
writeString("while (");
emitExpression(node->condition);
writeString(") {\n");
{
    IndentScope while_indent(*this);
    emitStatement(node->body);
}
writeIndent();
writeString("}\n");
```

**After:**
```cpp
writeIndent();
writeKeyword(KW_WHILE);
writeString("(");
emitExpression(node->condition);
writeString(") ");
writeBlockOpen();
{
    emitStatement(node->body);
}
writeBlockClose();
```

These helpers reduce boilerplate, prevent "forgotten dedent" bugs in manual blocks, and centralize the logic for block formatting.

#### 2.3.1 Compound Assignment Emission
Compound assignments (e.g., `x += y`) are treated as expressions in C. When used as statements in Z98, they are automatically wrapped in a `(void)` cast to suppress "value computed is not used" warnings on legacy compilers. This is handled centrally in `C89Emitter::emitExpression` and is utilized by `writeExprStmt`.

Example:
Zig: `total += i;`
Generated C: `(void)(total += i);`

### Usage in Pipeline:
The `C89Emitter` is typically owned by the `CompilationUnit` and instantiated during the code generation phase.

```cpp
C89Emitter emitter(arena, "output.c");
emitter.emitComment("Generated by Z98");
emitter.writeString("int main() {\n");
emitter.indent();
emitter.writeIndent();
emitter.writeString("return 0;\n");
emitter.dedent();
emitter.writeString("}\n");
```

## 3. CVariableAllocator Class

The `CVariableAllocator` manages the allocation and uniquification of C variable names within a function scope. It ensures that all generated identifiers are valid in C89 and compatible with legacy compilers like MSVC 6.0.

### Responsibilities:
- **Keyword Avoidance**: Automatically detects conflicts with the 32 standard C89 keywords (e.g., `int`, `return`, `static`) and prefixes conflicting identifiers with `z_`. Identifiers beginning with `__` bypass this check.
- **Length Enforcement**: Enforces a strict 31-character limit for all identifiers to comply with MSVC 6.0 constraints.
- **Uniquification**: Resolves name collisions within a function by appending numeric suffixes (e.g., `my_var`, `my_var_1`).
- **Sanitization**: Replaces invalid characters in Zig identifiers with underscores to produce valid C identifiers.
- **Temporary Name Generation**: Provides a `generate(base)` method for creating unique names for compiler-generated temporary variables.

### Implementation Details:
- **State Management**: The allocator is designed to be reset via `reset()` at the start of each function body to ensure that names are unique only within their relevant scope.
- **Storage**: Allocated names are interned or copied into the `ArenaAllocator` to avoid manual memory management.

### Example:
Zig name `long_variable_name_exceeding_31_chars` might become `long_variable_name_exceeding_3`.
Zig name `int` becomes `z_int`.
Zig name `__tmp_if_result_very_long_identifier` becomes `__tmp_if_result_very_long_ide`.
Multiple uses of `tmp` result in `tmp`, `tmp_1`, `tmp_2`, etc.

### 3.1 Compiler-Internal Identifiers
Identifiers starting with `__` (double underscore) are reserved for compiler use (e.g., `__tmp_if_1`, `__bootstrap_print`). These identifiers bypass the standard mangling process:
- They do **not** receive a module prefix.
- They do **not** receive a `z_` prefix if they conflict with C keywords (the compiler ensures they don't).
- They are **not** sanitized (the compiler ensures they contain only valid characters).
- They **are** truncated to 31 characters for MSVC 6.0 compatibility.

This bypass is implemented in `C89Emitter::getC89GlobalName` and `CVariableAllocator::makeUnique`. The rationale is to ensure that compiler-generated temporaries remain unique and predictable, without interference from the user-level mangling rules.

## 4. Emission Strategies

### 4.1 Multi-Module Generation
The compiler generates a pair of files for each Zig module (e.g., `foo.zig`):
1. **`foo.c`**: Contains the full implementation. Includes `zig_runtime.h`. Private symbols are `static`.
2. **`foo.h`**: Contains the public interface. Only includes declarations for `pub` symbols. Uses standard header guards.

### 4.2 Type Emission Order in Headers
To support recursive types and avoid "incomplete type" errors in C89, the `CBackend` and `C89Emitter` follow a strict emission order in generated headers. To handle cross-module circular dependencies, forward declarations are prioritized over module inclusions:

1. **Forward Declarations**: All aggregate types (structs, unions, and tagged unions) that are defined in the current module are forward-declared first (e.g., `struct Node;`). This occurs immediately after including `zig_runtime.h` and **before** including any other module headers (`#include "other.h"`). This ensures that if `other.h` refers back to a type in the current module (e.g. via a pointer), the C compiler already knows the type is a struct.
2. **Module Inclusions**: Headers for imported modules are included after the local forward declarations.
3. **Named Aggregate Definitions**: Structs, unions, enums, and tagged unions defined in the current module are emitted in topological dependency order (provided by the `MetadataPreparationPass`). This order respects **value dependencies** (e.g., if `A` contains `B` by value, `B` is defined before `A`).
4. **Lazy Special Type Emission**: Special types like `Slice_T`, `Optional_T`, and `ErrorUnion_T` are often anonymous in Zig but require `typedef`s in C. These are emitted "lazily":
    - During the emission of a named aggregate (Step 2), if it contains a field of a special type, the `emitter.emitBufferedTypeDefinitions()` call immediately after the struct definition ensures that the special type's C `struct` is emitted.
    - Because Step 2 follows dependency order, by the time a special type is emitted, the underlying named aggregates it depends on (the payload or element type) are guaranteed to be complete.
4. **Globals and Prototypes**: Finally, external variables and function prototypes are emitted. Any special types used in their signatures that weren't already emitted are triggered and defined here.

This strategy ensures that a recursive struct returned by value in an error union (e.g., `pub fn foo() !Node`) correctly results in `struct Node` being defined before `ErrorUnion_Node`.

### 4.3 Two-Pass Block Emission
C89 requires all local variable declarations to appear at the beginning of a block, before any executable statements. To support Zig's flexible declaration placement, the `C89Emitter::emitBlock` method employs a two-pass strategy:
1. **Pass 1 (Declarations)**: Scans the block for all `NODE_VAR_DECL` nodes and emits their C declarations (e.g., `int x;`). Initializers are NOT emitted in this pass.
2. **Pass 2 (Statements)**: Emits all nodes in order. Variable declarations with initializers are converted into assignment statements (e.g., `x = 42;`) using the unified assignment logic.

### 4.3 Unified Assignment and Wrapping
The `C89Emitter::emitAssignmentWithLifting` method provides a centralized way to handle assignments, variable initializations, and return value wrapping. It automatically handles:
- **Type Coercion**: Generates the necessary C code to wrap values into `Optional` or `ErrorUnion` structures.
- **Struct/Array Initializers**: Decomposes Zig's positional initializers into individual C field assignments.
    - **Complex L-values**: If the target l-value is "complex" (e.g., a function call or multi-level dereference), the emitter evaluates it once into a temporary pointer and performs assignments through that pointer. This prevents double evaluation of side-effectful expressions and ensures correct C precedence.
    - **Simple L-values**: For simple identifiers or direct dereferences, it uses the `captureExpression` mechanism to stringify the l-value before decomposition.
- **Discarding Results**: Correctly handles assignments to the blank identifier `_` by evaluating the RHS for side effects and casting to `(void)`.

Note: Control-flow expression lifting is now handled at the AST level by the `ControlFlowLifter` pass, so the emitter no longer performs ad-hoc lifting.

This unification reduces code duplication and ensures consistent behavior across different parts of the code generator.

### 4.4 Control Flow Mapping
- **If Statements**: Mapped to C `if (cond) { ... } else { ... }`. The condition is always parenthesized.
  - **Braceless Support**: Zig allows `if (cond) stmt;`. The `ControlFlowLifter` normalizes these into synthetic blocks before they reach the emitter, so the `C89Emitter` always sees and emits braced blocks.
  - **Optional Capture**: If the condition is an optional type and uses the `|val|` capture, the emitter generates a temporary variable to hold the condition's result and an `if (tmp.has_value)` check. Inside the `then` block, it declares the capture variable and assigns `tmp.value` to it.
  - **Example (if-capture)**:
    ```zig
    if (optional_ptr) |ptr| {
        ptr.* = 10;
    }
    ```
    Generated C:
    ```c
    {
        Optional_Ptr_i32 opt_tmp = optional_ptr;
        if (opt_tmp.has_value) {
            int* ptr = opt_tmp.value;
            *ptr = 10;
        }
    }
    ```
- **While Loops**:
  - **Braceless Support**: Like `if`, braceless `while` bodies are normalized into blocks by the `ControlFlowLifter`.
  - **Loop Labeling Scheme**: Both `while` and `for` loops use a unified labeling scheme based on the loop's unique `label_id`.
    - **Start**: `__loop_<id>_start`
    - **Continue**: `__loop_<id>_continue`
    - **End**: `__loop_<id>_end`
  - **Unlabeled**: Plain loops without an iteration expression (`: (iter)`) and without a user label were previously emitted as standard C `while (cond) { ... }`. However, to ensure correct `break`/`continue` semantics when nested inside `switch` statements, all `while` loops now use the labeled `goto` pattern.
  - **Labeled or with Iteration Expression**: These loops (and now all `while` loops) are mapped to a `goto`-based pattern to support multi-level jumps and the Zig iteration step:
    ```c
    __loop_0_start: ;
    if (!(cond)) goto __loop_0_end;
    {
        /* body */
    }
    __loop_0_continue: ;
    /* optional iteration expression */
    goto __loop_0_start;
    __loop_0_end: ;
    ```
- **For Loops**: Translated to an equivalent `while` loop wrapped in a new block to handle capture variables and unique loop state.
  - **Braceless Support**: Braceless `for` bodies are normalized into blocks by the `ControlFlowLifter`.
  - **Discarding Captures**: If a capture is named `_`, the emitter does not generate a C variable declaration or assignment for it.
  - **Arrays/Slices**:
    ```c
    {
        size_t __for_idx_1 = 0;
        size_t __for_len_1 = /* len */;
        while (__for_idx_1 < __for_len_1) {
            T item = iterable[__for_idx_1];
            /* body */
            __for_idx_1++;
        }
    }
    ```
  - **Ranges**:
    ```c
    {
        size_t __for_idx_1 = start;
        size_t __for_len_1 = end;
        while (__for_idx_1 < __for_len_1) {
            size_t item = __for_idx_1;
            /* body */
            __for_idx_1++;
        }
    }
    ```
- **Break/Continue**:
  - **Unlabeled**: Mapped directly to C `break;` and `continue;`, unless the loop requires labels (e.g., due to an iteration expression or being a `for` loop).
  - **Labeled or requiring labels**: Mapped to `goto __loop_<id>_end;` for `break` and `goto __loop_<id>_continue;` (or `_start` if no iteration expr) for `continue`.
- **Switch Statements**:
  - **Range Lowering Strategy**: Switch cases involving ranges (`start...end` or `start..end`) are expanded into individual C `case` labels.
    - Inclusive (`...`): All values from `start` to `end` (inclusive) get a label.
    - Exclusive (`..`): Values from `start` up to `end - 1` get a label.
    - **Pseudocode**:
      ```cpp
      i64 effective_end = range->is_inclusive ? end : end - 1;
      for (i64 val = start; val <= effective_end; ++val) {
          writeIndent();
          writeString("case ");
          writeI64(val);
          writeString(":\n");
      }
      ```
    - **Character Literals**: Character literals (e.g., `'a'...'z'`) in ranges are emitted as their integer ASCII values (e.g., `case 97:` through `case 122:`). Character literals are also supported in other constant evaluation contexts, resolved to their integer values.
    - **Limit**: Expansion is limited to 1000 labels per range to prevent excessive code bloat.
  - **Tagged Union Capture**: When switching on a tagged union, the emitter generates a block for each case that has a capture variable.
    ```c
    case Union_Tag_A: {
        int x = switch_tmp.data.A;
        /* body */
    } break;
    ```
    - **Void Handling**: If the captured field has type `void`, the C variable declaration and assignment are skipped to comply with C89 rules.
    - **Declaration/Assignment Separation**: For non-void captures, the emitter separates the declaration of the capture variable from its assignment. This avoids using braced initializers for anonymous structs, which is not permitted in C89.
- **Return Statements**: Mapped to `return expr;` or `return;`. If `defer` statements are active in the function, they are emitted before the return. If the function returns a value, a temporary variable is used to hold the value while defers run. If the returned expression is a `switch`, `try`, or `catch`, it is lifted to a statement and the result is returned via a temporary.
  - **Implicit Return**: For functions returning `!void` or `ErrorSet!void`, if the end of the body is reached without a return, an implicit `return {0};` (success) is emitted.
- **Unreachable Expression**: `unreachable` is mapped to a call to `__bootstrap_panic("reached unreachable", __FILE__, __LINE__)`.
  - **Lifting**: When used as an expression (e.g., in a branch of an `if` expression), `unreachable` is integrated into the `ControlFlowLifter`. It is emitted as a panic call in the corresponding branch of the generated C statement, ensuring that dead code following the expression is correctly skipped.
  - **Divergence**: The `allPathsExit` helper recognizes `unreachable` as a diverging node. The emitter uses this information to stop generating subsequent statements in a block after an `unreachable` is encountered.
- **Extern Functions and Variables**: Symbols marked as `extern` (including runtime intrinsics like `arena_alloc`) bypass the standard name mangling and use their original Zig name in the generated C code. This ensures compatibility with standard C libraries and the compiler's own runtime.
- **Defer Statements**: Implemented using a compile-time stack of deferred actions.
  - **Braceless Support**: Braceless `defer stmt;` is normalized into a block-wrapped defer by the `ControlFlowLifter`.
  - When entering a block, a new scope is pushed onto the stack.
  - `defer` statements are added to the current scope on the stack.
  - At the natural end of a block, all defers in that scope are emitted in reverse order.
  - For `return`, `break`, and `continue`, the emitter identifies all scopes being exited and emits their deferred actions in order (from innermost outward) before emitting the jump or return.
- **ErrDefer Statements**: Fully implemented using a function-level error flag.
  - **Error Tracking**: If a function returns an error union and contains at least one `errdefer`, the emitter generates a unique error flag variable (e.g., `int err_occurred_1 = 0;`) in the function prologue.
  - **Flag Activation**: In `emitReturn`, if the return value's `is_error` field is true, the error flag is set to `1` before executing deferred actions.
  - **Conditional Execution**: `errdefer` statements are emitted inside an `if (err_occurred_1) { ... }` block during scope exit or function return.
  - **Execution Order**: Like regular `defer`, `errdefer` actions are executed in reverse order of declaration (LIFO) within their scope, but only after all preceding regular `defer` statements for that scope have run.
  - **Scope Constraints**: To prevent stack exhaustion on legacy hardware, the total number of `defer` and `errdefer` statements is limited to 32 per scope. Exceeding this limit results in a compilation error (`ERR_TOO_MANY_DEFERS`).

### 4.4 Slice Support
Slices (`[]T`) are emitted as C structs containing a pointer and a length.

#### Central Slice Header (`zig_special_types.h`)
To ensure that slice types (which are often anonymous in Zig but require named `struct`s in C) are available across all modules, the compiler generates a central header file named `zig_special_types.h`.
- **Generation**: Created once per compilation by `CBackend::generateSpecialTypesHeader`.
- **Inclusion**: Automatically included by the `C89Emitter::emitPrologue` in every generated `.c` and `.h` file, immediately after `#include "zig_runtime.h"`.
- **Contents**: Contains `typedef struct { T* ptr; usize len; } Slice_T;` for every unique slice type used in the program, guarded by `#ifndef ZIG_SLICE_Slice_T` to prevent multiple definitions during Single Translation Unit (STU) builds.
- **Helper Functions**: Also contains the `__make_slice_T` static inline helpers used for array-to-slice coercion and slicing operations.

#### Type Definition
For each unique slice type encountered, the compiler generates a `typedef` and a static inline helper function for construction.
- **Naming**: Slice structs are named using a mangling scheme: `Slice_` + mangled element type (e.g., `Slice_i32`, `Slice_Ptr_i32`).
- **Visibility**: If a slice is used in a `pub` declaration, its `typedef` and helper are placed in the module's header (`.h`). Otherwise, they are in the implementation file (`.c`).
- **Caching Strategy**: To ensure that every header file is self-contained, types like slices, error unions, and optionals are emitted in every header that uses them. The `MetadataPreparationPass` pre-populates `module->header_types` by recursively scanning all reachable types from public symbols to ensure all transitive dependencies (including nested special types) are included. In source files (`.c`), the `CBackend` performs a deep recursive scan of all AST nodes and their associated types before emission. A global cache is used to ensure each type is emitted only once per translation unit.
- **Const Qualifiers**: `const` is dropped in the emitted C code, so `[]const T` and `[]T` use the same C struct.

#### Operations
- **Indexing**: `s[i]` is emitted as `s.ptr[i]`.
- **Length**: `s.len` is emitted as `s.len`.
- **Slicing**: `base[start..end]` is emitted as a call to the generated helper: `__make_slice_T(computed_ptr, computed_len)`.
- **Implicit Coercion**: Array-to-slice coercion is automatically handled by the `TypeChecker` by inserting a synthetic slicing node, which the emitter then translates into a helper call. String literals are also implicitly coerced to `[]const u8` slices. For control-flow expressions yielding slices, the TypeChecker uses a **Distributed Coercion** strategy to ensure branches produce structs, not pointers, before lifting occurs.

#### Helper Functions
For each unique slice type, a construction helper is generated:
- **Signature**: `ZIG_INLINE ZIG_UNUSED Slice_T __make_slice_T(T* ptr, usize len)`
- **Implementation**: Returns a `Slice_T` struct initialized with the provided pointer and length.
- **Usage**: Invoked for all slicing expressions (`base[start..end]`) and implicit array-to-slice coercions.

#### String Literal Coercion to Slice
To avoid signedness warnings when coercing string literals (which are `char*` in C89) to `u8` slices (where `u8` is `unsigned char`), the construction helper for `u8` slices is specialized:
- **Signature**: `ZIG_INLINE ZIG_UNUSED Slice_u8 __make_slice_u8(const char* ptr, usize len)`
- **Implementation**: The pointer parameter is explicitly cast to `unsigned char*` when assigning to the slice's `ptr` field: `s.ptr = (unsigned char*)ptr;`.
- **Rationale**: This allows string literals to be passed directly to the helper without generating `-Wpointer-sign` warnings, while maintaining the correct unsigned representation for `u8` data.

### 4.5 Array and Struct Initializers
Standard C89 does not allow array or struct assignment after declaration (e.g., `arr = {1, 2, 3};` is invalid). To support Zig's flexible variable initialization, the `C89Emitter` employs the following strategy for local variables:
1. **Positional Initialization**: If a variable is initialized with `{ ... }`, the emitter generates a series of individual assignments for each field or array element.
   - Zig `var arr = [3]i32{1, 2, 3};` becomes:
     ```c
     int arr[3];
     arr[0] = 1;
     arr[1] = 2;
     arr[2] = 3;
     ```
   - **Complex L-values**: When assigning to a complex location (e.g., `ptr.* = .{ .x = 1 }`), the emitter uses `captureExpression` to stringify the l-value (e.g., `(*ptr)`) and then emits individual assignments (e.g., `(*ptr).x = 1;`).
   - This approach ensures compatibility with C89 and works correctly even if the initializer elements are non-constant expressions.
2. **Global Constant Initializers**: Global variables (using `pub const` or `pub var`) are emitted using C-style constant initializers: `static int arr[3] = {1, 2, 3};`.

### 4.5 Built-in Intrinsics
- **@ptrCast(T, expr)**: Emitted as a standard C-style cast: `(T)expr`.
- **@intCast / @floatCast**: Handled by the TypeChecker for constants (constant folding). For runtime values, they emit calls to checked conversion helpers (e.g., `__bootstrap_i32_from_u32(x)`).
- **std.debug.print**: Lowered to a sequence of `__bootstrap_print(const char*)` and `__bootstrap_print_int(i32)` calls. The compiler parses the format string at compile-time and decomposes it into multiple calls, mapping `{}` placeholders to the positional arguments provided in the tuple literal.

### 4.6 Tuple Literals
Tuple literals `.{ arg1, arg2 }` are supported primarily for `std.debug.print` lowering. When used in other constant contexts, they are emitted as C-style array/struct initializers `{ arg1, arg2 }`.

### 4.6 Many-item Pointers ([*]T)
Many-item pointers (e.g., `[*]u8`, `[*]const i32`) are supported in the bootstrap compiler. They represent pointers to zero or more items of type `T`, mapping directly to C's raw pointers (`T*`).

#### Semantics
- **Indexing**: `[*]T` supports indexing `ptr[i]`, returning a value of type `T`.
- **Dereferencing**: `[*]T` supports the dereference operator `.*`, yielding the first element (equivalent to `ptr[0]`). Mapped to C `*ptr`.
- **Arithmetic**: `[*]T` supports pointer arithmetic (`ptr + i`, `i + ptr`, `ptr - i`) and pointer subtraction (`ptr1 - ptr2`).
  - Arithmetic requires **unsigned** integer offsets (`usize`, `u32`).
  - Pointer subtraction yields `isize`.
- **Nullability**: In the bootstrap compiler, `[*]T` can be assigned the `null` literal (mapped to `((void*)0)`).

#### Pointer Arithmetic Summary
| Operation | Many-item ([*]T) | Single-item (*T) | Result Type |
|-----------|------------------|------------------|-------------|
| `ptr + unsigned` | ✓ Allowed | ✗ REJECTED | `[*]T` |
| `ptr - unsigned` | ✓ Allowed | ✗ REJECTED | `[*]T` |
| `ptr1 - ptr2` | ✓ Allowed | ✗ REJECTED | `isize` |
| `ptr[i]` | ✓ Allowed | ✗ REJECTED | `T` |
| `ptr.*` | ✓ Allowed | ✓ Allowed | `T` |

#### Multi-level Pointers
Arithmetic on multi-level pointers is supported only if the outer level is a many-item pointer.
- Zig `var pp: [*]*i32` -> C `int** pp`.
- `pp + 1` advances by `sizeof(int*)`.

### 4.7 Operator Precedence & Parentheses
The emitter maintains correct C precedence by automatically parenthesizing the base expressions of postfix operators (`.`, `->`, `[]`, `()`) when the base expression involves lower-precedence operators like unary `*` or `&`. For example, Zig `ptr.*.field` becomes C `(*ptr).field`.

This logic is implemented in `requiresParentheses()` and is applied in:
- `emitAccess`: For standard member and array access.
- `emitAssignmentWithLifting`: For decomposing struct/array initializers into field-by-field assignments, and for assigning tag literals to tagged unions.
- `emitOptionalWrapping` / `emitErrorUnionWrapping`: For wrapping values into special structures.

#### 4.7.1 Complex L-value Detection (`isSimpleLValue`)
To prevent double evaluation and ensure correct precedence, the emitter uses the `isSimpleLValue()` helper to distinguish between "safe" l-values (identifiers and variable declarations) and "complex" ones (dereferences, function calls, or array access).

When a complex l-value is encountered during wrapping, decomposition, or tag assignment:
1. A temporary pointer is declared and initialized with the address of the complex l-value: `T* tmp = &(complex_expr);`.
2. All subsequent accesses and assignments are performed through the temporary pointer: `(*tmp).member = value;`.

This strategy ensures that side-effectful expressions are evaluated exactly once and that the resulting C code correctly respects the intended Zig semantics regardless of C's complex operator precedence rules.

### 4.8 Expression Capture (Redirection)
The `C89Emitter::captureExpression` helper allows the compiler to obtain the C string representation of an AST node without writing it to the output file.
- **Mechanism**: Temporarily redirects the emitter's output by disabling the `output_file_` and enabling `in_type_def_mode_`, which writes to the `type_def_buffer_`.
- **Reentrancy**: Carefully saves and restores the global buffer position and state to allow nested captures during complex decomposition.
- **Usage**: Primarily used for stringifying l-values during struct/array initializer decomposition.

### 4.9 Multi-level Pointers (**T)
Multi-level pointers (e.g., `**i32`, `***f64`) are fully supported in the bootstrap compiler and map directly to C's multi-level pointers (e.g., `int**`, `double***`).

### 4.10 Function Pointers
Function pointers (e.g., `fn(i32) i32`) are supported and map to C's function pointer syntax.

#### Recursive Declarators
C's "inside-out" declarator syntax is handled by a recursive emission strategy (`emitTypePrefix` and `emitTypeSuffix`). This ensures that complex nested types like "array of pointers to functions returning pointers to functions" are emitted correctly.

Examples:
- Zig `var fp: fn(i32) void` -> C `void (*fp)(int)`
- Zig `var fp2: fn(i32, i32) i32` -> C `int (*fp2)(int, int)`
- Zig `var fps: [10]fn() void` -> C `void (*fps[10])(void)`
- Zig `fn foo() fn() void` -> C `void (*foo(void))(void)`
- Zig `fn get_handler(id: i32) fn(i32) i32` -> C `int (*get_handler(int))(int)`

#### Indirect Calls
Indirect calls through function pointer variables or complex expressions (e.g., `fps[0]()`) are emitted directly as standard C function calls: `callee(args)`. C89 allows implicit dereferencing of function pointers.

#### Limitations
- **Parameter Limit**: Arbitrary parameter limits (previously 4) have been removed; function pointers now support an unlimited number of parameters via dynamic allocation.
- **Implicit Coercion**: Function declarations (names) implicitly coerce to their corresponding function pointer type when assigned or passed as arguments, provided signatures match exactly.
- **Calling Convention**: Defaults to `__cdecl`. Custom calling conventions are not supported.
- **Nullability**: Function pointers can be assigned `null` (temporary bootstrap extension).

#### Const Qualifiers
To simplify code generation and avoid complex C declaration syntax (e.g., `int* const*`), the Z98 bootstrap compiler **drops most `const` qualifiers** in the generated C code for pointers and variables.
- Zig `*const i32` -> C `int*`
- Zig `*const *i32` -> C `int**`
- Zig `const x: i32 = 42` -> C `int x = 42`

This is safe because the Zig compiler frontend already enforces const-correctness during semantic analysis. The generated C code serves only as an intermediate representation where these qualifiers are not required for correctness. Note: For pointer-to-array types (`*[N]T`), the emitter handles decay to many-item pointers by injecting `&(*ptr)[0]` as needed.

#### Extern *void Handling
Zig's `*void` (pointer to a zero-sized type) is consistently emitted as `void *` in C, especially in `extern` signatures. This ensures that declarations like `extern fn alloc(size: usize) *void` map correctly to `extern void* alloc(unsigned int size)`.

#### Pointer to Array Decay
When a variable of type `*[N]T` is assigned to a many-item pointer `[*]T`, the `TypeChecker` injects a decay expression.
- **Variable Decay**: `ptr` of type `*[N]T` becomes `&(*ptr)[0]` in the generated C code, correctly decaying the array pointer to its first element.
- **String Literal Decay**: String literals (now typed as `*const [N]u8`) are already pointer values in C, so they are passed directly without extra address-of operations.

### 4.11 Error Handling Support
Error handling in the bootstrap compiler is implemented using a C89-compatible structure and a global error registry.

#### Error Tag Registry
All unique error tags encountered across all modules (in definitions or literals) are registered in a global registry and assigned unique positive integers starting from 1. The value 0 is reserved for "success". These are emitted as `#define` constants in the prologue of each generated C file.

```c
/* Error tags */
#define ERROR_FileNotFound 1
#define ERROR_OutOfMemory 2
```

#### Error Union Types (!T)
Error unions are represented as C `struct`s containing a `union` for the payload and the error code, plus a boolean flag.

- **Naming**: Error union structs are named using a mangling scheme: `ErrorUnion_` + mangled payload type (e.g., `ErrorUnion_i32`).
- **Structure**:
```c
typedef struct {
    union {
        T payload;   /* Valid if is_error is 0 */
        int err;     /* Valid if is_error is 1 */
    } data;
    int is_error;    /* 0 = success, 1 = error */
} ErrorUnion_T;
```
For `void` payloads, the `union` is omitted:
```c
typedef struct {
    int err;
    int is_error;
} ErrorUnion_void;
```
Size and alignment are calculated to match a 32-bit target: `ErrorUnion_void` is 8 bytes with 4-byte alignment. `ErrorUnion_T` size depends on `T`.

#### void in Unions and Structs
In accordance with C89 rules, fields of type `void` are omitted from emitted C `struct` and `union` definitions. If a union would be empty after omitting all `void` fields, a `char __dummy;` field is injected to maintain valid C syntax. Tagged union initializers only assign the tag if the payload for the active arm is `void`.

#### Error Set Types
Error sets map to the C `int` type.
- **Naming**: Mapped to `ErrorSet` in internal mangling, but used directly as `int` in most contexts.
- **Error Codes**: Unique positive integers starting from 1 (0 is success). Emitted as `#define ERROR_Tag ID` constants.

#### Implicit Wrapping
When a value of type `T` is assigned to an error union `!T` (including variable initializers and returns), the emitter generates code to wrap it as a success value:
```c
target.data.payload = value;
target.is_error = 0;
```

When an error literal `error.Tag` is assigned to an error union, it is wrapped as an error using the registered tag ID:
```c
target.data.err = ERROR_Tag;
target.is_error = 1;
```

#### Return Statements
Returning from a function that returns an error union performs implicit wrapping if the returned expression is not already an error union. This is implemented by using a temporary variable `__return_val` and then returning it.

## 6. Build System & Separate Compilation

To avoid symbol conflicts (especially with `static` functions and slice helpers) and provide a professional development experience, the `CBackend` generates build scripts that perform separate compilation and linking for each module.

### 6.1 Build Automation
The backend automatically generates basic build scripts in the output directory:
- **`build_target.bat`**: A Windows batch script for MSVC 6.0. It compiles each generated `.c` file separately using `cl /c` and links them into `app.exe` using `link.exe`.
- **`build_target.sh`**: A shell script for GCC. It compiles each generated `.c` file separately using `gcc -c` and links them into `app` using `gcc`.

### 6.2 Runtime Portability
To ensure the generated code is self-contained and buildable on any system with a compatible C compiler:
- **`zig_runtime.h` and `zig_runtime.c`**: These files are copied from the compiler's source tree into the output directory.
- **`zig_special_types.h`**: This header, containing definitions for slices and other program-specific types, is generated in the output directory.

By providing all necessary runtime components and a standard multi-module build script, the Z98 compiler ensures that its output is immediately usable by developers on legacy platforms.

## 6.1 Error Handling Code Generation (Milestone 7)

**Preamble:** These features are part of the extended feature set enabled after Milestone 7, building on the core bootstrap compiler. They enable Zig-style error propagation and handling while remaining compatible with C89.

### Error Union Representation
Error unions (`!T`) are emitted as C structures. The name is mangled as `ErrorUnion_T`.

```c
typedef struct {
    union {
        T payload;   /* Valid if is_error is 0 */
        int err;     /* Valid if is_error is 1 */
    } data;
    int is_error;    /* 0 = success, 1 = error */
} ErrorUnion_T;
```

### Lifting Strategy
Since C89 does not support expressions with control flow, `try` and `catch` expressions are "lifted" into statement blocks that assign their result to a temporary variable or a target location.

#### `try` Expression
Zig:
```zig
var x = try mightFail();
```

Generated C:
```c
{
    ErrorUnion_i32 __try_res = mightFail();
    if (__try_res.is_error) {
        /* emit defers */
        return __try_res;
    }
    x = __try_res.data.payload;
}
```

#### `catch` Expression
Zig:
```zig
var x = mightFail() catch 0;
```

Generated C:
```c
{
    ErrorUnion_i32 __catch_res = mightFail();
    if (__catch_res.is_error) {
        x = 0;
    } else {
        x = __catch_res.data.payload;
    }
}
```

#### `catch` with Error Capture
Zig:
```zig
var x = mightFail() catch |err| {
    if (err == error.Oops) return 0;
    return 1;
};
```

Generated C:
```c
{
    ErrorUnion_i32 __catch_res = mightFail();
    if (__catch_res.is_error) {
        int err = __catch_res.data.err;
        /* lifted block body */
    } else {
        x = __catch_res.data.payload;
    }
}
```

### Known Limitations

1. **Mixed Declarations and Code**: C89 requires all variable declarations at the start of a block. While the emitter uses a two-pass approach to hoist variable declarations, compiler-generated temporaries from expression lifting may still be emitted after some statements. Legacy compilers like MSVC 6.0 and OpenWatcom are lenient, but strict C89 compilers may issue warnings.
2. **Nesting Depth**: Deeply nested `try`, `catch`, or `orelse` expressions within complex binary operations or array indices may encounter lifting issues.
3. **Empty Macro Arguments**: The compiler avoids emitting macros with empty arguments (e.g., `#define FOO()`) to maintain compatibility with MSVC 6.0.

## 6.2 Optional Types Code Generation (Milestone 7)

**Preamble:** Optional types (`?T`) are supported as part of the bootstrap language extension. They enable nullable values for both pointers and value types using a uniform struct representation.

### Optional Representation
Optional types are emitted as C structures. The name is mangled as `Optional_T`.

**Uniform Struct Representation (Bootstrap Limitation)**: While modern Zig optimizes `?*T` to be the same size as a raw pointer (using 0 as null), the Z98 bootstrap compiler uses a uniform struct representation for all optional types internally.

```c
typedef struct {
    T value;         /* Valid if has_value is 1 */
    int has_value;   /* 1 = has value, 0 = null */
} Optional_T;
```

### C ABI Mapping for Optional Pointers (Milestone 8)
To maintain compatibility with the C ABI, optional pointers (`?*T`, `?[*]T`, and `?fn(...)`) are automatically transformed into raw C pointers when they cross the boundary of `extern` or `export` functions.

- **Extern Functions (Zig calls C)**:
    - **Arguments**: The `ControlFlowLifter` generates a temporary raw pointer. If the optional has a value, the temporary is assigned the payload; otherwise, it is assigned `NULL` (0). The raw pointer is then passed to the C function.
    - **Return Value**: If a C function returns a raw pointer that Zig expects as an optional, the lifter wraps the result. If the pointer is non-null, it produces an optional with `has_value = 1`; otherwise, `has_value = 0`.

- **Export Functions (C calls Zig)**:
    - **Parameters**: In the function prologue, the lifter wraps each raw pointer parameter from C into a Zig-internal optional struct.
    - **Return Value**: Before returning to C, the lifter unwraps the Zig optional into a raw C pointer.

This "lift early, emit simply" strategy ensures that the `C89Emitter` sees standard C signatures for boundary functions while the rest of the Zig code continues to use the uniform struct representation.

### Lifting Strategy
Like other control-flow expressions, `orelse` is "lifted" into a statement block.

#### `orelse` Expression
Zig:
```zig
var x = opt orelse 0;
```

Generated C:
```c
{
    Optional_i32 __orelse_res = opt;
    if (__orelse_res.has_value) {
        x = __orelse_res.value;
    } else {
        x = 0;
    }
}
```

### Implicit Wrapping
When a value of type `T` is assigned to an optional `?T`, the emitter generates code to wrap it:
```c
target.value = value;
target.has_value = 1;
```

When the `null` literal is assigned to an optional, it is wrapped as null:
```c
target.has_value = 0;
```

### Defer Interaction
While `orelse` itself doesn't cause early returns (unlike `try`), the fallback expression (right side of `orelse`) can contain a `return` or `unreachable`. The emitter correctly handles these by executing any active `defer` statements before the `return` or emitting a panic for `unreachable`.

### Defers and Loop Control Flow
`defer` and `errdefer` statements interact with loop control flow (`break`, `continue`) as follows:
- **Scope Exit**: When a `break` or `continue` is encountered, the emitter identifies all blocks being exited (from the current point up to the target loop).
- **Execution Order**: Deferred statements for all these scopes are emitted in reverse order of their appearance (LIFO), innermost first.
- **Jump**: After all relevant defers are emitted, the final `goto` to the loop's `_end` or `_continue` label is generated.
- **Independence**: This mechanism relies on the `label_id` assigned by the `TypeChecker` and is independent of the specific C label naming scheme.

### 6.3 Anonymous Structs and Unions
Zig allows defining anonymous structs and unions as types for fields (e.g., `data: union { a: i32, b: f32 }`). Standard C89 supports anonymous types if they are defined inline with the field declaration.

#### Emission Strategy
The `C89Emitter` identifies anonymous structs and unions by checking if their `c_name` and `as.struct_details.name` are `NULL`.

- **Inlined Definition**: Instead of emitting a named type (e.g., `struct S data;`), the emitter outputs the full type body followed by the field name: `union { int a; float b; } data;`.
- **Recursive Emission**: The `emitStructBody` and `emitUnionBody` helpers recursively handle fields, ensuring that nested anonymous types are also inlined correctly.
- **Keyword Mangling**: Field names that conflict with C keywords (like `int` or `float`) are mangled (e.g., `z_int`) using `getSafeFieldName` to ensure valid C89 syntax.
- **Recursive Definition**: When a struct, union, or tagged union contains a field with an anonymous aggregate type, the `C89Emitter` recursively emits the full definition of that anonymous type before the parent container's definition. This ensures that the generated C code has complete type information for all nested anonymous structures.

Example Zig:
```zig
const S = struct {
    data: union {
        val: i32,
        other: f32,
    },
};
```

Generated C89:
```c
struct S {
    union {
        int val;
        float other;
    } data;
};
```

### 6.4 Tagged Unions
Tagged unions (both `TYPE_TAGGED_UNION` and `TYPE_UNION` with `is_tagged` flag) are emitted as C `struct`s containing a `tag` field and a `data` union. This is abstracted by the `isTaggedUnion()` helper in `type_system.hpp`.

#### Tag Literal Coercion
To support idiomatic Zig patterns like `return .Eof;` for tagged unions, the `TypeChecker` and `C89Emitter` implement a coercion mechanism. When a tag literal (e.g., `.Eof`) is assigned to a tagged union, and the corresponding union arm has a `void` payload, the `TypeChecker` automatically coerces the literal into a synthetic tagged union initializer (e.g., `.{ .Eof }`). The emitter then generates a C structure initializer that only sets the `.tag` field.

#### Emission Strategy
The `C89Emitter::emitBaseType` and `C89Emitter::emitTaggedUnionDefinition` handle tagged union emission.

- **Named Tagged Unions**: Emitted as `struct Name`. The definition includes the tag and the payload union.
- **Anonymous Tagged Unions**: Emitted inline where they are used (e.g., as struct fields) as an anonymous `struct { TagType tag; union { ... } data; }`.
- **Layout**:
  ```c
  struct UnionName {
      TagType tag;
      union {
          Field1Type Field1;
          Field2Type Field2;
          /* ... */
      } data;
  };
  ```
- **Forward Declarations**: Because tagged unions are lowered to C `struct`s, they **must** be forward-declared using the `struct` keyword in C, even if they are conceptually "unions" in Zig. The `C89Emitter::ensureForwardDeclaration` method handles this automatically by using the correct keyword based on `isTaggedUnion(type)`.
- **Implicit Enums**: For `union(enum)`, the `tag` field uses the generated enum `UnionName_Tag`.
- **Field Omitting**: Like bare unions and structs, `void` fields are omitted from the payload union. If all fields are `void`, a `char __dummy;` is injected to maintain valid C syntax.

#### Tagged Union Initialization with Anonymous Structs
When a tagged union variant has an anonymous struct payload (e.g., `Cons: struct { car: i32, cdr: i32 }`), the compiler transforms the Zig initializer `Value{ .Cons = .{ .car = x, .cdr = y } }` into the following C code:
```c
struct zS_xxx_Value v;
v.tag = zE_xxx_Value_Tag_Cons;
v.data.Cons.car = x;
v.data.Cons.cdr = y;
```
This ensures correct field ordering and C89 compatibility. The implementation handles:
- **Detection**: `C89Emitter::emitInitializerAssignments` detects if the value being assigned to a tagged union variant is a nested `NODE_STRUCT_INITIALIZER`.
- **L-value Capture**: Uses `captureExpression` to safely stringify the base l-value (e.g., `v`).
- **Field-by-Field Assignment**: Recursively emits assignments for each field of the anonymous payload struct into the `.data.Variant.Field` path in C.
- **Complex L-values**: To prevent double-evaluation, complex l-values are evaluated into a temporary pointer (e.g., `init_lval_tmp`) before decomposition.

Example Zig (Named):
```zig
const U = union(enum) {
    A: i32,
    B: f64,
    C: void,
};
```

Generated C89:
```c
enum U_Tag {
    U_Tag_A = 0,
    U_Tag_B = 1,
    U_Tag_C = 2
};
typedef enum U_Tag U_Tag;

struct U {
    U_Tag tag;
    union {
        int A;
        double B;
    } data;
};
```

Example Zig (Anonymous Field):
```zig
const S = struct {
    u: union(enum) { a: i32, b: f32 },
};
```

Generated C89:
```c
struct S {
    struct {
        int tag;
        union {
            int a;
            float b;
        } data;
    } u;
};
```

### 4.12 String Literal Splitting (MSVC 6.0 Compatibility)
Standard C89 (and specifically MSVC 6.0) has limits on the maximum length of a string literal (2048 characters for MSVC 6.0). To ensure generated code remains compatible with legacy toolchains:
- **Automatic Splitting**: The `C89Emitter` monitors the length of emitted string literals. If a literal exceeds 1024 characters, it is closed and a new one is started using C's implicit concatenation: `"part 1" "part 2"`.
- **Atomic Escapes**: Splitting only occurs after a complete byte (and its associated escape sequence) has been emitted. This prevents breaking escape sequences like `\xAB` or `\123` across literal boundaries.
- **Implementation**: Managed in `C89Emitter::emitStringLiteral` using a local counter and the `MAX_STRING_LITERAL_CHUNK` constant.
