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
