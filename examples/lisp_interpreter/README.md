# Minimal Lisp Interpreter in Z98

A "Baptism of Water" implementation of a Lisp interpreter designed for 1998-era constraints using the RetroZig bootstrap compiler.

## Modules

-   **`arena.zig`**: A simple bump allocator implementation.
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

**Note**: This interpreter currently triggers a compiler assertion failure during the type-checking phase of cross-module imports of recursive structures.

To reproduce the bug, see `missing_features_lisp.md` in the repository root or run:
```bash
./retrozig examples/lisp_interpreter/repro_bug.zig -o repro_bug.c
```
The source code is provided as a complete reference implementation and a benchmark for future compiler improvements.
