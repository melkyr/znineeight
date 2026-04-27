> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Z98 Compiler - 0.11.0 "para-Cresol"
**A self-hosting subset of Zig → C89 bootstrap compiler for Windows 9x.**

## Project Overview
Z98 is a subset of the Zig language. This compiler is not affiliated with the official Zig project.
Z98 is an ambitious project to build a somewhat Zig compiler (or at least a good subset of my interpretation of the lang spec) from scratch that targets the Windows 9x era (Windows 95, 98, ME). To achieve this while adhering to the hardware and software constraints of that period, the compiler uses a "Progressive Enhancement" strategy.

We start with a **Stage 0** bootstrap compiler written in C++98, which compiles a **Stage 1** compiler written in a subset of Zig. Finally, **Stage 1** compiles itself to become the fully self-hosted **Stage 2** compiler.

<img width="646" height="562" alt="Zni01" src="https://github.com/user-attachments/assets/d17def92-f577-4a9b-9415-022a4ee1ebfd" />
<img width="643" height="559" alt="Zni03" src="https://github.com/user-attachments/assets/654e2f81-917c-4250-b9d0-5ec7d7536f66" />


## Current Status: Milestone 11 finished. Stable Bootstrap Compiler
The project has successfully completed Milestone 11.
The Stage 0 compiler (`zig0`) is a robust multi-module compiler capable of generating C89 code using a separate compilation model with full `defer` and `errdefer` support.

### Key Supported Features
- **Multi-Module Support**: Recursive `@import` resolution with topological sorting and circular dependency detection.
- **Separate Compilation**: Generates individual `.c` and `.h` files per module, with automated build scripts (`build_target.sh/bat`).
- **AST Lifting**: Automatic transformation of expression-form control flow (`if`, `switch`, `try`, `catch`, `orelse`) into statement-form equivalents.
- **Error Handling**: Full support for error unions (`!T`), error sets, `try`, `catch`, and full `errdefer` execution.
- **Optional Types**: Support for `?T`, `null`, and `orelse`.
- **Slices**: Full support for `[]T` and slicing expressions `base[start..end]`.
- **Tagged Unions**: Support for `union(enum)` with payload captures in `switch` and `while` statements, including nested anonymous struct payloads.
- **Recursive Types**: Support for mutually recursive structs and unions via a robust placeholder resolution mechanism.
- **Control Flow**: Full support for `defer`, `errdefer`, labeled loops, `break`/`continue` with scope unwinding, and braceless `if`/`while`/`for`/`defer` statements.
- **Switch Features**: Support for range-based prongs (e.g., `1...10 => ...`) and divergent prongs (`return`, `unreachable`).
- **Built-in Lowering**: Compiler-assisted lowering for `std.debug.print` and safe narrowing casts.
- **Memory Strategy**: Multi-tiered arena system (Global, Token, Transient) for < 16MB peak usage.
- **Static Analysis**: Lifetime analysis, null pointer detection, and double-free detection.
- **Unified Logging**: Centralized logging system via a global `Logger` instance intercepted at the platform layer, supporting multiple log levels, buffering, and file output.

### Technical Constraints
To ensure compatibility with 1998-era hardware (e.g., Pentium I/II, 32MB RAM):
- **Language**: C++98 (maximum) for the bootstrap compiler.
- **Memory**: < 16MB peak usage preferred.
- **Dependencies**: Win32 API (`kernel32.dll`) only. No third-party libraries or modern STL.
- **Architecture**: 32-bit little-endian target assumptions.
- **MSVC 6.0 Compatibility**: Extensive use of `__int64` and C89-compliant constructs.

### Peak Memory Usage (Compilation)
The following table shows the peak memory usage of `zig0` when compiling the example programs. Measurements were taken using `valgrind --tool=massif`.

| Example | Peak Memory (MB) |
|---------|------------------|
| `hello` | 0.82 |
| `prime` | 0.82 |
| `days_in_month` | 0.82 |
| `fibonacci` | 0.82 |
| `heapsort` | 0.82 |
| `quicksort` | 0.82 |
| `sort_strings` | 0.82 |
| `func_ptr_return` | 0.82 |
| `lzw` | 1.33 |
| `mandelbrot` | 0.82 |
| `lisp_interpreter_curr` | 4.11 |
| `game_of_life` | 1.33 |
| `mud_server` | 1.33 |
| `rogue_mud` | 1.85 |

All examples stay well within the 16MB constraint.

## Comparison with Official Zig

| Feature | Official Zig Project | Z98 Bootstrap (Kind of Zig Subset) |
| :--- | :--- | :--- |
| **Language Standard** | Modern Zig (0.13.0+) | Z98 Subset (Interpretation) |
| **Compiler Host** | Modern C++, Zig | C++98 (Stage 0), Z98 (Stage 1) |
| **Dependencies** | CMake, LLVM, LLD, Clang, Python | Win32 API (`kernel32.dll`) ONLY |
| **Memory Usage** | GBs (during LLVM build) | < 16MB Peak strictly enforced |
| **Target Output** | Native Machine Code (via LLVM) | ANSI C89 Source Code |
| **Target Systems** | Modern (Linux, Windows, macOS, etc.) | Legacy (Windows 95/98/ME/NT 4.0) |
| **Portability** | Highly Portable (LLVM-based) | Extremely Portable (C89-based) |

