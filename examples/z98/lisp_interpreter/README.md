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

## Building with zig1

The compiler is self-hosted. A seed build (`scripts/seed/build_from_seed.sh`)
puts `lib/` next to the `zig1` binary, and the compiler searches `<exe-dir>/lib`
automatically. When the binary lives elsewhere, pass the library directory with
`-I lib` (relative to the current directory). On Windows never use `-I /lib`:
that is the drive root, and the compiler reports `cannot find std`.

`-o <dir>` selects the output directory and is required; without it the
compiler emits nothing. Create the directory first.

### Linux

```sh
mkdir -p out
/path/to/zig1_5_clean -o out main.zig
sh out/build_target.sh
./out/prog
```

### Windows 9x / NT

Run this from the example directory in a Command Prompt. `-osw` selects the
Windows target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw -o out main.zig
cd out
build_owc_crt.bat
prog.exe
```

`build_owc_crt.bat` (OpenWatcom, static CRT) is the verified path;
`build_target_crt.bat` is the MSVC 6 equivalent (run `VCVARS32.BAT` first);
`build_owc_nocrt.bat` / `build_target_nocrt.bat` are the no-CRT alternates; and
`build_mingw_crt.bat` is the MinGW fallback (needs `msvcrt.dll`). The output is
`out\prog.exe`.

Sources: `main.zig` (entry) imports `sand.zig`, `value.zig`, `token.zig`,
`parser.zig`, `env.zig`, `eval.zig`, `builtins.zig`, and `util.zig`; pass only
`main.zig` — the compiler resolves the rest.

## Basic Test Expressions

You can use the following expressions to verify the interpreter's functionality:

- **Arithmetic**: `(+ 1 2)` -> `3`, `(* 3 4)` -> `12`
- **Definitions**: `(define x 10)` -> `10`
- **Conditionals**: `(if (= x 10) 1 0)` -> `1`

For a detailed analysis of the compiler challenges and the required fixes, please refer to:
`examples/lisp_interpreter/missing_features_lisp.md`
