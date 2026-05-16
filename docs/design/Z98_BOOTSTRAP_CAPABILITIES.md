# Z98 Bootstrap Architecture & Capability Specification

This document details the architectural patterns and internal "ways of doing things" in the Z98 bootstrap compiler (`zig0`). Understanding these is critical for planning a compatible and efficient `zig1`.

## 1. Memory Management: The Arena Pattern

The bootstrap compiler is strictly constrained to **<16MB peak RAM**. It achieves this by avoiding `malloc`/`free` and instead using a multi-tiered arena system.

### 1.1 Hierarchical Arenas
- **Global Arena**: Persists for the entire compilation. Stores Types, Symbols, and the String Interner.
- **CompilationUnit Arena**: Stores the AST and per-module metadata.
- **Transient Token Arena**: Used during lexing/parsing and **reset immediately** after the AST is built.
- **Transient Codegen Arena**: Used during the emission of each file and reset between files.

### 1.2 "Reset and Reuse" Strategy
Any data structure that grows during a pass (like the state maps in analyzers) must be allocated from an arena that can be cleared once the pass is complete.

## 2. Type System: Placeholder & Mutation Pattern

Z98 handles recursive and cross-module types using a **late-binding mutation pattern**.

1. **Registration**: When a type is first named (e.g., `struct Node`), a `TYPE_PLACEHOLDER` is created and put in the Symbol Table.
2. **Mangling**: The C-name (e.g., `zS_0_Node`) is assigned to the placeholder immediately to ensure stable references.
3. **Resolution**: As the Type Checker visits fields, it follows these placeholders.
4. **Mutation**: Once the type body is parsed, the placeholder `Type` struct is mutated **in-place** to a `TYPE_STRUCT`.
5. **Transitive Refresh**: Any type that depends on the placeholder (like `*Node`) is automatically updated because it holds a pointer to the same `Type` struct.

## 3. Separate Compilation Model

Z98 does NOT use a single large translation unit. It mimics the C project model.

- **Module-to-File Mapping**: Each `.zig` file becomes one `.c` and one `.h` file.
- **Topological Sorting**: Modules are sorted by import dependency. Headers are emitted for "pub" symbols.
- **Implicit Dependency Handling**: The `MetadataPreparationPass` recursively scans all types reachable from public signatures to ensure headers include all necessary transitive `typedef`s (like Slices or Error Unions).

## 4. AST Lifting Pass: Expression-to-Statement Transformation

C89 cannot represent Zig's expression-oriented control flow (e.g., `var x = if (c) a else b;`).

- **Hoisting**: The `ControlFlowLifter` pass identifies these "Control Flow Expressions".
- **Temporary Injection**: It creates a temporary variable in the C block, transforms the expression into a statement that assigns to that temp, and replaces the original expression with an identifier for the temp.
- **L-Value Capture**: For complex assignments like `arr[foo()] = try bar()`, the lifter "captures" the L-value to ensure side effects (like `foo()`) only happen once.

## 5. C89 Emitter Patterns

### 5.1 Two-Pass Block Emission
C89 requires all variable declarations at the absolute top of a `{}` block.
- **Pass 1**: Emitter scans the block, finds all `VarDecl` nodes, and emits `Type Name;`.
- **Pass 2**: Emitter runs the actual code. `VarDecl` nodes with initializers are emitted as assignments (`Name = Value;`).

### 5.2 Helper Specialization
- **Slice Helpers**: `__make_slice_T` functions are emitted as `static inline` in a global `zig_special_types.h` to ensure they are available to all modules without collision.
- **Print Lowering**: `std.debug.print` is never a real function call in generated C. It is a compiler intrinsic that the emitter decomposes into multiple `__bootstrap_print_*` calls.
- **Argc/Argv Support**: The compiler recognizes a specific `main` signature `pub fn main(argc: i32, argv: [*]*const u8)` and correctly lowers it to the standard C `int main(int argc, char* argv[])` entry point, ensuring parameters are accessible within Zig.

### 5.3 Deterministic Mangling
In "Test Mode", the emitter uses `z<Kind>_<Counter>_<Name>` to ensure integration tests remain stable even if file paths or internal hashes change.

## 6. Static Analysis Infrastructure

All analyzers (Lifetime, NullPointer, DoubleFree) use a **Flow-Sensitive State Map**.
- **State Merging**: At branch joins (end of `if`), states are merged conservatively (e.g., `Freed + Allocated = Unknown`).
- **LIFO Defer Queue**: Analyzers maintain a stack of `defer` actions and "execute" them (applying state changes) whenever a `return`, `break`, or `continue` is encountered.
