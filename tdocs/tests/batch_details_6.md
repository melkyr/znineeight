# Z98 Test Batch 6 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 33 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_TypeChecker_StructDeclaration_Valid`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `context.getCompilationUnit` is false
  ```

### `test_TypeChecker_StructDeclaration_DuplicateField`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { x: i32, x: bool };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeChecker_StructInitialization_Valid`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn main() -> void {
    var p: Point = Point { .x = 10, .y = 20 };
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `context.getCompilationUnit` is false
  ```

### `test_TypeChecker_MemberAccess_Valid`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn main() -> void {
    var p: Point = Point { .x = 10, .y = 20 };
    var x_val: i32 = p.x;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `context.getCompilationUnit` is false
  ```

### `test_TypeChecker_MemberAccess_InvalidField`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn main() -> void {
    var p: Point = Point { .x = 10, .y = 20 };
    var z_val: i32 = p.z;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeChecker_StructInitialization_MissingField`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn main() -> void {
    var p: Point = Point { .x = 10 };
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeChecker_StructInitialization_ExtraField`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn main() -> void {
    var p: Point = Point { .x = 10, .y = 20, .z = 30 };
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeChecker_StructInitialization_TypeMismatch`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn main() -> void {
    var p: Point = Point { .x = 10, .y = true };
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeChecker_StructLayout_Verification`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { a: u8, b: i32, c: u8 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `sym not equals null` is satisfied
  2. Assert that `TYPE_STRUCT` matches `kind of type`
  3. Assert that `3` matches `fields.length`
  4. Assert that `0` matches `*fields)[0].offset`
  5. Assert that `1` matches `*fields)[0].size`
  6. Assert that `4` matches `*fields)[1].offset`
  7. Assert that `4` matches `*fields)[1].size`
  8. Assert that `8` matches `*fields)[2].offset`
  9. Assert that `1` matches `*fields)[2].size`
  10. Assert that `12` matches `type.size`
  11. Assert that `4` matches `type.alignment`
  ```

### `test_TypeChecker_UnionDeclaration_DuplicateField`
- **Implementation Source**: `tests/type_checker_struct_tests.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union { x: i32, x: bool };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `context.getCompilationUnit` is satisfied
  ```

### `test_TypeCheckerEnum_MemberAccess`
- **Implementation Source**: `tests/test_enum_member_access.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Color = enum { Red, Green, Blue };
const my_color = Color.Green;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Ensure that `unit.getErrorHandler` is false
  3. Validate that `sym not equals null` is satisfied
  4. Validate that `sym.symbol_type not equals null` is satisfied
  5. Assert that `TYPE_ENUM` matches `sym.kind of symbol_type`
  ```

### `test_TypeCheckerEnum_InvalidMemberAccess`
- **Implementation Source**: `tests/test_enum_member_access.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Color = enum { Red, Green };
const x = Color.Blue;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnum_ImplicitConversion`
- **Implementation Source**: `tests/test_enum_member_access.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Color = enum { Red, Green, Blue };
const x: i32 = Color.Red;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeCheckerEnum_Switch`
- **Implementation Source**: `tests/test_enum_member_access.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Color = enum { Red, Green, Blue };
fn foo(c: Color) -> i32 {
    return switch (c) {
        Color.Red => 1,
        Color.Green => 2,
        else => 3,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Ensure that `unit.getErrorHandler` is false
  ```

### `test_TypeCheckerEnum_DuplicateMember`
- **Implementation Source**: `tests/test_enum_member_access.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Color = enum { Red, Green, Red };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_TypeCheckerEnum_AutoIncrement`
- **Implementation Source**: `tests/test_enum_member_access.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Status = enum { Ok = 0, Error = 10, Unknown, Fatal };
const u = Status.Unknown;
const f = Status.Fatal;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Ensure that `unit.getErrorHandler` is false
  3. Validate that `sym_status not equals null` is satisfied
  4. Assert that `TYPE_ENUM` matches `kind of status_type`
  5. Assert that `4` matches `members.length`
  6. Assert that `0` matches `*members)[0].value`
  7. Assert that `10` matches `*members)[1].value`
  8. Assert that `11` matches `*members)[2].value`
  9. Assert that `12` matches `*members)[3].value`
  ```

### `test_C89Rejection_ErrorUnionType_FnReturn`
- **Implementation Source**: `tests/test_task_135.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() !i32 { return 42; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_C89Rejection_OptionalType_VarDecl`
- **Implementation Source**: `tests/test_task_135.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: ?i32 = null;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_C89Rejection_ErrorUnionType_Param`
- **Implementation Source**: `tests/test_task_135.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo(x: !i32) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_C89Rejection_ErrorUnionType_StructField`
- **Implementation Source**: `tests/test_task_135.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { field: !i32 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_C89Rejection_NestedErrorUnionType`
- **Implementation Source**: `tests/test_task_135.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: *!u8 = null;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_Task136_ErrorSet_Catalogue`
- **Implementation Source**: `tests/test_task_136.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyErrors = error { A, B };
  ```
  ```zig
fn myTest() error{C}!void { }
  ```
  ```zig
const Merged = error{D} || error{E};
  ```
  ```zig
const std = @import(\
  ```
  ```zig
, source);
    Parser* parser = unit.createParser(file_id);

    parser->parse();

    ErrorSetCatalogue& catalogue = unit.getErrorSetCatalogue();
    // 1. MyErrors {A, B}
    // 2. anonymous {C}
    // 3. anonymous {D}
    // 4. anonymous {E}

    ASSERT_EQ(4, catalogue.count());

    const DynamicArray<ErrorSetInfo>* entries = catalogue.getErrorSets();
    ASSERT_TRUE(entries != NULL);

    bool found_myerrors = false;
    for (size_t i = 0; i < entries->length(); ++i) {
        if ((*entries)[i].name && strcmp((*entries)[i].name,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `catalogue.count` matches `4`
  2. Validate that `entries not equals null` is satisfied
  3. Assert that `*entries` matches `2`
  4. Validate that `found_myerrors` is satisfied
  ```

### `test_Task136_ErrorSet_Rejection`
- **Implementation Source**: `tests/test_task_136.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const E = error { A };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `run_type_checker_test_successfully(source` is satisfied
  ```

### `test_Task136_ErrorSetMerge_Rejection`
- **Implementation Source**: `tests/test_task_136.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Merged = E1 || E2;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_C89Rejection_ExplicitGeneric`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() void { max(i32, 1, 2); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_C89Rejection_ImplicitGeneric`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn max(comptime T: type, a: T, b: T) T { return a; }
 fn main() void { max(1, 2); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_GenericCatalogue_TracksExplicit`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn bar(comptime T: type, a: i32) void {}
 fn main() void { bar(i32, 1); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `unit.getGenericCatalogue` matches `1`
  2. Assert that `inst.param_count` matches `2`
  ```

### `test_GenericCatalogue_TracksImplicit`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn max(comptime T: i32, a: i32, b: i32) i32 { return a; }
 fn main() void { max(1, 2, 3); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `unit.getGenericCatalogue` matches `1`
  ```

### `test_C89Rejection_ComptimeValueParam`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn makeArray(comptime n: i32) void {}
 fn main() void { makeArray(10); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_GenericCatalogue_Deduplication`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Sub-system Coverage**: Semantic Analysis, Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn generic(comptime T: type) void {}
 fn main() void { generic(i32); generic(i32); }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `unit.getGenericCatalogue` matches `1`
  ```

### `test_Task155_AllTemplateFormsDetectedAndRejected`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn explicit_fn(comptime T: type, x: T) T { return x; }
fn implicit_fn(anytype x) void {}
fn test_caller() void {
    _ = explicit_fn(i32, 5);  // explicit instantiation
    implicit_fn(42);      // implicit instantiation
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task155_TypeParamRejected`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f(comptime T: type) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```

### `test_Task155_AnytypeParamRejected`
- **Implementation Source**: `tests/test_generics_rejection.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn f(anytype x) void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  2. Validate that `expect_type_checker_abort(source` is satisfied
  ```
