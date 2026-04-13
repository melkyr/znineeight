# Z98 Test Batch 23 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 6 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_CVariableAllocator_Basic`
- **Implementation Source**: `tests/test_c_variable_allocator.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
;

    const char* name = alloc.allocate(&s1);
    ASSERT_EQ(0, plat_strcmp(name,
  ```
  ```zig
;
    const char* name2 = alloc.allocate(&s2);
    ASSERT_EQ(0, plat_strcmp(name2,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `plat_strcmp(name, "my_var"` matches `0`
  2. Assert that `plat_strcmp(name2, "my_var_1"` matches `0`
  ```

### `test_CVariableAllocator_Keywords`
- **Implementation Source**: `tests/test_c_variable_allocator.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
;

    const char* name = alloc.allocate(&s1);
    ASSERT_EQ(0, plat_strcmp(name,
  ```
  ```zig
;
    const char* name2 = alloc.allocate(&s2);
    ASSERT_EQ(0, plat_strcmp(name2,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `plat_strcmp(name, "z_int"` matches `0`
  2. Assert that `plat_strcmp(name2, "z_123var"` matches `0`
  ```

### `test_CVariableAllocator_Truncation`
- **Implementation Source**: `tests/test_c_variable_allocator.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
;

    const char* name = alloc.allocate(&s1);
    ASSERT_EQ(31, (int)plat_strlen(name));
    ASSERT_TRUE(plat_strncmp(name, s1.name, 31) == 0);

    // Collision after truncation
    Symbol s2;
    s2.name =
  ```
  ```zig
;
    const char* name2 = alloc.allocate(&s2);
    ASSERT_EQ(31, (int)plat_strlen(name2));
    // name is
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `int` matches `31`
  2. Validate that `plat_strncmp(name, s1.name, 31` is satisfied
  3. Assert that `plat_strcmp(name2, "this_is_a_very_long_variable__1"` matches `0`
  ```

### `test_CVariableAllocator_MangledReuse`
- **Implementation Source**: `tests/test_c_variable_allocator.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
;

    const char* name = alloc.allocate(&s);
    ASSERT_EQ(0, plat_strcmp(name,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `plat_strcmp(name, "already_mangled"` matches `0`
  ```

### `test_CVariableAllocator_Generate`
- **Implementation Source**: `tests/test_c_variable_allocator.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
));

    const char* name2 = alloc.generate(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `plat_strcmp(name, "_tmp"` matches `0`
  2. Assert that `plat_strcmp(name2, "_tmp_1"` matches `0`
  ```

### `test_CVariableAllocator_Reset`
- **Implementation Source**: `tests/test_c_variable_allocator.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    alloc.reset();

    const char* name = alloc.generate(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `plat_strcmp(name, "my_var"` matches `0`
  ```
