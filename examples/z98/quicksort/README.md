# Quicksort with Function Pointer Comparator

This example demonstrates:
- Function pointers as parameters.
- Many-item pointers (`[*]T`) for array access.
- Pointer arithmetic.
- Recursive function calls.

## How to Build and Run

1.  Ensure the bootstrap compiler `zig0` is built in the root directory.
2.  Run the provided script:
    ```bash
    ./run.sh
    ```

Or manually:
```bash
../../zig0 quicksort.zig -o output
cd output
gcc -std=c89 -pedantic main.c ../../../src/runtime/zig_runtime.c -I../../../src/include -o quicksort
./quicksort
```
