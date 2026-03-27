# Minimal Lisp Interpreter in Z98

A "Baptism of Water" implementation of a Lisp interpreter designed for 1998-era constraints using the Z98 bootstrap compiler.

## Modules

-   **`sand.zig`**: A simple bump allocator implementation (formerly `arena.zig`).
-   **`value.zig`**: Defines the `Value` type and allocation helpers.
-   **`token.zig`**: Tokenizer for Lisp source code.
-   **`parser.zig`**: Recursive-descent parser that builds `Value` structures and handles symbol interning.
-   **`env.zig`**: Linked-list based environment for variable bindings.
-   **`eval.zig`**: The core evaluator, implementing `quote`, `if`, `define`, `lambda`, and function application.
-   **`builtins.zig`**: Primitive Lisp functions (`car`, `cdr`, `cons`, `+`, `-`, `=`, etc.).
-   **`util.zig`**: Helper functions like `mem_eql`, `parse_int`, and `deep_copy`.
-   **`main.zig`**: REPL loop and global environment setup.

## Design Highlights

### Dual-Arena System
The interpreter uses two distinct allocation regions:
1.  **Permanent Arena**: Used for the global environment, interned symbols, and closure definitions.
2.  **Temporary Arena**: Used for intermediate values during evaluation. It is reset after every top-level REPL expression to ensure minimal memory usage.

`util.deep_copy` is used to migrate values from the temporary to the permanent arena when they are bound to the environment via `define`.

### Syntax Workaround
Due to current bootstrap compiler limitations, this implementation uses a "Downgraded" syntax:
-   `struct` + `union` instead of `union(enum)`.
-   Manual tag checks instead of `switch` captures.

## Current Status

**Status**: The Zig source code for the interpreter is feature-complete for the "Baptism of Water" phase. However, generating a working binary requires specific patches to the `z98` bootstrap compiler.

### Build Instructions

To attempt a build of the Lisp interpreter:

1.  Ensure you have a compiled `z98` compiler at the repository root.
2.  Run the compiler on the entry point:
    ```bash
    ./z98 examples/lisp_interpreter/main.zig -o o_lisp/main.c
    ```
3.  Compile the generated C code (requires `-m32` for the 1998 target):
    ```bash
    gcc -m32 -o lisp_repl o_lisp/*.c
    ```

**Note**: Without the compiler patches described in `missing_features_lisp.md`, the Zig compilation phase may fail with "type mismatch" errors across modules, and the generated C code may fail to compile due to C89 scoping rules or `main` function return type mismatches.

For a detailed analysis of the compiler challenges and the required fixes, please refer to:
`examples/lisp_interpreter/missing_features_lisp.md`
