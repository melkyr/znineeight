# Z98 Lisp Interpreter (`lisp_interpreter_curr`)

This is a stable Lisp interpreter built using the Z98 Milestone 11 compiler. It targets 32-bit C89 and demonstrates the compiler's ability to handle complex tagged unions, recursion, and arena allocation.

## Current Status: Milestone 11 Verified

The interpreter is fully functional in 32-bit mode. Recent updates have improved its stability and performance.

### Key Features
- **Tail-Call Optimization (TCO)**: The core `eval` loop has been refactored to support TCO. This allows deep tail recursion (e.g., `countdown` or `factorial-iter`) without exhausting the C stack.
- **Arena Memory Management**: Uses a dual-arena system (Permanent and Temporary) to manage Lisp values efficiently within a < 16MB memory footprint.
- **Milestone 11 Support**: Leverages advanced Z98 features like braceless control flow and improved tagged union codegen.

## Limitations & Known Issues

- **One Expression Per Line**: The REPL currently only parses and evaluates the first Lisp expression found on each input line. Multiple expressions like `(define a 1) (define b 2)` must be entered on separate lines.
- **Integer Overflow**: Uses 64-bit integers (`i64`), but the Z98 runtime currently enforces safety checks. Operations that exceed `i64` limits (like `(fact 13)`) will trigger a runtime panic.
- **Memory Exhaustion**: The temporary arena is fixed at 1MB. Extremely deep recursion or massive list processing that allocates many temporary objects without returning to the REPL loop may hit `OutOfMemory`.
- **64-bit Compatibility**: This interpreter is optimized for 32-bit targets. Building in 64-bit mode may lead to memory alignment issues or segfaults.

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

Sources: `main.zig` (entry) imports `builtins.zig`, `deep_copy.zig`, `env.zig`,
`eval.zig`, `parser.zig`, `sand.zig`, `token.zig`, `util.zig`, and `value.zig`;
pass only `main.zig` — the compiler resolves the rest.

## Quick Start

Start the REPL with `./out/prog` (Linux) or `out\prog.exe` (Windows), then try:

```lisp
> (define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1))))))
<closure>
> (fact 5)
120
```

Type `exit` or use `Ctrl+C` to leave.
