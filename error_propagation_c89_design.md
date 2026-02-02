# Error Propagation C89 Design (Task 147)

## Overview
Zig's error handling features cannot be directly translated to C89. This document outlines the alternative patterns for Milestone 5, ensuring compatibility with 1998-era compilers like MSVC 6.0.

## Rejected Zig Features
The following features are detected and rejected by the bootstrap compiler:
- `try expr` - Error propagation operator
- `catch expr` - Error handling operator
- `errdefer stmt` - Error-only cleanup
- `!T` - Error union types
- `error{A,B}` - Error sets
- `anyerror` - Universal error type
- `error.Tag` - Error tag access

## C89-Compatible Alternatives

### 1. Error Representation
Error unions `!T` will be represented as structs containing a union for the payload and error code, plus a boolean flag.

```c
/* Zig: !i32 */
/* C89 Alternative: */
typedef struct {
    union {
        int32_t value;
        int error_code;
    } data;
    int is_error;  /* Use int (0/1) for MSVC 6.0 compatibility */
} ErrorableInt;

#define SUCCESS 0
#define ERROR_FILE_NOT_FOUND 1
#define ERROR_PERMISSION_DENIED 2
```

### 2. Basic Error Return Pattern
Functions returning errors will return the `Errorable` struct by value.

```c
/* Zig: fn read() !i32 */
ErrorableInt read(void) {
    ErrorableInt result;
    memset(&result, 0, sizeof(result));

    if (/* failure condition */) {
        result.is_error = 1;
        result.data.error_code = ERROR_FILE_NOT_FOUND;
    } else {
        result.is_error = 0;
        result.data.value = 42;
    }

    return result;
}
```

### 3. Try Expression Translation
The `try` operator is expanded into an explicit check and early return.

```c
/* Zig: var x = try read(); */
/* C89 Alternative: */
ErrorableInt temp = read();
if (temp.is_error) {
    /* Propagate error to caller */
    ErrorableInt err_ret;
    memset(&err_ret, 0, sizeof(err_ret));
    err_ret.is_error = 1;
    err_ret.data.error_code = temp.data.error_code;
    return err_ret;
}
int x = temp.data.value;
```

### 4. Catch Expression Translation
The `catch` operator is translated using the ternary operator or an `if` block.

```c
/* Zig: var x = read() catch 0; */
/* C89 Alternative: */
ErrorableInt temp = read();
int x = temp.is_error ? 0 : temp.data.value;
```

### 5. Errdefer Alternative
Zig's `errdefer` is implemented using `goto` and a cleanup label.

```c
/* Zig: errdefer cleanup(); */
/* C89 Alternative: */
ErrorableInt operation(void) {
    Resource* res = acquire_resource();
    ErrorableInt result;

    result = do_work(res);
    if (result.is_error) {
        goto cleanup;
    }

    /* Success path */
    result = do_more_work(res);
    if (result.is_error) {
        goto cleanup;
    }

    /* Normal exit */
    return result;

cleanup:
    /* Error-only cleanup */
    release_resource(res);
    return result;
}
```

## MSVC 6.0 Specific Constraints
1.  **No `stdbool.h`**: Use `int` with `0` for `false` and `1` for `true`.
2.  **Limited stack**: Functions with large error union structs (> 256 bytes) or deep nesting will use `EXTRACTION_ARENA` strategy.
3.  **4-byte alignment**: MSVC 6.0 cannot guarantee 8-byte alignment on the stack. Payloads requiring > 4-byte alignment force Arena allocation.
4.  **32-bit Error Codes**: All error tags are mapped to 32-bit integers via `#define`.
5.  **No `alloca()`**: Dynamic stack allocation is avoided for stability.

## Memory Strategy
-   **Small Payloads (< 32 bytes)**: Stored directly on the stack (`EXTRACTION_STACK`).
-   **Large Payloads or Deep Nesting**: Managed via the `CompilationUnit`'s `ArenaAllocator` (`EXTRACTION_ARENA`).
-   **Complex Returns**: Uses the out-parameter pattern where the caller provides a pointer to the result structure (`EXTRACTION_OUT_PARAM`).

## Performance Considerations
1.  **Struct Return**: Returning structures by value may incur copying overhead; mitigated by compiler optimizations or out-parameters.
2.  **Arena Allocation**: Fast O(1) allocation, but requires careful lifecycle management via the `CompilationUnit`.
3.  **Stack Pressure**: Conservative limits on stack usage prevent overflows on legacy systems with small default stacks.
