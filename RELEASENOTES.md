# Z98 0.12.1 “Isophthalic anhydride” Release Notes

We are proud to announce the release of Z98 version **0.12.1**, codenamed **“Isophthalic anhydride”**.

As an anhydride is the dehydrated form of an acid, this patch release represents a "drier," more refined version of our previous "Isophthalic acid" release. Version 0.12.1 focuses on hardening the `zig0` bootstrap compiler by resolving critical C89 compatibility edge cases and improving the robustness of our type system and code generation.

## 🏗️ Hardening C89 Compatibility

The primary focus of this release is ensuring that Z98 remains the most compatible Zig-to-C89 compiler for legacy environments like MSVC 6.0 and OpenWatcom.

### 📦 Aggregate Initializer Lifting
We have addressed a significant C89 compatibility gap regarding aggregate initializers (structs, unions, and tuples) in expression contexts.
- **The Issue**: Previously, passing a struct literal directly to a function (e.g., `func(.{ .x = 1 })`) would sometimes emit invalid C99 compound literals or braced initializers in an expression context, which legacy compilers reject with `error C2059: syntax error : '{'`.
- **The Solution**: The `ControlFlowLifter` now automatically identifies aggregate literals in non-constant expression contexts and "lifts" them into uniquely named temporary variables. These variables are then decomposed into field-by-field assignments, ensuring 100% ANSI C89 compliance.

### 🏷️ Enhanced Tagged Union Coercion
Z98 now supports distributed coercion for tagged unions within control-flow expressions.
- You can now return "naked" tag literals (e.g., `.Alive`) from different branches of an `if` or `switch` expression, provided the expected result type is a tagged union.
- The `TypeChecker` now proactively unifies branch types by coercing literals into their full tagged union representations before final validation, simplifying the implementation of complex state machines.

## 🛠️ Internal Compiler Improvements

### 🧬 Standardized Identifier Mangling
We have refined our internal mangling strategy to better support compiler-generated symbols.
- Identifiers starting with `__` (reserved for internal use) are now bypassed by the module-prefixing and keyword-mangling logic.
- This ensures that internal runtime helpers and compiler-generated temporaries maintain consistent names across translation units, resolving several "undeclared identifier" issues in complex multi-module builds.

### 🌐 Cross-Module Type Visibility
Following an investigation into cross-module resolution failures, we have improved how the compiler handles qualified member access for types and modules.
- The `TypeChecker` now more robustly unwraps meta-types and resolves placeholders when accessing union tags and type aliases across module boundaries (e.g., `Module.Union.Tag`).
- Structural equality checks have been enhanced to account for nominal type identity in cross-module contexts, preventing spurious "type mismatch" errors.

## 🔌 Platform & Runtime
- **Standardized Print IO**: Unified all `plat_print_*` functions to route through the global `Logger` instance, improving consistency across 32-bit targets.
- **`@intToPtr` Support**: Added support for the `@intToPtr` builtin to assist with low-level memory mapping and driver development.

## 📂 New Documentation
- **[Z98 Bootstrap Manual](docs/reference/z98_bootstrap_manual.md)**: A new comprehensive guide detailing idiomatic patterns, subset constraints, and the PAL API, with extensive examples from the `rogue_mud` and `lisp_interpreter_curr` projects.

## 📜 100% Test Stability
The Z98 test suite continues to pass at 100% stability across all **82 batches**. This release includes new integration tests (Batches 9b and 61) specifically targeting the new lifting and coercion logic.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---

# Z98 0.12.0 “Isophthalic acid” Release Notes

We are proud to announce the release of Z98 version **0.12.0**, codenamed **“Isophthalic acid”**.

**Isophthalic acid** marks a monumental milestone in the Z98 project. This release represents the final feature-set for our C++ bootstrap compiler (`zig0`) and the official commencement of our journey toward a self-hosted Zig compiler. This release introduces fundamental language features like Tuples, a robust Networking PAL, and a significant evolution in our static analysis capabilities.

## 🛡️ Double-Free Analyzer 2.0

Stability and memory safety are paramount when targeting resource-constrained legacy systems. In this release, the `DoubleFreeAnalyzer` has undergone a major upgrade (Phases 5-8), transforming it from a basic check into a sophisticated static analysis tool:

- **Composite Tracking**: The analyzer now tracks lifetimes across complex aggregate members (e.g., `s.ptr`) and nested structures (arrays, tuples).
- **Transfer History Diagnostics**: Error messages now include a complete transfer history, showing exactly where ownership was originally established and through which assignments it was transferred before a violation occurred.
- **Path-Aware `errdefer`**: The analyzer now correctly understands that `errdefer` blocks only execute on error paths, eliminating false positives in complex cleanup logic.
- **Arena Leak Detection**: Introducing the `-Warena-leak` flag, which helps developers identify memory that was allocated in an arena but never properly managed, ensuring peak efficiency.

## 🏗️ Expanding the Language: Tuples & Networking

### 🧊 Full Tuple Support
Z98 now supports **Tuples**. This includes tuple types (`struct { i32, f32 }`), literals (`.{ 42, 3.14 }`), and zero-indexed member access (`t.0`). In the C89 backend, tuples are lowered into specialized structs with indexed fields, providing a seamless and efficient mapping to the target hardware.

### 🌐 Networking PAL & Socket API
To support the next generation of Z98 applications, we have introduced a minimal **Socket API** to our Platform Abstraction Layer (PAL). This API provides a cross-platform interface for TCP server creation, non-blocking I/O via `select()`, and standard `send`/`recv` operations. It is fully compatible with both Winsock 1.1 on Windows 95/98 and standard POSIX sockets.

## 🔌 Compatibility & Tooling

### 🛠️ OpenWatcom 1.9 Support
Continuing our commitment to legacy toolchains, the bootstrap compiler and its generated code are now fully compatible with the **OpenWatcom 1.9** compiler suite. We have included optimized build scripts (`build_openw.bat`) and standardized PAL headers to ensure a smooth development experience on native 90s hardware.

### 📜 100% Test Stability
The Z98 test suite now comprises **82 batches** of tests, all of which are passing with 100% stability. This includes rigorous verification of the new Tuple support, Networking PAL, and advanced static analysis rules.

## 🚀 The Road to Self-Hosting
With the completion of Milestone 11, we are freezing the feature set of the bootstrap compiler. Our focus now shifts to the **Self-Hosting Phase**. We have already drafted comprehensive design documents for the self-hosted compiler, covering the new LIR-based architecture, advanced type system, and modular design. These documents can be found in `docs/sf/`.

## 📂 New & Updated Examples
- **[MUD Server](examples/mud_server/)**: A minimal telnet Multi-User Dungeon server demonstrating the new Networking PAL and Tuple support.
- **[Game of Life](examples/game_of_life/)**: Enhanced with patterns and optimized C89 lowering.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---

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
