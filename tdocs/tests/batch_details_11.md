# Z98 Test Batch 11 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 30 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_Milestone4_Lexer_Tokens`
- **Implementation Source**: `tests/test_milestone4_lexer_parser.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
!i32 ?u8 error{A} E1 || E2 @import
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `t.type` matches `TOKEN_BANG`
  2. Assert that `t.type` matches `TOKEN_IDENTIFIER`
  3. Assert that `t.type` matches `TOKEN_QUESTION`
  4. Assert that `t.type` matches `TOKEN_ERROR_SET`
  5. Assert that `t.type` matches `TOKEN_LBRACE`
  6. Assert that `t.type` matches `TOKEN_RBRACE`
  7. Assert that `t.type` matches `TOKEN_PIPE_PIPE`
  8. Assert that `t.type` matches `TOKEN_AT_IMPORT`
  9. Assert that `t.type` matches `TOKEN_EOF`
  ```

### `test_Milestone4_Parser_AST`
- **Implementation Source**: `tests/test_milestone4_lexer_parser.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `type.type` matches `NODE_ERROR_UNION_TYPE`
  2. Validate that `type.as.error_union_type.error_set equals null` is satisfied
  3. Assert that `type.as.error_union_type.payload_type.type` matches `NODE_TYPE_NAME`
  4. Assert that `type.type` matches `NODE_OPTIONAL_TYPE`
  5. Assert that `type.as.optional_type.payload_type.type` matches `NODE_TYPE_NAME`
  6. Assert that `type.type` matches `NODE_ERROR_SET_MERGE`
  7. Assert that `type.as.error_set_merge.left.type` matches `NODE_TYPE_NAME`
  8. Assert that `type.as.error_set_merge.right.type` matches `NODE_TYPE_NAME`
  ```

### `test_OptionalType_Creation`
- **Implementation Source**: `tests/test_optional_type.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `opt_type not equals null` is satisfied
  2. Assert that `kind of opt_type` matches `TYPE_OPTIONAL`
  3. Validate that `opt_type.as.optional.payload equals base_type` is satisfied
  4. Assert that `opt_type.size` matches `8`
  5. Assert that `opt_type.alignment` matches `4`
  ```

### `test_OptionalType_ToString`
- **Implementation Source**: `tests/test_optional_type.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_OptionalType_ToString and validate component behavior
  ```

### `test_TypeChecker_OptionalType`
- **Implementation Source**: `tests/test_optional_type_checker.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: ?i32 = null;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `var_decl_node.type` matches `NODE_VAR_DECL`
  2. Validate that `sym not equals null` is satisfied
  3. Validate that `sym.symbol_type not equals null` is satisfied
  4. Assert that `sym.kind of symbol_type` matches `TYPE_OPTIONAL`
  5. Assert that `sym.symbol_type.as.optional.kind of payload` matches `TYPE_I32`
  ```

### `test_NameMangler_Milestone4Types`
- **Implementation Source**: `tests/test_milestone4_name_mangling.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
, mangler.mangleType(optional_type));

    // Error Set: error{A, B} -> errset_A_B
    DynamicArray<const char*>* tags = new (arena.alloc(sizeof(DynamicArray<const char*>))) DynamicArray<const char*>(arena);
    tags->append(interner.intern(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_NameMangler_Milestone4Types and validate component behavior
  ```

