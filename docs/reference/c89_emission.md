# C89 Code Generation Strategy

This document outlines the strategy for emitting C89-compliant code from the RetroZig bootstrap compiler.

## 1. Integer Literals

Integer literals are always emitted in **decimal** format to simplify the emitter and ensure consistent output. The original base (hex, octal, binary) from the Zig source code is not preserved.

### 1.1 Mapping Table

The emission of integer literals depends on their resolved Zig type:

| Zig Type | C89 Emission | Example |
|----------|--------------|---------|
| `i32` | Decimal, no suffix | `42` |
| `u32` | Decimal + `U` suffix | `42U` |
| `i64` | Decimal + `i64` suffix | `42i64` |
| `u64` | Decimal + `ui64` suffix | `42ui64` |
| `i8`, `u8` | Decimal, no suffix | `42` |
| `i16`, `u16` | Decimal, no suffix | `42` |
| `usize` | Decimal, no suffix (maps to `unsigned int`) | `42` |
| `isize` | Decimal, no suffix (maps to `int`) | `42` |

### 1.2 64-bit Suffixes and Compatibility

The suffixes `i64` and `ui64` are specific to **MSVC 6.0**. To support other compilers (like GCC or Clang), a compatibility header (`zig_runtime.h`) is provided. This header defines macros to map these suffixes to the standard `LL` and `ULL` suffixes if possible, or provides other mechanisms for compatibility.

Every generated `.c` file should include `zig_runtime.h` at the top.

### 1.3 The Compatibility Header (`zig_runtime.h`)

The `zig_runtime.h` header serves several purposes:
- **Portable Typedefs**: Defines `i8`, `u8`, `i16`, `u16`, `i32`, `u32`, `i64`, `u64`, `usize`, and `isize` in a way that is compatible with both MSVC 6.0 and modern compilers in C89 mode.
- **64-bit Literal Suffixes**: Provides macros for `i64` and `ui64` suffixes. On MSVC, these are used directly. On other compilers, they are mapped to `LL` and `ULL` via the preprocessor.
- **Runtime Safety**: Contains the `__bootstrap_panic` handler used by runtime safety checks (like overflow detection in numeric casts).

## 2. Float Literals

Float literals are emitted using `sprintf` with the `%.15g` format specifier to ensure full precision for `double` values while maintaining a concise representation.

### 2.1 Mapping Table

| Zig Type | C89 Emission | Example |
|----------|--------------|---------|
| `f32`    | Decimal + `f` suffix | `3.14f` |
| `f64`    | Decimal, no suffix | `3.14` |

### 2.2 Formatting Rules

- **Whole Numbers**: To ensure C treats a literal as a float, if the generated string lacks a decimal point (`.`) or an exponent (`e`), a `.0` suffix is automatically appended (e.g., `2.0`).
- **Hexadecimal Floats**: Zig's hexadecimal floating-point literals are converted to their decimal equivalents during emission, as MSVC 6.0 does not support hex floats.
- **Scientific Notation**: Large or small values are automatically emitted in scientific notation by `sprintf` when appropriate.

## 3. String Literals

String literals are emitted wrapped in double quotes (`"`).

### 3.1 Escaping Rules

The decoded string content from the AST is re-encoded into C89-compliant syntax.

- **Symbolic Escapes**: Standard C89 symbolic escapes are used for common control characters:
  - `\a`, `\b`, `\f`, `\n`, `\r`, `\t`, `\v`, `\\`, `\"`.
