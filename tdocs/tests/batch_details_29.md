# Z98 Test Batch 29 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 15 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_Codegen_Binary_Arithmetic`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: i32, b: i32) i32 { return a + b * 2 / (10 - a) % 3; }
  ```
  ```zig
return a + b * 2 / (10 - a) % 3;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `return a + b * 2 / (10 - a) % 3;`
  ```

### `test_Codegen_Binary_Comparison`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: i32, b: i32) bool { return a == b and a != 0 or b < 10 and a >= b; }
  ```
  ```zig
return a == b && a != 0 || b < 10 && a >= b;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `return a == b && a != 0 || b < 10 && a >= b;`
  ```

### `test_Codegen_Binary_Bitwise`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: u32, b: u32) u32 { return (a & b) | (a ^ b) ^ (a << 1) >> 2; }
  ```
  ```zig
return (a & b) | (a ^ b) ^ (a << 1) >> 2;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `return (a & b) | (a ^ b) ^ (a << 1) >> 2;`
  ```

### `test_Codegen_Binary_CompoundAssignment`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: *i32, b: i32) void { a.* += b; a.* -= 1; a.* *= 2; a.* /= 2; a.* %= 3; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `(void)(*a += b);\n    (void)(*a -= 1);\n    (void)(*a *= 2);\n    (void)(*a /= 2);\n    (void)(*a %= 3);`
  ```

### `test_Codegen_Binary_BitwiseCompoundAssignment`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: *u32, b: u32) void { a.* &= b; a.* |= 1; a.* ^= 0xF; a.* <<= 1; a.* >>= 2; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `(void)(*a &= b);\n    (void)(*a |= 1);\n    (void)(*a ^= 15);\n    (void)(*a <<= 1);\n    (void)(*a >>= 2);`
  ```

### `test_Codegen_Binary_Wrapping`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: u32, b: u32) u32 { return a +% b -% 1 *% a; }
  ```
  ```zig
return a + b - 1 * a;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `return a + b - 1 * a;`
  ```

### `test_Codegen_Binary_Logical_Keywords`
- **Implementation Source**: `tests/integration/codegen_binary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: bool, b: bool) bool { return a and b or !a; }
  ```
  ```zig
return a && b || !a;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Generate C89 code and verify critical lowering: `return a && b || !a;`
  ```

### `test_Codegen_Unary_Negation`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: i32) i32 { return -a; }
  ```
  ```zig
return -a;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_Negation and validate component behavior
  ```

### `test_Codegen_Unary_Plus`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: i32) i32 { return +a; }
  ```
  ```zig
return +a;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_Plus and validate component behavior
  ```

### `test_Codegen_Unary_LogicalNot`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: bool) bool { return !a; }
  ```
  ```zig
return !a;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_LogicalNot and validate component behavior
  ```

### `test_Codegen_Unary_BitwiseNot`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: u32) u32 { return ~a; }
  ```
  ```zig
return ~a;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_BitwiseNot and validate component behavior
  ```

### `test_Codegen_Unary_AddressOf`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test() void { var x: i32 = 42; var p: *i32 = &x; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_AddressOf and validate component behavior
  ```

### `test_Codegen_Unary_Dereference`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(p: *i32) i32 { return p.*; }
  ```
  ```zig
return *p;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_Dereference and validate component behavior
  ```

### `test_Codegen_Unary_Nested`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(p: *i32) i32 { return -p.*; }
  ```
  ```zig
return -*p;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_Nested and validate component behavior
  ```

### `test_Codegen_Unary_Mixed`
- **Implementation Source**: `tests/integration/codegen_unary_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_test(a: i32, b: bool) i32 { if (!b) { return -a; } return a; }
  ```
  ```zig
if (!b) {
        return -a;
    }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_Unary_Mixed and validate component behavior
  ```