### `test_CallSiteLookupTable_Basic`
- **Implementation Source**: `tests/test_call_site_lookup.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
, CALL_DIRECT);
    ASSERT_EQ(0, table.getUnresolvedCount());
    ASSERT_EQ(true, table.getEntry(id).resolved);
    // Use plat_strcmp for C++98 compatibility and avoidance of <cstring>
    ASSERT_TRUE(plat_strcmp(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `table.count` matches `1`
  2. Assert that `table.getUnresolvedCount` matches `1`
  3. Assert that `table.getUnresolvedCount` matches `0`
  4. Assert that `table.getEntry(id` matches `true`
  5. Validate that `plat_strcmp("mangled_foo", table.getEntry(id` is satisfied
  6. Assert that `table.getEntry(id` matches `CALL_DIRECT`
  ```

### `test_CallSiteLookupTable_Unresolved`
- **Implementation Source**: `tests/test_call_site_lookup.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `table.getUnresolvedCount` matches `1`
  2. Assert that `table.getEntry(id` matches `false`
  3. Validate that `plat_strcmp("Function pointer", table.getEntry(id` is satisfied
  4. Assert that `table.getEntry(id` matches `CALL_INDIRECT`
  ```

### `test_TypeChecker_CallSiteRecording_Direct`
- **Implementation Source**: `tests/type_checker_call_site_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
fn main() void { foo(); }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `1`
  4. Assert that `table.getUnresolvedCount` matches `0`
  5. Validate that `plat_strcmp(entry.context, "main"` is satisfied
  6. Assert that `entry.call_type` matches `CALL_DIRECT`
  7. Validate that `entry.mangled_name not equals null` is satisfied
  ```

### `test_TypeChecker_CallSiteRecording_Recursive`
- **Implementation Source**: `tests/type_checker_call_site_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn factorial(n: i32) i32 {
    if (n <= 1) { return 1; }
    return n * factorial(n - 1);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `1`
  4. Assert that `table.getUnresolvedCount` matches `0`
  5. Validate that `plat_strcmp(entry.context, "factorial"` is satisfied
  6. Assert that `entry.call_type` matches `CALL_RECURSIVE`
  ```

### `test_TypeChecker_CallSiteRecording_Generic`
- **Implementation Source**: `tests/type_checker_call_site_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn identity(comptime T: type, x: T) T { return x; }
fn main() void {
    identity(i32, 42);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `table.count` is satisfied
  3. Assert that `entry.call_type` matches `CALL_GENERIC`
  4. Validate that `entry.resolved` is satisfied
  5. Validate that `entry.mangled_name not equals null` is satisfied
  6. Validate that `found` is satisfied
  ```

### `test_Task165_ForwardReference`
- **Implementation Source**: `tests/test_task_165_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void { foo(); }
fn foo() void {}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `1`
  4. Assert that `table.getUnresolvedCount` matches `0`
  5. Assert that `entry.call_type` matches `CALL_DIRECT`
  6. Validate that `entry.resolved` is satisfied
  7. Validate that `entry.mangled_name not equals null` is satisfied
  ```

### `test_Task165_BuiltinRejection`
- **Implementation Source**: `tests/test_task_165_resolution.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Task165_BuiltinRejection and validate component behavior
  ```

### `test_Task165_C89Incompatible`
- **Implementation Source**: `tests/test_task_165_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn takeIncompatible(e: test_incompatible) void {}
fn main() void { takeIncompatible(undefined); }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `table.count` is satisfied
  3. Validate that `found_incompatible` is satisfied
  ```

### `test_IndirectCall_Variable`
- **Implementation Source**: `tests/test_indirect_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
const fp = foo;
fn main() void { fp(); }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `catalogue.count` matches `1`
  4. Assert that `catalogue.get(0` matches `INDIRECT_VARIABLE`
  ```

### `test_IndirectCall_Member`
- **Implementation Source**: `tests/test_indirect_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: fn() void };
fn main() void {
    var s: S = undefined;
    s.f();
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `catalogue.count` matches `1`
  4. Assert that `catalogue.get(0` matches `INDIRECT_MEMBER`
  ```

### `test_IndirectCall_Array`
- **Implementation Source**: `tests/test_indirect_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const funcs: [2]fn() void = undefined;
fn main() void {
    funcs[0]();
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `catalogue.count` matches `1`
  4. Assert that `catalogue.get(0` matches `INDIRECT_ARRAY`
  ```

### `test_IndirectCall_Returned`
- **Implementation Source**: `tests/test_indirect_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn getFunc() fn() void { return undefined; }
fn main() void {
    getFunc()();
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `catalogue.count` matches `1`
  4. Assert that `catalogue.get(0` matches `INDIRECT_RETURNED`
  ```

### `test_IndirectCall_Complex`
- **Implementation Source**: `tests/test_indirect_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {}
fn main() void {
    (switch (0) { else => foo })();
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `catalogue.count` matches `1`
  4. Assert that `catalogue.get(0` matches `INDIRECT_COMPLEX`
  ```

### `test_ForwardReference_GlobalVariable`
- **Implementation Source**: `tests/test_forward_reference.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() i32 { return x; }
const x: i32 = 42;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  ```

### `test_ForwardReference_MutualFunction`
- **Implementation Source**: `tests/test_forward_reference.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn a() void { b(); }
fn b() void { a(); }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  ```

### `test_ForwardReference_StructType`
- **Implementation Source**: `tests/test_forward_reference.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const p: Point = Point { .x = 1, .y = 2 };
const Point = struct { x: i32, y: i32 };

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  ```

### `test_Recursive_Factorial`
- **Implementation Source**: `tests/test_recursive_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn factorial(n: i32) i32 {
    if (n <= 1) { return 1; }
    return n * factorial(n - 1);
}
fn main() void {
    var x: i32 = factorial(5);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `2`
  4. Assert that `entry.call_type` matches `CALL_RECURSIVE`
  5. Validate that `entry.mangled_name not equals null` is satisfied
  6. Assert that `entry.call_type` matches `CALL_DIRECT`
  7. Validate that `found_recursive` is satisfied
  8. Validate that `found_direct` is satisfied
  ```

### `test_Recursive_Mutual_Mangled`
- **Implementation Source**: `tests/test_recursive_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn isEven(n: i32) bool {
    if (n == 0) { return true; }
    return isOdd(n - 1);
}
fn isOdd(n: i32) bool {
    if (n == 0) { return false; }
    return isEven(n - 1);
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `2`
  4. Assert that `entry.call_type` matches `CALL_DIRECT`
  5. Validate that `found_isEven_call` is satisfied
  6. Validate that `found_isOdd_call` is satisfied
  ```

### `test_Recursive_Forward_Mangled`
- **Implementation Source**: `tests/test_recursive_calls.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn start() void { later(); }
fn later() void { start(); }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Assert that `table.count` matches `2`
  4. Assert that `entry.call_type` matches `CALL_DIRECT`
  5. Validate that `found_start_call` is satisfied
  6. Validate that `found_later_call` is satisfied
  ```

### `test_CallSyntax_AtImport`
- **Implementation Source**: `tests/test_call_syntax.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const std = @import(\
  ```
  ```zig
, source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    ASSERT_TRUE(ast != NULL);
    ASSERT_EQ(NODE_BLOCK_STMT, ast->type);
    ASSERT_EQ(1, ast->as.block_stmt.statements->length());

    ASTNode* stmt = (*ast->as.block_stmt.statements)[0];
    ASSERT_EQ(NODE_VAR_DECL, stmt->type);

    ASTNode* init = stmt->as.var_decl->initializer;
    ASSERT_TRUE(init != NULL);

    // Check if it's NODE_IMPORT_STMT
    ASSERT_EQ(NODE_IMPORT_STMT, init->type);
    ASSERT_STREQ(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Assert that `ast.type` matches `NODE_BLOCK_STMT`
  3. Assert that `ast.as.block_stmt.statements.length` matches `1`
  4. Assert that `stmt.type` matches `NODE_VAR_DECL`
  5. Validate that `init not equals null` is satisfied
  6. Assert that `init.type` matches `NODE_IMPORT_STMT`
  ```

### `test_CallSyntax_AtImport_Pipeline`
- **Implementation Source**: `tests/test_call_syntax.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const std = @import(\
  ```
  ```zig
);
    if (f) {
        fprintf(f,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  ```

### `test_CallSyntax_ComplexPostfix`
- **Implementation Source**: `tests/test_call_syntax.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void { a().b().c(); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Assert that `fn_decl.type` matches `NODE_FN_DECL`
  3. Assert that `body.type` matches `NODE_BLOCK_STMT`
  4. Assert that `expr_stmt.type` matches `NODE_EXPRESSION_STMT`
  5. Assert that `call_c.type` matches `NODE_FUNCTION_CALL`
  6. Assert that `member_c.type` matches `NODE_MEMBER_ACCESS`
  7. Assert that `call_b.type` matches `NODE_FUNCTION_CALL`
  8. Assert that `member_b.type` matches `NODE_MEMBER_ACCESS`
  9. Assert that `call_a.type` matches `NODE_FUNCTION_CALL`
  10. Assert that `call_a.as.function_call.callee.type` matches `NODE_IDENTIFIER`
  ```

### `test_CallSyntax_MethodCall`
- **Implementation Source**: `tests/test_call_syntax.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void { s.method(); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `AST is successfully constructed` is satisfied
  2. Assert that `call.type` matches `NODE_FUNCTION_CALL`
  3. Assert that `call.as.function_call.callee.type` matches `NODE_MEMBER_ACCESS`
  ```

### `test_Task168_ComplexContexts`
- **Implementation Source**: `tests/task_168_validation.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn getInt() i32 { return 42; }
fn process(n: i32) void {}
fn doubleInt(n: i32) i32 { return n * 2; }
const S = struct { f: i32 };
fn main() void {
    defer { process(getInt()); }
    switch (getInt()) {
        42 => process(1),
        else => process(0),
    };
    while (getInt() > 0) {
        process(getInt());
    }
    const s: S = S { .f = getInt() };
    process(doubleInt(doubleInt(getInt())));
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `table.count` is satisfied
  3. Assert that `table.getUnresolvedCount` matches `0`
  ```
