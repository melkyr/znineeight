# Error Code Mapping Strategy (Milestone 5 Planning)

## Overview
This document outlines the strategy for mapping modern Zig error handling features to C89-compatible constructs. Since the bootstrap compiler targets legacy environments (MSVC 6.0, Win9x), we must convert Zig's rich error system into simple integer codes and structure-based error propagation that can be reliably compiled by a C89 compiler.

## Global Error Registry
The bootstrap compiler will maintain a global registry of all unique error tags encountered during the compilation of a unit.

- **Success Convention**: The integer value `0` is reserved for "success," following standard C conventions.
- **Unique Identifiers**: Each unique error tag (e.g., `FileNotFound`, `OutOfMemory`) will be assigned a unique 32-bit positive integer starting from `1`.
- **Global Scope**: To ensure that error set merging (`E1 || E2`) works correctly, all error tags across all error sets share this same global integer space.
- **MSVC 6.0 Compatibility**: Error codes will be emitted as `#define` constants to avoid signedness or size ambiguities associated with `enum` on older compilers.

```c
/* Generated C89 - Global Error Registry */
#define ERROR_SUCCESS           0
#define ERROR_FILE_NOT_FOUND    1
#define ERROR_PERMISSION_DENIED 2
#define ERROR_OUT_OF_MEMORY     3
#define ERROR_TIMEOUT           4
```

## Error Union Representation (`!T`)
Error unions will be translated into a C89 `struct` containing a `union` for the payload and the error code.

```c
/* Zig: fn read(path: []const u8) !i32 */

/* Generated C89 */
typedef struct {
    union {
        int32_t success_value;    /* Valid if is_error is 0 */
        int error_code;           /* Valid if is_error is 1 */
    } data;
    int is_error;                 /* 0 = success, 1 = error */
} Errorable_int32;

Errorable_int32 read(const char* path);
```

### Alternative: Pointer Parameters
For simpler functions or to avoid struct-return overhead on very old hardware, the compiler may optionally emit functions that use an out-parameter for the error code:

```c
/* Generated C89 Alternative */
int32_t read(const char* path, int* out_error);
/* Returns payload, sets *out_error. ERROR_SUCCESS (0) on success. */
```

## Try, Catch, and Orelse Translation

### `try` Expression
The `try` expression is translated into an `if` check that propagates the error up the call stack.

**Zig Source:**
```zig
var x = try mightFail();
```

**Generated C89:**
```c
Errorable_int32 result = mightFail();
if (result.is_error) {
    return result; /* Propagate the error union */
}
int32_t x = result.data.success_value;
```

### `catch` Expression
The `catch` expression provides a fallback value if an error occurs.

**Zig Source:**
```zig
var x = mightFail() catch 0;
```

**Generated C89:**
```c
Errorable_int32 result = mightFail();
int32_t x = result.is_error ? 0 : result.data.success_value;
```

### `orelse` Expression
Similar to `catch`, but specifically for optional types (which are also rejected by C89 validator but catalogued).

**Zig Source:**
```zig
var x = optional_val orelse default_val;
```

**Generated C89:**
```c
/* Assuming Optionals are also mapped to structs with a bool flag */
int32_t x = optional_val.has_value ? optional_val.value : default_val;
```

## MSVC 6.0 & C89 Technical Constraints
1. **Integer Size**: Error codes must fit in a 32-bit signed `int` (range 0 to 2,147,483,647).
2. **No 64-bit Enums**: MSVC 6.0 does not support 64-bit enums; hence the use of `#define` or 32-bit `int` is preferred.
3. **Struct Returns**: While supported, returning large structs by value can be inefficient. The compiler will prioritize small result types or out-parameters.
4. **Keyword Collisions**: Generated error constants will be prefixed with `ERROR_` to avoid collisions with C keywords or user-defined identifiers.

## Existing Detection Infrastructure
The bootstrap compiler already detects and catalogues these features for rejection in Pass 1, while preserving metadata for this mapping strategy.

### Lexer Support
- `TOKEN_BANG`: Recognizes `!` for error unions.
- `TOKEN_PIPE_PIPE`: Recognizes `||` for error set merging.
- `TOKEN_TRY`, `TOKEN_CATCH`, `TOKEN_ORELSE`: Recognizes error handling keywords.
- `TOKEN_ERROR`: Recognizes the `error` keyword for set definitions.

### Parser Support
- `parseErrorSetDefinition()`: Detects `error { A, B }`.
- `parseErrorUnionType()`: Detects `!T` and `error{A}!T`.
- `parseTryExpression()`: Handles `try expr`.
- `parseCatchExpression()`: Handles `expr catch expr` and `expr catch |err| expr`.
- `parseOrelseExpression()`: Handles `expr orelse expr`.

