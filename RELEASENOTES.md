# Z98 0.11.0 “para-Cresol” Release Notes

We are proud to announce the release of Z98 version **0.11.0**, codenamed **“para-Cresol”**.

Following the foundational work of "Xylene", **para-Cresol** represents a phase of refinement and aromatic enhancement. Just as para-cresol is an essential precursor in the creation of fine fragrances and antioxidants, this release focuses on smoothing out the remaining rough edges of the bootstrap compiler and introducing the final set of language features required for the next stage of our journey: the self-hosted Zig compiler.

This release completes Milestone 11, bringing a suite of quality-of-life improvements and robustness fixes that make the Z98 subset feel more expressive and reliable.

## ✨ Milestone 11: The Refinement Phase

### 🎨 Expressive Control Flow
Z98 now supports **Braceless Control Flow**. For simple `if`, `while`, `for`, and `defer` statements, braces are now optional, allowing for more concise and idiomatic Zig code. The compiler's lifting pass has been updated to handle these cases seamlessly, ensuring they are correctly transformed into safe C89 blocks.

### 🔢 Switch Enhancements
We have introduced support for **Switch Ranges**. You can now use inclusive (`...`) and exclusive (`..`) ranges within switch prongs, significantly simplifying logic for character classes and numeric intervals.

### 🎣 Robust Payload Captures
Payload captures are now fully supported in both `while` loops and `switch` expressions. This allows for safe and elegant unwrapping of Optional types and Tagged Unions, with the compiler ensuring that captures are correctly scoped and initialized even in complex nested loops.

### 🖨️ Print Lowering
A major architectural addition in this release is **Print Lowering**. Calls to `std.debug.print` are now automatically decomposed by the compiler into a series of efficient, direct runtime calls (`__bootstrap_print`, `__bootstrap_print_int`). This eliminates the need for a complex `printf` implementation in the bootstrap runtime and improves reliability on legacy systems.

## 🛠️ Stabilization & Compatibility

### 🏗️ C89 Compliance: Block-Top Declarations
To adhere to the strictest C89 standards (and ensure compatibility with MSVC 6.0), the `C89Emitter` now guarantees that all compiler-generated temporary variables—such as those used for loop indices or expression lifting—are declared at the absolute top of their respective C blocks.

### 🔄 Recursion & Type Resolution
This release fully resolves several deep-seated issues related to recursion. The Lisp interpreter example now runs flawlessly thanks to a "mutable slot" strategy for recursive definitions and a more robust `TYPE_ANONYMOUS_INIT` resolution system for nested aggregate initializers.

### 🔌 Standardized Runtime API
We have standardized the signatures of our core runtime IO functions. `__bootstrap_print`, `__bootstrap_write`, and `__bootstrap_panic` now consistently use `const char*` signatures, resolving signedness warnings and improving interop with standard C libraries.

## 📂 New & Updated Examples
- **[Mandelbrot](examples/mandelbrot/)**: A new example demonstrating floating-point performance and the new braceless syntax.
- **[Lisp Interpreter](examples/lisp_interpreter_curr/)**: Now fully functional with recursive `define` and improved 32-bit alignment.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---
**Note:** Z98 is an independent project and is not affiliated with the official Zig project. It continues to serve as a bridge between the modern world of Zig and the classic hardware of the late 90s.

***

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
