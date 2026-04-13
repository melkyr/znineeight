# Z98 Test Batch 15 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 12 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_StructIntegration_BasicNamedStruct`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
var p: Point = Point{ .x = 1, .y = 2 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_StructIntegration_BasicNamedStruct and validate component behavior
  ```

### `test_StructIntegration_MemberAccess`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
fn foo() i32 {
    var p: Point = Point{ .x = 10, .y = 20 };
    return p.x;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_StructIntegration_NamedInitializerOrder`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct { x: i32, y: i32 };
var p: Point = Point{ .y = 20, .x = 10 };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_StructIntegration_NamedInitializerOrder and validate component behavior
  ```

### `test_StructIntegration_RejectAnonymousStruct`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void {
    var s: struct { x: i32 } = null;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_StructIntegration_RejectStructMethods`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Point = struct {
    x: i32,
    fn length(self: *Point) i32 { return self.x; }
};
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_StructIntegration_AllowSliceField`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Buffer = struct {
    data: []i32,
};
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_StructIntegration_AllowMultiLevelPointerField`
- **Implementation Source**: `tests/integration/struct_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Data = struct {
    ptr: **i32,
};
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_TaggedUnion_BasicSwitch`
- **Implementation Source**: `tests/integration/tagged_union_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Tag = enum { a, b };
const U = union(Tag) { a: i32, b: f32 };
fn foo(u: U) i32 {
    return switch (u) {
        .a => |val| val,
        .b => |val| 0,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_TaggedUnion_ImplicitEnum`
- **Implementation Source**: `tests/integration/tagged_union_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union(enum) { a: i32, b: f32 };
fn foo(u: U) i32 {
    return switch (u) {
        .a => |val| val,
        .b => |_| 0,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_TaggedUnion_ElseProng`
- **Implementation Source**: `tests/integration/tagged_union_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union(enum) { a: i32, b: f32, c: bool };
fn foo(u: U) i32 {
    return switch (u) {
        .a => |val| val,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_TaggedUnion_ExplicitEnumCustomValues`
- **Implementation Source**: `tests/integration/tagged_union_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Tag = enum(i32) { a = 100, b = 200 };
const U = union(Tag) { a: i32, b: f32 };
fn foo(u: U) i32 {
    return switch (u) {
        .a => |val| val,
        .b => |_| 0,
        else => 0,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_TaggedUnion_CaptureImmutability`
- **Implementation Source**: `tests/integration/tagged_union_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union(enum) { a: i32 };
fn foo(u: U) void {
    switch (u) {
        .a => |val| {
            val = 42;
        },
        else => {},
    }
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```
