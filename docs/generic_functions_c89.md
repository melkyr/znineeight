# Generic Function Detection (Task 154)

## Overview
Zig supports generic functions through `comptime`, `anytype`, and `type` parameters. These are not compatible with C89 and are strictly rejected in the bootstrap phase.

## Detected Generic Patterns

### 1. Comptime Parameters
```zig
fn generic(comptime T: type, value: T) T {
    return value;
}
```

### 2. Anytype Parameters
```zig
fn printAny(anytype value) void {
    // Type inferred at call site
}
```

### 3. Type Parameters
```zig
fn makePointer(T: type) *T {
    // Returns pointer to type T
}
```

## Bootstrap Compiler Response
- **Detect**: Parser identifies generic function definitions by looking for `comptime` or `anytype` prefixes, or parameters of type `type`.
- **Catalogue**: Recorded in `GenericCatalogue` for documentation and future mapping strategies.
- **Reject**: `C89FeatureValidator` reports a fatal error "Generic functions are not supported in C89 mode." and stops compilation.

## C89 Compatibility
Generic functions cannot be directly translated to C89 because:
1. C89 has no compile-time type parameters.
2. No equivalent to `anytype` (type inference).
3. No `comptime` execution model.
4. Templates/generics don't exist in C89.

## Milestone 5 Considerations
For a full Zig compiler, generic functions would require:
1. Template instantiation at compile time.
2. Type checking for each instantiation.
3. Separate code generation for each type.
4. Name mangling for different instantiations.

## Examples

### Detected and Rejected
```zig
// All of these are rejected in C89 mode
fn generic1(comptime T: type, x: T) T { return x; }
fn generic2(anytype x) void {}
fn generic3(x: type) void {}
```

### Allowed (Non-Generic)
```zig
// Regular functions are allowed
fn add(a: i32, b: i32) i32 { return a + b; }
```
