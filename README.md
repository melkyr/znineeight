# RetroZig Compiler

**A self-hosting Zig compiler for Windows 9x.**

## What is this?

This project is an attempt to build a Zig compiler from scratch, targeting the Windows 9x series of operating systems (Windows 95, 98, ME) and the hardware of that era. The compiler is written in a subset of Zig and is designed to be self-hosting, meaning it will eventually be able to compile its own source code.

## Project Philosophy

The core philosophy of this project is **"Progressive Enhancement."** We start with a minimal C++98 bootstrap compiler (Stage 0) that can compile a more feature-complete Zig-written compiler (Stage 1). The ultimate goal is to have a self-hosted compiler (Stage 2) that can compile itself without any external dependencies.

We are also committed to the following principles:

*   **Minimalism:** The compiler should be as small and efficient as possible, with a target peak memory usage of less than 16MB.
*   **Zero Dependencies:** The final compiler should not have any external dependencies, other than the Win32 API.
*   **Historical Accuracy:** We are targeting the MSVC 6.0 (Visual C++ 98) toolchain and the x86 32-bit architecture of the late 1990s.

## Current Status

Phase 0, the implementation of the core infrastructure for the bootstrap compiler in C++98, is now complete. The project has a solid foundation, including memory management, string interning, error handling, and a basic testing framework.

The next step is to begin Phase 1, which will focus on implementing the lexer. This is the first step in turning the bootstrap compiler into a tool that can understand and process Zig source code.

## Getting Started

To get started with the project, you will need the following:

*   A Windows 98 virtual machine
*   Microsoft Visual C++ 6.0

Once you have the required software, you can clone the repository and start working on the bootstrap compiler.

## How to Build and Test

This project uses simple batch scripts for building and testing from the command line.

*   `build.bat`: Compiles the C++ bootstrap compiler (`zig0.exe`).
*   `test.bat`: Builds the compiler and runs all available tests, including the compiler's self-test and the unit test suite.
*   `clean.bat`: Deletes all build artifacts (`.exe`, `.obj`).

To build the compiler, run:
```batch
build.bat
```

To run the entire test suite, run:
```batch
test.bat
```

## How to Contribute

We welcome contributions from the community. If you are interested in helping out, please read the `architecture.md` file to learn more about the compiler's design and the `AI_tasks.md` file for a list of tasks that need to be done.
