# Z98 0.10.0 “Xylene” Release Notes

We are pleased to announce the first official release of the Z98 compiler, version **0.10.0**, codenamed **“Xylene”**.

Z98 is an independent, self‑hosting subset of the Zig language, designed to target 1998‑era hardware and software (Windows 95/98/ME). By generating clean, portable ANSI C89 code, Z98 brings a selection of modern language features—error unions, `defer`, slices—to legacy systems with extreme resource constraints.

The name **Xylene** (pronounced *ZY-leen*) was chosen because, like the chemical compound, this release serves as a fundamental building block for the Z98 ecosystem—a stable, essential foundation upon which future stages will be built. Xylene is also a solvent used to dissolve complex substances; similarly, this release aims to dissolve the complexity of bringing modern language concepts to older platforms.

## 🚀 Hero Milestone: Cross‑Compiler Stability
The primary goal of this release is to establish a rock‑solid bootstrap compiler. We have focused on making `zig0` itself compile and run reliably across a variety of environments, verifying that:

- It builds with **G++**, **Clang++**, and **MinGW‑w64** (with minor identifier adjustments to avoid collisions with Windows headers).
- The generated C89 code compiles cleanly with **`gcc -m32`**, **`musl‑gcc`**, and is designed to be compatible with **MSVC 6.0**.
- Peak memory usage stays well below **16 MB**, making it viable for actual Pentium‑class hardware with limited RAM.

We consider this the most important achievement of the release: a compiler that can be built and run on the systems it targets, and whose output is portable C89.

For detailed test results, see [Cross-Compatibility Tests](docs/reference/cross_compatibility_tests.md).

## ✨ Key Features

### 📦 Separate Compilation & Multi‑Module Support
The compiler now fully supports multiple modules. It resolves `@import` dependencies, emits each module as its own `.c` and `.h` file, and automatically generates `build_target.sh` / `build_target.bat` scripts to build the final executable. This reflects the way real‑world C projects are structured and paves the way for larger applications.

### 🛠️ AST Lifting (Expression‑to‑Statement Transformation)
Zig’s expression‑oriented syntax doesn’t always map directly to C89’s statement‑based nature. We implemented an **AST Lifting** pass that transforms expression‑form `if`, `switch`, `try`, `catch`, and `orelse` into safe, statement‑based blocks with temporary variables. This allows these constructs to be used in complex contexts while keeping the generated C code simple and C89‑compliant.

### ⚠️ Advanced Error Handling
The compiler now supports error unions (`!T`), `try`, `catch`, and full `defer` / `errdefer` semantics. These features are not just parsed; they are correctly lowered to C89 code that runs on the target platforms. `errdefer` execution is conditional on error returns, which is handled by a per‑function error flag.

### 🧬 Rich Type System
- **Slices (`[]T`)**: First‑class support for pointer+length pairs, with slicing syntax `arr[start..end]` and automatic array‑to‑slice coercion.
- **Tagged Unions (`union(enum)`)**: Safe unions with payload captures in `switch` statements.
- **Optional Types (`?T`)**: Type‑safe nullability with the `orelse` operator.
- **Recursive Types**: Complex, mutually recursive structures are handled via a two‑phase placeholder resolution system.

## 📚 Documentation
- [Z98 Language Specification](docs/reference/Language_Spec_Z98.md)
- [C89 Emission Reference](docs/reference/c89_emission.md)
- [Building Z98](docs/Building.md)
- [Z98 Design Philosophy](docs/design/DESIGN.md)

## 📂 Featured Examples
- **[Hello World](examples/hello/)**: The classic starting point.
- **[Prime Sieve](examples/prime/)**: Basic arithmetic and loops.
- **[Heapsort](examples/heapsort/)**: In‑place sorting with arrays.
- **[Quicksort](examples/quicksort/)**: Function pointers and recursion.
- **[Lisp Interpreter](examples/lisp_interpreter_curr/)**: A non‑trivial application that exercises the type system, error handling, and memory management.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez* 
*Jules (AI-Agent used to help out)* 

---
**Note:** Z98 is an independent project and is not affiliated with the official Zig project. It does not aim to replace Zig or C89, but rather to offer a compatible subset that can run on extremely limited hardware. This release is the first step in that journey; we expect it to have limitations and welcome feedback.
