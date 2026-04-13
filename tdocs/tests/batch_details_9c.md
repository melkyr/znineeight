# Z98 Test Batch 9c Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 13 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_ExpectedType_SwitchReturn`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
fn testSwitch(u: MyUnion) MyUnion {
    return switch (u) {
        .A => |a| .{ .A = a },
        .B => |b| .{ .B = b },
        else => .{ .A = 0 },
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_Assignment`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
export fn testAssign(u: MyUnion) void {
    var result: MyUnion = .{ .A = 0 };
    result = switch (u) {
        .A => |a| .{ .A = a },
        .B => |b| .{ .B = b },
        else => .{ .A = 0 },
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_VarDecl`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
export fn testVarDecl(u: MyUnion) void {
    const result: MyUnion = switch (u) {
        .A => |a| .{ .A = a },
        .B => |b| .{ .B = b },
        else => .{ .A = 0 },
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_FunctionArg`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
fn consume(u: MyUnion) void {}
export fn testArg(u: MyUnion) void {
    consume(switch (u) {
        .A => |a| .{ .A = a },
        .B => |b| .{ .B = b },
        else => .{ .A = 0 },
    });
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_NestedSwitch`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
fn testNested(u: MyUnion, v: MyUnion) MyUnion {
    return switch (u) {
        .A => |a| switch (v) {
            .A => |va| .{ .A = a + va },
            else => .{ .A = a },
        },
        .B => |b| .{ .B = b },
        else => .{ .A = 0 },
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_IfExpr`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
fn testIf(b: bool) MyUnion {
    return if (b) .{ .A = 1 } else .{ .B = true };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_BlockExpr`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyUnion = union(enum) { A: i32, B: bool };
fn testBlock(b: bool) MyUnion {
    return {
        var x = b;
        .{ .A = 1 }
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_SwitchEnumToUnion`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const MyEnum = enum { A, B };
const MyUnion = union(enum) { A: i32, B: bool };
fn translate(e: MyEnum) MyUnion {
    return switch (e) {
        .A => .{ .A = 1 },
        .B => .{ .B = true },
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_VoidPayloads`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union(enum) { A, B: void, C: i32 };
fn getVoid() void {}
export fn testVoid() void {
    var u: U = .{ .A };
    u = .{ .B = {} };
    u = .{ .B = getVoid() };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_DeeplyNested`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const Inner = union(enum) { A: i32, B: bool };
const Outer = union(enum) { I: Inner, C: i32 };
export fn testNestedAnon() void {
    var o: Outer = .{ .I = .{ .A = 42 } };
    o = .{ .I = .{ .B = true } };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```

### `test_ExpectedType_SwitchMissingElseError`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union(enum) { A, B };
fn testMissingElse(u: U) i32 {
    return switch (u) {
        .A => 1,
        .B => 2,
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  ```

### `test_ExpectedType_AnonymousToNonUnionError`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
export fn testAnonToNonUnion() void {
    var x: i32 = .{ .A = 1 };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Type Checker correctly rejects invalid input
  ```

### `test_ExpectedType_MixedSwitch`
- **Implementation Source**: `tests/main_batch9c.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union(enum) { A: i32, B: bool };
fn testMixed(u: U) U {
    return switch (u) {
        .A => |a| U{ .A = a },
        .B => |b| .{ .B = b },
        else => .{ .A = 0 },
    };
}

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  ```
