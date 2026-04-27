# Z98 0.12.1 “Isophthalic anhydride” Release Notes

We are pleased to announce the release of Z98 version **0.12.1**, codenamed **“Isophthalic anhydride”**.

As an anhydride is the dehydrated form of an acid, this patch release represents a "drier," more refined version of our previous "Isophthalic acid" release. Version 0.12.1 focuses on hardening the `zig0` bootstrap compiler by resolving critical C89 compatibility edge cases and improving the robustness of our type system and code generation.

## 🏗️ Hardening C89 Compatibility

The primary focus of this release is ensuring that Z98 remains the most compatible Zig-to-C89 compiler for legacy environments like MSVC 6.0 and OpenWatcom.

### 📦 Aggregate Initializer Lifting
We have addressed a significant C89 compatibility gap regarding aggregate initializers (structs, unions, and tuples) in expression contexts.
- **The Issue**: Previously, passing a struct literal directly to a function (e.g., `func(.{ .x = 1 })`) would sometimes emit invalid C99 compound literals or braced initializers in an expression context, which legacy compilers reject.
- **The Solution**: The `ControlFlowLifter` now automatically identifies aggregate literals in non-constant expression contexts and "lifts" them into uniquely named temporary variables. These variables are then decomposed into field-by-field assignments, ensuring 100% C89 compliance.

### 🏷️ Enhanced Tagged Union Coercion
Z98 now supports distributed coercion for tagged unions within control-flow expressions.
- You can now return "naked" tag literals (e.g., `.Alive`) from different branches of an `if` or `switch` expression, provided the expected result type is a tagged union.
- The `TypeChecker` now proactively unifies branch types by coercing literals into their full tagged union representations before final validation.

## 🛠️ Internal Compiler Improvements

### 🧬 Standardized Identifier Mangling
We have refined our internal mangling strategy to better support compiler-generated symbols.
- Identifiers starting with `__` (reserved for internal use) are now bypassed by the module-prefixing and keyword-mangling logic.
- This ensures that internal runtime helpers and compiler-generated temporaries maintain consistent names across translation units, resolving several "undeclared identifier" issues in complex multi-module builds.

### 🌐 Cross-Module Type Visibility
Following an investigation into cross-module resolution failures, we have improved how the compiler handles qualified member access for types and modules.
- The `TypeChecker` now more robustly unwraps meta-types and resolves placeholders when accessing union tags and type aliases across module boundaries (e.g., `Module.Union.Tag`).
- Structural equality checks have been enhanced to account for nominal type identity in cross-module contexts.

## 🔌 Platform & Runtime
- **Standardized Print IO**: Unified all `plat_print_*` functions to route through the global `Logger` instance, improving consistency across 32-bit targets.
- **`@intToPtr` Support**: Added support for the `@intToPtr` builtin to assist with low-level memory mapping and driver development.

## 📂 Updated Documentation
- **[Z98 Bootstrap Manual](docs/reference/z98_bootstrap_manual.md)**: A new comprehensive guide detailing idiomatic patterns, subset constraints, and the PAL API.

## 📜 100% Test Stability
The Z98 test suite continues to pass at 100% stability across all **82 batches**. This release includes new integration tests (Batches 9b and 61) specifically targeting the new lifting and coercion logic.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---
**Note:** Z98 is an independent project and is not affiliated with the official Zig project. It continues to serve as a bridge between the modern world of Zig and the classic hardware of the late 90s.