## Getting Started
Just as a side note through the docs I will use zig0/z98 but they will refer to this project, as stated at the begining this is not affiliated with the official Zig project it's just a silly idea I had.

### Prerequisites
- **Linux**: `gcc` (C++98 compatible), `make`.
- **Windows 98**: MinGW 3.x (Required for `zig0`). MSVC 6.0 SP6 (Supported for C89 target only).

### Building the Compiler
Detailed instructions are available in [docs/Building.md](docs/Building.md).
On Linux:
```bash
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0
```
On Windows (MinGW 3.x):
```batch
g++ -std=c++98 -m32 -mconsole -static-libgcc -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0.exe -lwsock32
```

### Build Flags and Options
The Z98 compiler (`zig0`) supports several command-line options to control the build process:

-   `-o <file>`: Specify the output C source file path. The compiler will also generate a corresponding `.h` file in the same directory, along with build scripts and the required runtime headers in the same output folder.
-   `-I <path>`: Add a directory to the module search path for `@import` resolution. Multiple `-I` flags can be provided.
-   `--win-line-endings`: Forces the compiler to use CRLF (`\r\n`) line endings in all generated C source and header files. This is recommended for maximum compatibility when building with MSVC 6.0 on Windows 9x.
-   `--debug-lifter`: Enables verbose logging of the AST lifting pass, showing how expression-flow is transformed into statements.
-   `--debug-codegen`: Enables debug tracing in the C89 code generator, including variable allocation and scope tracking.
-   `--test-mode`: Enables deterministic name mangling (using counters instead of hashes) for stable integration testing.
-   `--log-file=<path>`: Enables centralized logging to the specified file. Logs are buffered and flushed after each compilation phase.
-   `--no-logs`: Suppresses all non-essential console output (INFO and DEBUG levels). Fatal errors and reported compilation errors/warnings are still displayed on stderr.
-   `--verbose` or `-v`: Enables DEBUG-level logging on the console. By default, DEBUG logs are only sent to the log file (if enabled).
-   `--header-priority-include`: Forces the compiler to emit module `#include` directives before type definitions in generated `.h` files. This resolves "field has incomplete type" errors when special types (Optional, Slice, etc.) have payloads from imported modules.

### Running Tests
The project features a comprehensive suite of over 500 unit and integration tests.
```bash
./test.sh    # Runs all test batches
```

## Minimal Distribution & Building Applications
To distribute a minimal version of the Z98 toolchain or to build an application on a target system without the full source tree, you require the following files:

1.  **`zig0` (or `zig0.exe`)**: The bootstrap compiler binary.
2.  **Runtime Source & Headers**:
    -   `src/include/zig_runtime.h`: Core runtime definitions.
    -   `src/include/zig_compat.h`: C89/Platform compatibility macros.
    -   `src/include/platform_win98.h`: Windows 9x API level enforcement (Required for Windows).
    -   `src/runtime/zig_runtime.c`: Implementation of runtime helpers (arenas, IO, panics).

### Building a Z98 Program (Manual Step-by-Step)
If you have a file `hello.zig`, you can build it into an executable as follows:

1.  **Compile to C**:
    ```bash
    ./zig0 hello.zig -o hello.c
    ```
    This will generate `hello.c`, `hello.h`, `zig_special_types.h`, `build_target.sh` (or `.bat`), and copy the runtime files into your current directory.

2.  **Build the Executable**:
    You can simply run the generated build script:
    ```bash
    ./build_target.sh  # On Linux/Unix
    # OR
    build_target.bat   # On Windows (MinGW)
    ```
    Alternatively, you can manually compile and link:
    ```bash
    # 1. Compile the runtime
    gcc -std=c89 -m32 -I. -c zig_runtime.c -o zig_runtime.o
    # 2. Compile your program
    gcc -std=c89 -m32 -I. -c hello.c -o hello.o
    # 3. Link everything
    gcc -m32 hello.o zig_runtime.o -o hello
    ```

## Documentation
- [Language Specification](docs/reference/Language_Spec_Z98.md): Supported syntax and Z98-specific patterns.
- [Building Guide](docs/Building.md): Detailed toolchain setup and build instructions.
- [Design Documents](docs/design/DESIGN.md): Core architecture and Arena Allocation strategy.
- [C89 Emission](docs/reference/c89_emission.md): How Z98 constructs map to C89.

## Examples
Check the `examples/` directory for sample Z98 programs:
- `examples/hello/`: Standard "Hello World".
- `examples/prime/`: Prime number calculation.
- `examples/fibonacci/`: Recursive Fibonacci sequence.
- `examples/heapsort/`: In-place Heapsort algorithm.
- `examples/quicksort/`: Quicksort with function pointers.
- `examples/sort_strings/`: String sorting with multi-level pointers.
- `examples/func_ptr_return/`: Functions returning function pointers.
