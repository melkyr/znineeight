# Template Instantiation Detection (Bootstrap - Task 155)

## Overview
The bootstrap compiler detects and rejects Zig template/generic features as non-C89 compatible.

## What We Detect

### 1. Generic Function Definitions
- `fn foo(comptime T: type, x: T) T` - Type parameters
- `fn bar(anytype x) void` - Type inference
- `fn baz(comptime n: i32) void` - Compile-time parameters

### 2. Generic Function Calls
- Explicit: `function(i32, value)` - Type argument present
- Implicit: Calls to known generic functions (catalogued)

## How We Detect

### Simple Pattern Matching
No complex type resolution needed. We check:

1. **In definitions**: Look for `: type` or `anytype` or `comptime` in parameters. The `Parser` identifies these and marks the function as generic.
2. **In calls**: Look for type expressions as arguments (explicit) or check if the callee is marked as generic in the symbol table or `GenericCatalogue` (implicit).

### Example Detection Code
```cpp
// In C89FeatureValidator::visitFunctionCall
for (size_t i = 0; i < call->args->length(); ++i) {
    if (isTypeExpression((*call->args)[i], unit.getSymbolTable())) {
        reportNonC89Feature(node->loc, "Generic function calls (with type arguments) are not C89-compatible.");
        break;
    }
}
```

## Bootstrap Limitations
We do NOT:
- Resolve type parameters
- Track instantiation chains
- Implement type inference
- Generate specialized code

## Rejection Messages
- "Generic functions are not supported in C89 mode."
- "Generic function calls (with type arguments) are not C89-compatible."
- "Calls to generic functions are not C89-compatible."
- "anytype parameters are not supported in C89 mode"
- "type parameters are not supported in C89 mode"

## Why This Approach
The bootstrap compiler's job is to:
1. **Detect** non-C89 features
2. **Reject** them with clear errors
3. **Document** what was rejected

Full generic support is deferred to Milestone 5.

## Test Strategy
Tests verify that:
1. Generic syntax is parsed
2. Generic features are rejected
3. Error messages are clear
