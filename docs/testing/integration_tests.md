# Integration Testing in RetroZig

Integration tests in RetroZig verify that multiple components of the compiler (Lexer, Parser, TypeChecker, and Validator) work together correctly. Unlike unit tests which focus on individual functions or classes, integration tests process small Zig source snippets through the full compilation pipeline.

## Philosophy

Integration tests are designed to:
1. **Verify End-to-End Flow**: Ensure that tokens produced by the Lexer are correctly consumed by the Parser, and the resulting AST is properly handled by semantic analysis passes.
2. **Validate Type Mapping**: Confirm that Zig language constructs are mapped to the correct bootstrap types and that these types are C89-compatible.
3. **Mocks for Future Stages**: Use mock components (like `MockC89Emitter`) to simulate future compiler stages (like Milestone 5 Codegen) and validate that the current stages produce all necessary metadata.
4. **Environment Independence**: Run without dependencies on external C compilers or libraries, focusing on internal consistency and metadata generation.

## Test Organization

Integration tests are located in `tests/integration/`. They are typically grouped by feature:

- `literal_tests.cpp`: Tests for all literal types (integers, floats, characters, strings, booleans, null).
- `variable_decl_tests.cpp`: Tests for variable and constant declarations, including type inference, scoping, and name mangling.
- `test_compilation_unit.hpp`: A specialized subclass of `CompilationUnit` that provides access to the AST and internal metadata for validation.

## Variable Declaration Tests (Task 171)

Variable declaration tests verify that Zig `var` and `const` declarations are correctly mapped to C89.

### Test Categories:
1. **Basic Declarations**: `var`, `const` with explicit types.
2. **Type Inference**: Variables without explicit types (inferring type from literal).
3. **Name Mangling**: Verification that C89 keyword conflicts (e.g., `var int: i32`) are resolved by the mangler (e.g., `int z_int`).
4. **Scope Testing**: Coverage for both global and local (function-scope) variables.
5. **Negative Tests**: Verification that duplicate names in the same scope or unsupported bootstrap types (like slices) are rejected.

### Expected C89 Output Patterns:
- Zig `var x: i32 = 42;` -> C `int x = 42;`
- Zig `const y: f64 = 3.14;` -> C `const double y = 3.14;`
- Zig `var int: i32 = 0;` -> C `int z_int = 0;` (mangled because `int` is a C keyword)

## Adding New Integration Tests

To add a new integration test:

1. **Write the Zig Source**: Define a small snippet of Zig code that exercises the feature.
2. **Use `TestCompilationUnit`**: Run the source through the pipeline.
3. **Extract Nodes**: Use the helper methods in `TestCompilationUnit` (e.g., `extractTestExpression`) to find the AST nodes you want to validate.
4. **Assert Types**: Verify `node->resolved_type` matches expectations.
5. **Assert Emission**: Use `MockC89Emitter` to verify the C89 string representation.

Example:
```cpp
TEST_FUNC(LiteralIntegration_IntegerDecimal) {
    return run_literal_test("fn foo() i32 { return 42; }", TYPE_I32, "42");
}
```

## Mock C89 Emitter

The `MockC89Emitter` (in `tests/integration/mock_emitter.hpp`) is a temporary utility for Milestone 4. It translates AST literal nodes into C89 string representations following the rules defined in `Bootstrap_type_system_and_semantics.md`.

It will be replaced by the real `C89Emitter` in Milestone 5, but the integration tests will remain to ensure the frontend continues to produce the correct AST and types for the backend.

## Arithmetic Expression Tests (Task 172)

Arithmetic expression tests verify that Zig expressions involving operators are correctly parsed, typed, and mapped to C89.

### Operator Mapping (Zig -> C89):

| Zig Operator | C89 Operator | Category |
|--------------|--------------|----------|
| `+`, `-`, `*`, `/`, `%` | `+`, `-`, `*`, `/`, `%` | Arithmetic |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | `==`, `!=`, `<`, `<=`, `>`, `>=` | Comparison |
| `and`, `or`, `!` | `&&`, `||`, `!` | Logical |
| `-` (unary) | `-` | Unary |

### Test Categories:
1. **Integer Arithmetic**: Basic operations with `i32` and literal promotion.
2. **Floating-Point**: Operations with `f64`.
3. **Comparisons**: Relational and equality operators returning `bool`.
4. **Logical Operations**: Boolean logic with `and`, `or`, and `!`.
5. **Precedence & Parentheses**: Explicit grouping with `()` to ensure correct evaluation order.
6. **Negative Tests**: Type mismatches (e.g., mixing `i32` and `f64` without casts) and invalid operations (e.g., modulo on floats).

### Expected C89 Output Patterns:
- Zig `1 + 2` -> C `1 + 2`
- Zig `true and false` -> C `1 && 0` (bool mapped to 0/1)
- Zig `(1 + 2) * 3` -> C `(1 + 2) * 3`

## Function Declaration Tests (Task 173)

Function declaration tests verify that Zig function signatures and names are correctly handled, including mangling and bootstrap constraints.

### Test Categories:
1. **Basic Signatures**: Functions with 0 to 4 parameters.
2. **Type Mapping**: Correct translation of parameter and return types (e.g., `*const u8` -> `const unsigned char*`).
3. **Name Mangling**:
   - C keywords (e.g., `fn if()` -> `void z_if(void)`).
   - Long names (truncated to 31 characters).
4. **Scoping**: Forward references and mutual recursion support.
5. **Negative Tests**:
   - Parameter count limit (rejecting 5+ parameters).
   - Invalid bootstrap types (slices, error unions, multi-level pointers).
   - Duplicate function names in the same scope.

