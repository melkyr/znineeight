# Z98 0.10.0 "Xylene" Release Notes

We are excited to announce the first official release of the Z98 compiler, version **0.10.0**, codenamed **"Xylene"**.

Z98 is an independent, self-hosting subset of the Zig language designed specifically to target 1998-era hardware and software (Windows 95/98/ME). By generating clean, portable ANSI C89 code, Z98 brings modern language features like error unions, defer, and slices to legacy systems with extreme resource constraints.

The name **Xylene** reflects this release's role as a fundamental building block for the Z98 ecosystem, providing the stable bootstrap foundation upon which future stages will be built.

## 🚀 Hero Milestone: Ultimate Cross-Compatibility
The central goal of Z98 is to be the most portable Zig-like toolchain ever created. In this release, we have achieved a major milestone in cross-compiler stability. The Z98 Stage 0 bootstrap compiler (`zig0`) has been verified to compile and function correctly across a diverse range of environments:

- **Modern Linux**: Seamless builds with `g++` and `clang++`.
- **Windows Legacy Interop**: Verified compilation via `MinGW-w64`, including fixes for naming collisions with internal Windows headers (e.g., `winnt.h`, `wingdi.h`).
- **Portable C Output**: The generated C89 code has been verified to compile with `musl-gcc`, `gcc -m32`, and is designed for compatibility with `MSVC 6.0`.
- **Target Constraints**: Successfully maintained a peak memory footprint of **< 16MB**, making it viable for actual Pentium-class hardware with limited RAM.

For detailed test results, see [Cross-Compatibility Tests](docs/reference/cross_compatibility_tests.md).

## ✨ Key Features

### 📦 Separate Compilation & Multi-Module Support
Z98 now supports a sophisticated separate compilation model.
- **Topological Sorting**: Modules are automatically sorted by their `@import` dependencies.
- **Individual Emission**: Each `.zig` file generates its own `.c` and `.h` pair, allowing for efficient build times and traditional C linking.
- **Automated Build Scripts**: The compiler automatically generates `build_target.sh` and `build_target.bat` for the output files.

### 🛠️ AST Lifting (Expression-to-Statement Transformation)
To bridge the gap between Zig's expression-oriented syntax and C89's statement-oriented nature, Z98 implements a robust **AST Lifting** pass. This allows features like `if`, `switch`, `try`, `catch`, and `orelse` to be used as expressions in complex contexts by automatically lowering them into safe, statement-based blocks with temporary variables.

### ⚠️ Advanced Error Handling
Experience Zig's powerful error handling even on 90s hardware:
- **Error Unions (`!T`)**: Efficiently return values or errors.
- **`try` & `catch`**: Intuitive error propagation and handling.
- **`defer` & `errdefer`**: Guaranteed cleanup and rollback logic, fully supported even in complex control flow with labeled loops.

### 🧬 Rich Type System
- **Slices (`[]T`)**: First-class support for pointer+length pairs with automatic slicing syntax `arr[start..end]`.
- **Tagged Unions (`union(enum)`)**: Safe, managed unions with payload captures in `switch` statements.
- **Optional Types (`?T`)**: Type-safe nullability with the `orelse` operator.
- **Recursive Types**: Support for complex, mutually recursive data structures via a two-phase placeholder resolution system.

## 📚 Documentation
- [Z98 Language Specification](docs/reference/Language_Spec_Z98.md)
- [C89 Emission Reference](docs/reference/c89_emission.md)
- [Building Z98](docs/Building.md)
- [Z98 Design Philosophy](docs/design/DESIGN.md)

## 📂 Featured Examples
Explore what's possible with Z98:
- **[Hello World](examples/hello/)**: The classic starting point.
- **[Prime Sieve](examples/prime/)**: Demonstrating basic arithmetic and loops.
- **[Heapsort](examples/heapsort/)**: In-place sorting with arrays.
- **[Quicksort](examples/quicksort/)**: Utilizing function pointers and recursion.
- **[Lisp Interpreter](examples/lisp_interpreter_curr/)**: A complex, real-world application showing off the power of Z98's type system and memory management.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*(Space reserved for contributor credits)*

---
**Note:** Z98 is an independent project and is not affiliated with the official Zig project.
