# Z98 Test Batch 34 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 5 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_MultiModule_BasicCall`
- **Implementation Source**: `tests/integration/multi_module_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
pub fn add(a: i32, b: i32) i32 { return a + b; }

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `unit.performFullPipeline(math_id` is satisfied
  3. Validate that `unit.performFullPipeline(main_id` is satisfied
  ```

### `test_MultiModule_StructUsage`
- **Implementation Source**: `tests/integration/multi_module_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
pub const Point = struct { x: i32, y: i32 };

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `unit.performFullPipeline(main_id` is satisfied
  ```

### `test_MultiModule_PrivateVisibility`
- **Implementation Source**: `tests/integration/multi_module_tests.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute core verification logic for test_MultiModule_PrivateVisibility and validate component behavior
  ```

### `test_MultiModule_CircularImport`
- **Implementation Source**: `tests/integration/multi_module_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const b = @import(\
  ```
  ```zig
;
    const char* b_source =
  ```
  ```zig
;

    // We can't easily test circular imports with addSource because resolveImports
    // is called inside performFullPipeline, and it attempts to load from disk.
    // I would need to mock the file system or use real files.

    // I'll use real files for this.
    plat_write_file(plat_open_file(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `!success` is satisfied
  ```

### `test_MultiModule_RelativePath`
- **Implementation Source**: `tests/integration/multi_module_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
pub const VAL = 42;

  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  ```
