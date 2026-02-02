# Error Handling Validation Rules

## Overview
This document lists validation rules for Zig error handling features.
These rules are NOT implemented in the bootstrap compiler (which rejects all error handling as non-C89),
but will be needed for the full compiler in Milestone 5.

## Validation Rules by Feature

### 1. Try Expressions (`try expr`)
**Zig Semantics:**
- `expr` must be of type `!T` (error union)
- `try` can only be used in a function that returns an error union, or inside a `catch` block
- Nested `try` expressions are allowed

**C89 Impact:**
- Determines error propagation strategy (stack vs arena vs out-parameter)
- Influences function signature in generated C89

### 2. Catch Expressions (`expr catch handler`)
**Zig Semantics:**
- `expr` must be of type `!T`
- `handler` must return type `T` (payload type)
- Optional error capture: `expr catch |err| handler`
- Chaining allowed: `expr catch handler1 catch handler2`

**C89 Impact:**
- Determines fallback generation pattern
- Error capture requires local variable in C89

### 3. Orelse Expressions (`expr orelse default`)
**Zig Semantics:**
- `expr` must be optional type `?T` or error union type `!T`
- `default` must return type `T`
- Short-circuits on null/error

**C89 Impact:**
- Optional types require different representation than error unions
- Fallback must be evaluated only if needed

### 4. Errdefer Statements (`errdefer stmt`)
**Zig Semantics:**
- Only executes if function returns via error path
- Must be in function returning error union
- Executes in reverse order of declaration

**C89 Impact:**
- Requires `goto`-based cleanup in C89
- Error flag must be checked before cleanup

### 5. Error Sets and Unions
**Zig Semantics:**
- Error union `!T` has distinct type from `T`
- Error sets can be merged: `E1 || E2`
- Global error access: `error.TagName`

**C89 Impact:**
- Error unions map to structs with union
- Error codes map to integer constants
- Set merging requires union of all error codes

## C89-Specific Validation Rules

### Stack Safety Rules
1. Error union structs > 256 bytes cannot use stack return pattern
2. Alignment > 4 bytes requires arena allocation
3. Deep nesting (>8 levels) reduces stack threshold to 32 bytes

### Memory Management Rules
1. Arena-allocated error unions must be freed
2. Out-parameter patterns must initialize output parameters
3. Struct return patterns must fit in register or stack

### MSVC 6.0 Constraints
1. No `stdbool.h` - use `int` with 0/1 for boolean flags
2. Maximum 4-byte alignment for stack variables
3. Conservative stack usage (50% of theoretical limit)
4. No `alloca()` for dynamic stack allocation

## Implementation Notes for Milestone 5

These rules will be implemented in:
1. **Semantic Validator**: Check Zig correctness
2. **C89 Compatibility Validator**: Check translation feasibility
3. **Pattern Selector**: Choose appropriate C89 pattern
4. **Code Generator**: Enforce rules during translation

## Test Cases Needed

### Positive Cases (Valid Zig):
```zig
fn valid() !i32 {
    const x = try mightFail();
    const y = mightFail() catch 0;
    errdefer cleanup();
    return x + y;
}
```

### Negative Cases (Invalid for C89):
```zig
// Too large for stack return
fn tooLarge() ![4096]u8 { ... }

// Alignment incompatible
fn badAlign() !Aligned64 { ... }

// Complex pattern we choose not to support
fn nestedTry() !i32 {
    return try (try a() + try b());
}
```
