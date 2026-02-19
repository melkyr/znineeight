# RetroZig Examples

This directory contains example programs written in the Z98 Zig subset, demonstrating various features of the RetroZig bootstrap compiler.

## Available Examples

### Basic
- `hello/`: Standard "Hello World" demonstrating multi-module compilation and runtime integration.
- `prime/`: Prime number calculation demonstrating basic arithmetic and loops.
- `fibonacci/`: Recursive Fibonacci sequence demonstrating recursion.

### Advanced (Milestone 7)
- `heapsort/`: In-place Heapsort algorithm demonstrating arrays and loops.
- `quicksort/`: Quicksort with function pointer comparator, demonstrating many-item pointers and function pointers.
- `sort_strings/`: String sorting demonstrating multi-level pointers (`[*][*]u8`).
- `func_ptr_return/`: Demonstrates functions returning function pointers and indirect calls.

## Running the Examples

You can run all examples at once using the provided script:
```bash
./run_all_examples.sh
```

Or run individual examples by navigating to their respective directories and running their `run.sh` script.

## Prerequisites
- A built `zig0` compiler in the root directory.
- `gcc` (or any C89-compatible compiler).
