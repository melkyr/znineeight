> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Z98 Compiler - 0.10.0 "Xylene"
**A self-hosting subset of Zig → C89 bootstrap compiler for Windows 9x.**

## Project Overview
Z98 is a subset of the Zig language. This compiler is not affiliated with the official Zig project.
Z98 is an ambitious project to build a somewhat Zig compiler (or at least a good subset of my interpretation of the lang spec) from scratch that targets the Windows 9x era (Windows 95, 98, ME). To achieve this while adhering to the hardware and software constraints of that period, the compiler uses a "Progressive Enhancement" strategy.

We start with a **Stage 0** bootstrap compiler written in C++98, which compiles a **Stage 1** compiler written in a subset of Zig. Finally, **Stage 1** compiles itself to become the fully self-hosted **Stage 2** compiler.

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

### Technical Constraints
To ensure compatibility with 1998-era hardware (e.g., Pentium I/II, 32MB RAM):
- **Language**: C++98 (maximum) for the bootstrap compiler.
- **Memory**: < 16MB peak usage preferred.
- **Dependencies**: Win32 API (`kernel32.dll`) only. No third-party libraries or modern STL.
- **Architecture**: 32-bit little-endian target assumptions.
- **MSVC 6.0 Compatibility**: Extensive use of `__int64` and C89-compliant constructs.

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
g++ -std=c++98 -m32 -mconsole -static-libgcc -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0.exe
```

### Build Flags and Options
The Z98 compiler (`zig0`) supports several command-line options to control the build process:

-   `-o <file>`: Specify the output C source file path. The compiler will also generate a corresponding `.h` file in the same directory.
-   `-I <path>`: Add a directory to the module search path for `@import` resolution. Multiple `-I` flags can be provided.
-   `--win-line-endings`: Forces the compiler to use CRLF (`\r\n`) line endings in all generated C source and header files. This is recommended for maximum compatibility when building with MSVC 6.0 on Windows 9x.
-   `--debug-lifter`: Enables verbose logging of the AST lifting pass, showing how expression-flow is transformed into statements.
-   `--debug-codegen`: Enables debug tracing in the C89 code generator, including variable allocation and scope tracking.
-   `--test-mode`: Enables deterministic name mangling (using counters instead of hashes) for stable integration testing.

### Running Tests
The project features a comprehensive suite of over 500 unit and integration tests.
```bash
./test.sh    # Runs all test batches
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