### Detection Catalogues (Arena Allocated)
- **`ErrorSetCatalogue`**: Tracks all error set definitions, their tags, and source locations.
- **`ErrorFunctionCatalogue`**: Identifies all functions that return error unions or error sets.
- **`TryExpressionCatalogue`**: Logs every `try` site, including usage context (e.g., `assignment`, `return`) and nesting depth.
- **`CatchExpressionCatalogue`**: Logs `catch` expressions, capturing handler types, chaining information, and error parameter names.
- **`OrelseExpressionCatalogue`**: Logs `orelse` usage, including payload and fallback types.

## Error Set Merging
Zig allows merging error sets: `const AllErrors = Errors1 || Errors2;`.
The mapping strategy handles this by using the **Global Error Registry**. Since every tag has a unique global integer ID, a merged set is simply a collection of these global IDs. In C89, any function returning `AllErrors` can return any ID belonging to either `Errors1` or `Errors2`.

## Anonymous Error Sets
Functions can return anonymous error sets: `fn f() error{A, B}!void`.
The compiler treats these tags exactly like named ones, registering `A` and `B` in the global registry if they haven't been seen before.

## Success Value Extraction Strategy

### Memory Layout Options
1. **Out-parameter approach**: Function returns error code, success via pointer.
2. **Struct return approach**: Return `Errorable_T` struct (CHOSEN).
3. **Tagged union approach**: Union with error/success discriminant.

### Chosen Approach: Errorable<T> Struct
The compiler generates a specialized struct for each unique error union type encountered.

```c
typedef struct {
    union {
        T success_value;
        int error_code;
    } data;
    int is_error;  /* 0 = success, 1 = error (bool not in C89) */
} Errorable_T;
```

### Type-Specific Macros
To maintain C89 compatibility and avoid template-like overhead, the compiler utilizes per-type definitions:

```c
#define DECLARE_ERRORABLE(TYPE, NAME) \
    typedef struct { \
        union { TYPE success_value; int error_code; } data; \
        int is_error; \
    } Errorable_##NAME

DECLARE_ERRORABLE(int32_t, int32);
DECLARE_ERRORABLE(void*, ptr);
```

### Memory Allocation Strategy
- **Small `Errorable_T` structs (< 64 bytes)**: Stack allocated as automatic variables during expression evaluation.
- **Large `Errorable_T` structs (>= 64 bytes)**: Allocated from the `ArenaAllocator` if they need to persist or to avoid excessive stack usage.
- **MSVC 6.0 Stack Limits**: MSVC 6.0 has a 64KB stack frame limit. Large `Errorable_T` structs (> 1KB) should use arena allocation to avoid stack overflow.

### MSVC 6.0 Alignment Constraints
To ensure correct layout on 1990s hardware, the compiler may emit alignment pragmas:

```c
#pragma pack(push, 4)  /* Ensure 4-byte alignment */
typedef struct {
    union {
        double dbl_value;   /* 8 bytes */
        int error_code;     /* 4 bytes */
    } data;
    int is_error;           /* 4 bytes */
} Errorable_double;         /* Total: 12 bytes */
#pragma pack(pop)
```

### Success Value Extraction Patterns

#### Pattern 1: Variable Assignment
**Zig:** `var x = try mightFail();`
**C89:**
```c
Errorable_int32 temp = mightFail();
if (temp.is_error) {
    return temp; /* Propagate */
}
int32_t x = temp.data.success_value;
```

#### Pattern 2: Direct Use in Expressions
**Zig:** `process(try getValue());`
**C89:**
```c
Errorable_int32 temp = getValue();
if (temp.is_error) return temp;
process(temp.data.success_value);
```

### Edge Cases

#### 1. Large Success Types
When `T` is a large struct (e.g., 64+ bytes), the `Errorable_T` struct stores the success value directly by value in the union to maintain simple semantics, but uses arena allocation for the temporary if necessary.

#### 2. Nested Error Unions
**Zig:** `fn doubleError() !!void { ... }`
**C89:** Translated as an `Errorable` struct where the success value is itself an `Errorable` struct.

#### 3. Void Success Values
**Zig:** `fn mightFail() !void { ... }`
**C89:** `Errorable_void` contains a union where the success path has no associated data, only the `is_error` flag is checked.

### MSVC 6.0 Union Initialization
MSVC 6.0 does not support C99 designated initializers. Generated code must perform manual initialization:

```c
Errorable_int32 result;
result.is_error = 0;
result.data.success_value = 42;
```
