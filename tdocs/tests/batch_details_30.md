# Batch 30 Details: Syntactic Analysis (Parser & AST)

## Focus
Syntactic Analysis (Parser & AST)

This batch contains 22 test cases focusing on syntactic analysis (parser & ast).

## Test Case Details
### `test_Codegen_MemberAccess_Simple`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s: S) i32 { return s.f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Pointer`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(sp: *S) i32 { return sp.f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_ExplicitDeref`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(sp: *S) i32 { return sp.*.f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_AddressOf`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s: S) i32 { return (&s).f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Union`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) i32 { return u.f; }
  ```
  ```zig
const U = union { f: i32, g: f32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Nested`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s2: S2) i32 { return s2.s1.f; }
  ```
  ```zig
const S1 = struct { f: i32 };
  ```
  ```zig
const S2 = struct { s1: S1 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Array`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(arr: [5]S) i32 { return arr[0].f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Call`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
extern fn getS() S;
  ```
  ```zig
fn foo() i32 { return getS().f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Cast`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(p: *void) i32 {
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_NestedPointer`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s2: S2) i32 { return s2.p1.f; }
  ```
  ```zig
const S1 = struct { f: i32 };
  ```
  ```zig
const S2 = struct { p1: *S1 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_ComplexPostfix`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s: S) i32 { return s.arr[0]; }
  ```
  ```zig
const S = struct { arr: [5]i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Simple`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s: S) i32 { return s.f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Pointer`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(sp: *S) i32 { return sp.f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_ExplicitDeref`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(sp: *S) i32 { return sp.*.f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_AddressOf`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s: S) i32 { return (&s).f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Union`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(u: U) i32 { return u.f; }
  ```
  ```zig
const U = union { f: i32, g: f32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Nested`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s2: S2) i32 { return s2.s1.f; }
  ```
  ```zig
const S1 = struct { f: i32 };
  ```
  ```zig
const S2 = struct { s1: S1 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Array`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(arr: [5]S) i32 { return arr[0].f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Call`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
extern fn getS() S;
  ```
  ```zig
fn foo() i32 { return getS().f; }
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_Cast`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(p: *void) i32 {
  ```
  ```zig
const S = struct { f: i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_NestedPointer`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s2: S2) i32 { return s2.p1.f; }
  ```
  ```zig
const S1 = struct { f: i32 };
  ```
  ```zig
const S2 = struct { p1: *S1 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```

### `test_Codegen_MemberAccess_ComplexPostfix`
- **Primary File**: `tests/integration/codegen_member_access_tests.cpp`
- **Test Input (Zig)**:
  ```zig
fn foo(s: S) i32 { return s.arr[0]; }
  ```
  ```zig
const S = struct { arr: [5]i32 };
  ```
- **How it is tested (Pseudocode)**:
  ```pseudocode
  1. Setup Syntactic Analysis (Parser & AST) environment in a clean arena
  2. Pass the Zig source code to the compiler frontend
  4. Ensure execution completes without internal errors or crashes
  ```
