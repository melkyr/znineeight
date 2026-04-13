# Z98 Test Batch 30 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 11 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_Codegen_MemberAccess_Simple`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
fn foo(s: S) i32 { return s.f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Simple and validate component behavior
  ```

### `test_Codegen_MemberAccess_Pointer`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
fn foo(sp: *S) i32 { return sp.f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Pointer and validate component behavior
  ```

### `test_Codegen_MemberAccess_ExplicitDeref`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
fn foo(sp: *S) i32 { return sp.*.f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_ExplicitDeref and validate component behavior
  ```

### `test_Codegen_MemberAccess_AddressOf`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
fn foo(s: S) i32 { return (&s).f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_AddressOf and validate component behavior
  ```

### `test_Codegen_MemberAccess_Union`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const U = union { f: i32, g: f32 };
fn foo(u: U) i32 { return u.f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Union and validate component behavior
  ```

### `test_Codegen_MemberAccess_Nested`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S1 = struct { f: i32 };
const S2 = struct { s1: S1 };
fn foo(s2: S2) i32 { return s2.s1.f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Nested and validate component behavior
  ```

### `test_Codegen_MemberAccess_Array`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
fn foo(arr: [5]S) i32 { return arr[0].f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Array and validate component behavior
  ```

### `test_Codegen_MemberAccess_Call`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
extern fn getS() S;
fn foo() i32 { return getS().f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Call and validate component behavior
  ```

### `test_Codegen_MemberAccess_Cast`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { f: i32 };
fn foo(p: *void) i32 {
    return @ptrCast(*S, p).f;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_Cast and validate component behavior
  ```

### `test_Codegen_MemberAccess_NestedPointer`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S1 = struct { f: i32 };
const S2 = struct { p1: *S1 };
fn foo(s2: S2) i32 { return s2.p1.f; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_NestedPointer and validate component behavior
  ```

### `test_Codegen_MemberAccess_ComplexPostfix`
- **Implementation Source**: `tests/integration/codegen_member_access_tests.cpp`
- **Sub-system Coverage**: Code Generation
- **Zig Source Input (Test Case Context)**:
  ```zig
const S = struct { arr: [5]i32 };
fn foo(s: S) i32 { return s.arr[0]; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_Codegen_MemberAccess_ComplexPostfix and validate component behavior
  ```
