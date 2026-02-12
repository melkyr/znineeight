# RetroZig Compiler
**A self-hosting Zig → C89 bootstrap compiler for Windows 9x.**

## Project Overview
RetroZig is an ambitious project to build a Zig compiler from scratch that targets the Windows 9x era (Windows 95, 98, ME). To achieve this while adhering to the hardware and software constraints of that period, the compiler uses a "Progressive Enhancement" strategy.

We start with a **Stage 0** bootstrap compiler written in C++98, which compiles a **Stage 1** compiler written in a subset of Zig. Finally, **Stage 1** compiles itself to become the fully self-hosted **Stage 2** compiler.

## Current Status: Milestone 4 Complete
The project has successfully completed Milestone 4: **Semantic Analysis**.
The Stage 0 compiler now features a robust frontend capable of lexing, parsing, and type-checking a significant subset of the Zig language.

### Key Supported Features
- **Primitive Types**: `i8` through `i64`, `u8` through `u64`, `isize`, `usize`, `f32`, `f64`, `bool`, `void`.
- **Pointers**: Single-level pointers (`*T`, `*const T`), address-of (`&`), dereference (`.*`), and pointer arithmetic.
- **Aggregates**: Named `struct`, `enum`, and bare `union` types.
- **Control Flow**: `if-else` (with `else if`), `while` loops (with `break`/`continue`), `switch` expressions, and `for` loops.
- **Functions**: Function declarations (up to 4 parameters) with support for recursion and forward references.
- **Error Handling Syntax**: Recognition of `try`, `catch`, `orelse`, and `errdefer` (currently catalogued for Milestone 5 translation).
- **Built-in Intrinsics**:
    - Compile-time: `@sizeOf(T)`, `@alignOf(T)`, `@offsetOf(T, "field")`.
    - Explicit Casts: `@ptrCast(T, expr)`, `@intCast(T, expr)`, `@floatCast(T, expr)`.
- **Static Analysis**: Lifetime analysis (dangling pointers), null pointer detection, and double-free detection for arena allocations.

### Key Limitations (Bootstrap Phase)
- **No Slices**: `[]T` is not supported in the bootstrap phase.
- **No Error Unions/Optionals**: `!T` and `?T` are recognized but strictly rejected (to be implemented in Milestone 5).
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **No Multi-level Pointers**: `**T` and deeper are rejected for simplicity.
- **No Function Pointers**: Functions cannot be used as first-class values.
- **No Code Generation**: Full C89 code generation is the target for Milestone 5.

## Technical Constraints
To ensure compatibility with 1998-era hardware (e.g., Pentium I/II, 32MB RAM):
- **Language**: C++98 (maximum).
- **Memory**: < 16MB peak usage preferred.
- **Dependencies**: Win32 API (`kernel32.dll`) only. No third-party libraries or modern STL containers.
- **Architecture**: 32-bit little-endian target assumptions.

## Getting Started

### Prerequisites
- **Linux/macOS**: `g++` (C++98 compatible), `make`.
- **Windows**: MSVC 6.0 (or modern MSVC with compatibility flags).

### Building the Compiler
To build the Stage 0 compiler:
```bash
./build.sh   # Linux/macOS
# OR
build.bat    # Windows
```

### Running Tests
The project features a comprehensive suite of over 380 unit and integration tests.
```bash
./test.sh    # Runs all test batches
```

## Documentation
Detailed documentation is available in the `docs/` directory:
- [Design Documents](docs/design/DESIGN.md): Core architecture and design philosophy.
- [Reference Manuals](docs/reference/builtins.md): Detailed specifications for language features and built-ins.
- [Testing Guide](docs/testing/TESTING.md): Overview of the testing strategy and framework.
