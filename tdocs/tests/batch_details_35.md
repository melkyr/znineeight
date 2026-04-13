# Z98 Test Batch 35 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 5 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_ImportResolution_Basic`
- **Implementation Source**: `tests/test_import_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const other = @import(\
  ```
  ```zig
); pub fn main() void {}
  ```
  ```zig
pub const x = 1;
  ```
  ```zig
, &source, &size)) return false;

    u32 file_id = unit.addSource(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Validate that `unit.getModule("other"` is satisfied
  ```

### `test_ImportResolution_IncludePath`
- **Implementation Source**: `tests/test_import_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const ext = @import(\
  ```
  ```zig
); pub fn main() void {}
  ```
  ```zig
pub const y = 2;
  ```
  ```zig
);

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read(
  ```
  ```zig
, &source, &size)) return false;

    u32 file_id = unit.addSource(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Validate that `unit.getModule("ext"` is satisfied
  ```

### `test_ImportResolution_DefaultLib`
- **Implementation Source**: `tests/test_import_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
pub const z = 3;
  ```
  ```zig
const std = @import(\
  ```
  ```zig
); pub fn main() void {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Validate that `unit.getModule("std_mock"` is satisfied
  ```

### `test_ImportResolution_PrecedenceLocal`
- **Implementation Source**: `tests/test_import_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const mod = @import(\
  ```
  ```zig
); pub fn main() void {}
  ```
  ```zig
pub const source = 1;
  ```
  ```zig
pub const source = 2;
  ```
  ```zig
);

    char* source = NULL;
    size_t size = 0;
    if (!plat_file_read(
  ```
  ```zig
, &source, &size)) return false;

    u32 file_id = unit.addSource(
  ```
  ```zig
// Since we normalize paths, we can check if it contains
  ```
  ```zig
const char* p = m->filename;
    bool found_inc = false;
    while (*p) {
        if (plat_strncmp(p,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Validate that `success` is satisfied
  3. Validate that `m not equals null` is satisfied
  4. Ensure that `found_inc` is false
  ```

### `test_ImportResolution_NotFound`
- **Implementation Source**: `tests/test_import_resolution.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
const missing = @import(\
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Execute complete compilation pipeline (Front-to-Back)
  2. Ensure that `success` is false
  3. Validate that `unit.getErrorHandler` is satisfied
  ```