- **Octal Escapes**: For any other non-printable character (ASCII 0-31 and 127) or byte values outside the printable ASCII range (32-126), a three-digit zero-padded octal escape is used (e.g., `\033` for ESC).
- **Printable ASCII**: Characters in the range 32-126 (inclusive) are emitted directly, except for the double quote (`"`) and backslash (`\`), which are escaped.

### 3.2 MSVC 6.0 Limitations

MSVC 6.0 has a limit of approximately 2048 characters for a single string literal. The bootstrap compiler currently does not automatically split long strings into multiple concatenated literals. Avoid using extremely long string literals in the Stage 1 compiler source.

## 4. Character Literals

Character literals are emitted wrapped in single quotes (`'`).

### 4.1 Escaping Rules

Character literals use the same escaping logic as string literals, with the following difference:
- The single quote character (`'`) is escaped (`\'`), while the double quote (`"`) is emitted directly.

Only ASCII codepoints (0-127) are supported in character literals during the bootstrap phase.

## 5. Rationale

- **Decimal-only emission**: Simplifies the internal implementation of the emitter and avoids the need to store the original literal format in the AST.
- **MSVC-first suffixes**: Prioritizes the primary target for bootstrapping (MSVC 6.0) while providing a path for cross-platform testing via the compatibility header.
- **Type-based emission**: Using the resolved type instead of raw lexer flags ensures consistency with the rest of the semantic analysis phase.
- **Octal escapes for non-printable characters**: Ensures maximum portability across C89 compilers, as hex escapes were not standardized until C90/C99.

## 6. Global Variables

Global variables are emitted at file scope.

### 6.1 Visibility and Linkage

- **`pub` symbols**: Emitted without the `static` keyword, giving them external linkage.
- **Private symbols**: Emitted with the `static` keyword, limiting their scope to the current translation unit.

### 6.2 Initializers

All global variables must have constant initializers. The bootstrap compiler rejects non-constant initializers at code generation time if they were not already caught by the semantic analyzer.

### 6.3 Name Mangling

Global identifiers are sanitized to avoid C89 keywords and reserved names (using a `z_` prefix). They are also truncated to 31 characters to ensure compatibility with MSVC 6.0 and other strict C89 compilers.

### 6.4 Enum Constants

Enum constants are **constant-folded** to their integer values during type checking. This avoids ordering issues in the generated C code where a global variable might be defined before its enum type. Consequently, the emitted C code for an enum initialization will use the literal integer value rather than the mangled name (e.g., `0` instead of `Color_Red`).

### 6.5 Struct and Array Initializers

Global struct and array initializers are emitted as positional C-style initializers (e.g., `{1, 2, 3}`). The emitter ensures that fields are emitted in the order they were declared in the Zig struct definition.

### 6.6 Anonymous Containers Rejection

To maintain simplicity and avoid generating synthetic names, the bootstrap compiler **rejects anonymous structs, unions, or enums** when used directly in a variable declaration (e.g., `var s: struct { x: i32 } = ...`). All such types must be defined using a named `const` declaration (e.g., `const S = struct { x: i32 }; var s: S = ...`).

## 7. Code Generation Examples

This section provides examples of Zig source code and the corresponding C89 code generated by the bootstrap compiler.

### 7.1 Global Variables and Constants

**Zig Source:**
```zig
pub const pi: f32 = 3.14159;
var counter: i32 = 0;
pub var global_ptr: *const i32 = &counter;
```

**Generated C89:**
```c
const float pi = 3.14159f;
static int counter = 0;
const int* global_ptr = &counter;
```

### 7.2 Structs and Initializers

**Zig Source:**
```zig
const Point = struct {
    x: i32,
    y: i32,
};

pub var origin: Point = .{ .x = 0, .y = 0 };
```

**Generated C89:**
```c
struct Point {
    int x;
    int y;
};

struct Point origin = {0, 0};
```

### 7.3 Enums and Constant Folding

**Zig Source:**
```zig
const Color = enum {
    Red,
    Green,
    Blue,
};

pub var current_color: Color = Color.Green;
```

**Generated C89:**
```c
enum Color {
    Color_Red = 0,
    Color_Green = 1,
    Color_Blue = 2
};
typedef enum Color Color;

enum Color current_color = 1;
```
*(Note: `Color.Green` is constant-folded to its integer value `1` during emission.)*

### 7.4 Arrays

**Zig Source:**
```zig
pub var data: [3]u8 = .{ ._0 = 1, ._1 = 2, ._2 = 3 };
```

**Generated C89:**
```c
unsigned char data[3] = {1, 2, 3};
```

## 8. Local Variables

Local variables are emitted within C functions or compound statements.

### 8.1 Declaration Splitting

In C89, all declarations must appear at the top of a block, before any statements. To support Zig's flexible variable declaration placement, the bootstrap compiler uses a two-pass emission strategy for blocks:

1. **Pass 1**: The emitter scans the block's statements for any variable declarations and emits them at the top of the C block.
2. **Pass 2**: The emitter then emits all statements in order. If a variable declaration had an initializer, it is emitted as an assignment statement at the point where it appeared in the Zig source.

### 8.2 `const` Handling

For local variables, the `const` qualifier is always **dropped** in the generated C code. Since Zig has already enforced `const` correctness during semantic analysis, the C compiler does not need to re-enforce it. This simplifies the declaration-splitting logic, as an assignment to a `const` variable (which happens during Pass 2) would be illegal in C.

### 8.3 `undefined` Initialization

If a local variable is initialized with `undefined` in Zig, it is emitted as an uninitialized variable in C (e.g., `int x;`). No assignment is generated in Pass 2.

### 8.4 Scoping and Uniquification

Zig allows shadowing of variables in nested blocks. C89 has block-level scoping for names, but the bootstrap compiler simplifies this by using a **single `CVariableAllocator` per function**.

Every local variable within a function is given a unique C name by appending a numeric suffix (e.g., `x`, `x_1`, `x_2`) if a name collision occurs. This ensures that even shadowed variables in Zig have distinct names in the generated C, avoiding any potential name conflict issues.

## 9. Functions

Function declarations and definitions are emitted as standard C89 constructs.

### 9.1 Signature Emission

- **Return Types**: Emitted before the function name. `void` is used for functions with no return value.
- **Parameters**: Emitted within parentheses. If a function has no parameters, `(void)` is emitted to be C89-compliant.
- **Parameter Names**: Parameter names are uniquified and sanitized using the `CVariableAllocator` for each function.

### 9.2 Linkage and Visibility

The emitter determines the C linkage based on Zig keywords:

| Zig Construct | C89 Linkage | Notes |
|---------------|-------------|-------|
| `pub fn foo() {}` | External (no `static`) | Accessible from other translation units. |
| `export fn foo() {}` | External (no `static`) | Same as `pub` in bootstrap phase. |
| `fn foo() {}` | Internal (`static`) | Limited to the current translation unit. |
| `extern fn foo();` | External (`extern` prefix) | Prototype only, no body allowed. |

### 9.3 Name Mangling

Function names follow the global name mangling rules:
- **Keyword Avoidance**: Conflicting names (e.g., `register`, `int`) are prefixed with `z_`.
- **Length Limit**: Truncated to 31 characters for MSVC 6.0 compatibility.
- **Uniquification**: Suffixes are added to resolve collisions within the file.

### 9.4 Body Emission

Function bodies are emitted as a compound statement (`{ ... }`). The emitter uses a **two-pass block emission** strategy (see Section 8.1) to ensure all local variable declarations appear at the top of the block, satisfying C89 requirements.

### 9.5 Restrictions and Rejections

- **Array Return Types**: Functions returning arrays (e.g., `fn f() [3]i32`) are strictly rejected by the `TypeChecker` as C89 does not support returning arrays by value.
- **Extern with Body**: `extern fn` declarations must end with a semicolon and cannot have a body.
- **Calling Conventions**: Custom calling conventions (e.g., `callconv(.Stdcall)`) are currently ignored and fallback to the default `__cdecl` for MSVC 6.0.

## 10. Binary Operators

The bootstrap compiler maps Zig binary operators directly to their C89 equivalents.

### 10.1 Mapping Table

| Zig Operator | C89 Operator | Notes |
|--------------|--------------|-------|
| `+`, `-`, `*`, `/`, `%` | `+`, `-`, `*`, `/`, `%` | Arithmetic |
| `==`, `!=`, `<`, `>`, `<=`, `>=` | `==`, `!=`, `<`, `>`, `<=`, `>=` | Comparison |
| `and` | `&&` | Logical AND |
| `or` | `||` | Logical OR |
| `&`, `|`, `^`, `<<`, `>>` | `&`, `|`, `^`, `<<`, `>>` | Bitwise |
| `+=`, `-=`, `*=`, `/=`, `%=` | `+=`, `-=`, `*=`, `/=`, `%=` | Arithmetic compound assignment |
| `&=`, `|=`, `^=`, `<<=`, `>>=` | `&=`, `|=`, `^=`, `<<=`, `>>=` | Bitwise compound assignment |
| `+%`, `-%`, `*%` | `+`, `-`, `*` | Wrapping operators map to standard arithmetic |

### 10.2 Precedence and Parentheses

The bootstrap parser correctly handles Zig's operator precedence rules during AST construction. Parentheses in the Zig source are preserved as `NODE_PAREN_EXPR` in the AST. The emitter simply outputs the expressions in the order they appear in the AST, relying on either the AST structure or explicit parentheses to maintain correct evaluation order in the generated C code.

### 10.3 Logical Operators Short-circuiting

Zig's `and` and `or` operators map to C's `&&` and `||`, both of which exhibit the same short-circuiting behavior.

## 11. Unary Operators

The bootstrap compiler maps Zig unary operators to their C89 prefix equivalents.

### 11.1 Mapping Table

| Zig Operator | C89 Operator | Notes |
|--------------|--------------|-------|
| `-x`         | `-x`         | Arithmetic negation |
| `!x`         | `!x`         | Logical NOT |
| `~x`         | `~x`         | Bitwise NOT |
| `&x`         | `&x`         | Address-of |
| `x.*`        | `*x`         | Dereference (mapped to C89 prefix `*`) |
| `+x`         | `+x`         | Unary plus |

### 11.2 Dereference Syntax

Zig uses the postfix operator `.*` for pointer dereference (e.g., `ptr.*`). The bootstrap compiler translates this into the standard C89 prefix dereference operator `*` (e.g., `*ptr`).

## 12. Member Access

Zig's dot operator (`.`) for member access is mapped to either the C dot operator (`.`) or the arrow operator (`->`), depending on whether the base expression is a pointer.

### 12.1 Auto-dereference

The bootstrap compiler implements Zig's auto-dereference for single-level pointers to structs or unions.

| Zig Syntax | Base Type | C89 Emission |
|------------|-----------|--------------|
| `s.field`  | `struct S` | `s.field`    |
| `p.field`  | `*struct S`| `p->field`    |
| `u.field`  | `union U`  | `u.field`    |

### 12.2 Parentheses for Low-Precedence Bases

In C, postfix operators (including `.` and `->`) have higher precedence than unary operators (like `*` and `&`). To maintain Zig's semantics, the bootstrap compiler automatically adds parentheses around the base expression if it has lower precedence in C.

| Zig Syntax | C89 Emission | Reason |
|------------|--------------|--------|
| `ptr.*.f`  | `(*ptr).f`   | Base is a dereference (unary `*`) |
| `(&s).f`   | `(&s)->f`    | Base is an address-of (unary `&`) |
| `a.b.c`    | `a.b.c`      | Base is level 1 (no parens) |
| `arr[0].f` | `arr[0].f`   | Base is level 1 (no parens) |

### 12.3 Enum Member Access

Enum member access in Zig (e.g., `Color.Red`) is handled by the `TypeChecker` using constant folding. However, if the emitter encounters an enum member access (e.g., in some contexts where folding didn't happen or for test compatibility), it emits the mangled name.

| Zig Syntax | C89 Emission |
|------------|--------------|
| `Color.Red`| `Color_Red`   |
