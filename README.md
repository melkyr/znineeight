# RetroZig Compiler
**A self-hosting Zig → C89 bootstrap compiler for Windows 9x.**

## Project Overview
RetroZig is an ambitious project to build a Zig compiler from scratch that targets the Windows 9x era (Windows 95, 98, ME). To achieve this while adhering to the hardware and software constraints of that period, the compiler uses a "Progressive Enhancement" strategy.

We start with a **Stage 0** bootstrap compiler written in C++98, which compiles a **Stage 1** compiler written in a subset of Zig. Finally, **Stage 1** compiles itself to become the fully self-hosted **Stage 2** compiler.

## Current Status: Milestone 6 Complete
The project has successfully completed Milestone 6: **C Library Integration & Final Bootstrap**.
The Stage 0 compiler (`zig0`) is now a fully functional multi-module compiler capable of generating C89 code that links with a specialized minimal runtime.

### Key Supported Features
- **Multi-Module Support**: Recursive `@import` resolution with circular dependency detection.
- **Code Generation**: Full C89 backend emitting optimized C code compatible with MSVC 6.0 and GCC.
- **Memory Strategy**: Pervasive use of **Arena Allocation** in both the compiler and the generated runtime to ensure high performance and zero fragmentation on legacy hardware.
- **Primitive Types**: `i8` through `i64`, `u8` through `u64`, `isize`, `usize`, `f32`, `f64`, `bool`, `void`.
- **Aggregates**: Named `struct`, `enum`, and bare `union` types.
- **Control Flow**: `if-else`, `while` loops, `switch` expressions, and `for` loops.
- **Functions**: Support for recursion, forward references, and `extern fn` declarations.
- **Built-in Intrinsics**: `@sizeOf`, `@alignOf`, `@offsetOf`, `@ptrCast`, `@intCast`, `@floatCast`.
- **Static Analysis**: Lifetime analysis, null pointer detection, and double-free detection.

### Technical Constraints
To ensure compatibility with 1998-era hardware (e.g., Pentium I/II, 32MB RAM):
- **Language**: C++98 (maximum) for the bootstrap compiler.
- **Memory**: < 16MB peak usage preferred.
- **Dependencies**: Win32 API (`kernel32.dll`) only. No third-party libraries or modern STL.
- **Architecture**: 32-bit little-endian target assumptions.
- **MSVC 6.0 Compatibility**: Extensive use of `__int64` and C89-compliant constructs.

## Getting Started

### Prerequisites
- **Linux**: `gcc` (C++98 compatible), `make`.
- **Windows 98**: MSVC 6.0 SP6.

### Building the Compiler
Detailed instructions are available in [docs/Building.md](docs/Building.md).
On Linux:
```bash
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o zig0
```
On Windows (MSVC 6.0):
```batch
cl /Za /W3 /Isrc/include src\bootstrap\bootstrap_all.cpp /Fezig0.exe
```

### Running Tests
The project features a comprehensive suite of over 500 unit and integration tests.
```bash
./test.sh    # Runs all test batches
```

## Documentation
- [Language Specification](docs/reference/Language_Spec_Z98.md): Supported syntax and Z98-specific patterns.
- [Building Guide](docs/Building.md): Detailed toolchain setup and build instructions.
- [Design Documents](docs/design/DESIGN.md): Core architecture and Arena Allocation strategy.
- [C89 Emission](docs/reference/c89_emission.md): How Zig constructs map to C89.

## Examples
Check the `examples/` directory for sample Z98 programs:
- `examples/hello/`: Standard "Hello World".
- `examples/prime/`: Prime number calculation.
- `examples/fibonacci/`: Recursive Fibonacci sequence.
- `examples/heapsort/`: In-place Heapsort algorithm.