### Expected C89 Output Patterns:
- Zig `fn foo() void` -> C `void foo(void)`
- Zig `fn if() void` -> C `void z_if(void)`
- Zig `fn test(p: *i32) *f64` -> C `double* test(int* p)`

## Function Call Tests (Task 174)

Function call tests verify that calls to Zig functions are correctly resolved, argument types are checked, and mangled names are used in the generated C89 output.

### Test Categories:
1. **Simple Calls**: 0-4 arguments, various return types (void, i32, f64, pointers).
2. **Nested Calls**: Functions used as arguments to other functions (e.g., `foo(bar())`).
3. **Name Mangling**: Verification that calls to functions with C keyword names (e.g., `int()`) use the mangled name (e.g., `z_int()`).
4. **Void Statements**: Verification that void-returning functions can be called as standalone statements.
5. **Call Resolution**: Direct verification of the `CallSiteLookupTable` entries.
6. **Negative Tests**:
   - Argument count limit (rejecting 5+ arguments).
   - Type mismatches (passing incompatible types to parameters).
   - Undefined functions (calling a function that hasn't been declared).
   - Function pointers (rejecting indirect calls via variables in bootstrap).

### Expected C89 Output Patterns:
- Zig `add(1, 2)` -> C `add(1, 2)` (Note: mangling depends on whether it's generic or a keyword)
- Zig `int()` -> C `z_int()`
- Zig `outer(inner())` -> C `outer(inner())`

## If Statement Tests (Task 175)

If statement tests verify that Zig `if` and `else` blocks are correctly parsed, condition types are validated, and the resulting control flow is correctly mapped to C89.

### Test Categories:
1. **Condition Types**:
   - **Boolean**: `if (b) { ... }`
   - **Integer**: `if (x) { ... }` (non-zero treated as true)
   - **Pointer**: `if (ptr) { ... }` (non-null treated as true)
2. **If-Else**: Basic `if (cond) { ... } else { ... }` structure.
3. **Else-If Chains**: Support for `else if` chains (e.g., `if (a) { } else if (b) { } else { }`).
4. **Nesting**: Nested `if` statements within `then` or `else` blocks.
5. **Complex Conditions**: Conditions using logical operators (`and`, `or`, `!`) and comparisons.
6. **Negative Tests**:
   - **Invalid Conditions**: Rejecting floats, structs, or void conditions.
   - **Syntax Enforcement**: Rejecting braceless `if` statements (the bootstrap parser requires braces for all blocks).

### Expected C89 Output Patterns:
- Zig `if (b) { }` -> C `if (b) { }`
- Zig `if (x > 0) { return 1; } else { return 0; }` -> C `if (x > 0) { return 1; } else { return 0; }`
- Zig `if (a) { } else if (b) { }` -> C `if (a) { } else if (b) { }`

## While Loop Tests (Task 176)

While loop tests verify that Zig `while` loops are correctly parsed, condition types are validated, and the resulting control flow (including `break` and `continue`) is correctly mapped to C89.

### Test Categories:
1. **Condition Types**:
   - **Boolean**: `while (flag) { ... }`
   - **Integer**: `while (count) { ... }` (non-zero treated as true)
   - **Pointer**: `while (ptr) { ... }` (non-null treated as true)
2. **Break and Continue**: Basic support for `break;` and `continue;` statements.
3. **Nesting**: Nested `while` loops and their interaction with scoping.
4. **Scoping**: Verification that variables declared within the loop body are correctly scoped (using `MockC89Emitter`'s symbol table support).
5. **Complex Conditions**: Conditions using logical operators (`and`, `or`, `!`) and comparisons.
6. **Negative Tests**:
   - **Invalid Conditions**: Rejecting floats, structs, or void conditions.
   - **Syntax Enforcement**: Rejecting braceless `while` loops.

### Expected C89 Output Patterns:
- Zig `while (true) { break; }` -> C `while (1) { break; }`
- Zig `while (i < 10) { i = i + 1; continue; }` -> C `while (i < 10) { i = i + 1; continue; }`
- Zig `while (ptr) { ptr = null; }` -> C `while (ptr) { ptr = ((void*)0); }`

## Pointer Operation Tests (Task 178)

Pointer operation tests verify that Zig pointer operations are correctly parsed, typed, and mapped to C89, while also validating the safety analyzers (Lifetime and Null Pointer).

### Test Categories:
1. **Address-of and Dereference**: `&x` (address-of) and `ptr.*` (dereference).
2. **Pointer Arithmetic**:
   - `ptr + integer` / `integer + pointer` -> `ptr`
   - `ptr - integer` -> `ptr`
   - `ptr1 - ptr2` -> `isize` (Note: `isize` is rejected in bootstrap but handled by TypeChecker).
3. **Null Pointers**: `null` literal, pointer comparison with `null`, and assignment.
4. **Pointer-to-Struct**: Accessing members through pointers (e.g., `ptr.field` -> `ptr->field`).
5. **Type Compatibility**:
   - Implicit conversion from `*T` to `*void`.
   - Const-adding conversions (e.g., `*i32` to `*const i32`).
6. **Negative Tests**:
   - **LifetimeAnalyzer**: Returning the address of a local variable or parameter.
   - **NullPointerAnalyzer**: Dereferencing a pointer that is definitely `null`.
   - **Invalid Arithmetic**: Adding two pointers or adding a float to a pointer.
   - **Invalid Dereference**: Attempting to dereference a non-pointer type.
   - **Address-of Non-LValue**: Attempting to take the address of a temporary expression like `&(1 + 2)`.

### Expected C89 Output Patterns:
- Zig `&x` -> C `&x`
- Zig `ptr.*` -> C `*ptr`
- Zig `ptr.field` -> C `ptr->field` (when `ptr` is a pointer)
- Zig `null` -> C `((void*)0)`
- Zig `ptr + 1` -> C `ptr + 1`
