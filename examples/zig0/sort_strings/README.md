# Sorting Strings (Multi-level Pointers)

This example demonstrates:
- Multi-level pointers (`[*][*]const u8`).
- Many-item pointers of many-item pointers.
- Passing string literals into arrays.

## How to Build and Run

1.  Ensure the bootstrap compiler `zig0` is built in the root directory.
2.  Run the provided script:
    ```bash
    ./run.sh
    ```

Or manually:
```bash
../../zig0 sort_strings.zig -o output
cd output
gcc -std=c89 -pedantic main.c ../../../src/runtime/zig_runtime.c -I../../../src/include -o sort_strings
./sort_strings
```
