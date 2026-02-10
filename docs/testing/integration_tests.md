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
- `test_compilation_unit.hpp`: A specialized subclass of `CompilationUnit` that provides access to the AST and internal metadata for validation.

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
