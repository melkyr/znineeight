# Function Returning a Function Pointer

This example demonstrates:
- Functions that return function pointers.
- Calling returned function pointers.
- Implicit coercion of function names to pointers.

## How to Build and Run

1.  Ensure the bootstrap compiler `zig0` is built in the root directory.
2.  Run the provided script:
    ```bash
    ./run.sh
    ```

Or manually:
```bash
../../zig0 func_ptr_return.zig -o output
cd output
gcc -std=c89 -pedantic main.c ../../../src/runtime/zig_runtime.c -I../../../src/include -o func_ptr_return
./func_ptr_return
```
