# Detailed Findings from the JSON Parser "Baptism of Fire"

This document records the issues, bugs, and limitations discovered while attempting to compile and run both downgraded and advanced Z98 JSON parsers.

## 1. Summary of Performance
- **Peak Memory Usage (Compiler)**: ~517 KB (0.5 MB) during compilation of the advanced multi-file parser.
- **Limit Verification**: Well within the 16MB technical constraint (< 4% of target limit).

## 2. Syntax & Parser Constraints

### Braceless Switch Bodies for Void Payloads
- **Status**: **QUIRK IDENTIFIED**
- **Observation**: Switch prongs matching a `void` payload (e.g., `.Null => ...`) that consisted of a single expression-statement would sometimes fail to emit correctly or cause "Unimplemented statement type" in C output if not wrapped in a block `{}`.
- **Workaround**: Always use an explicit block for switch prong bodies: `.Null => { doSomething(); },`.

### Slicing Syntax (Implicit End)
- **Status**: **LIMITATION**
- **Observation**: Syntax like `slice[pos..]` is not supported.
- **Workaround**: Use explicit end index: `slice[pos..slice.len]`.

### Struct Methods
- **Status**: **DESIGN LIMITATION** (Confirmed)
- **Observation**: Attempting to use `fn method(self: *S) ...` inside a `struct` declaration results in a syntax error.
- **Workaround**: Use top-level functions that take a pointer to the struct: `fn structMethod(self: *S) ...`.

## 3. Type System & Semantic Analysis

### Strict Numeric Coercion
- **Status**: **DESIGN LIMITATION** (Confirmed)
- **Observation**: `i32` literals do not implicitly coerce to `usize` in many contexts, including struct initializers and switch conditions.
- **Workaround**: Use explicit `@intCast(usize, value)` or ensure variables are declared with the exact expected type.

### Tagged Union Equality and Assignment
- **Status**: **QUIRK IDENTIFIED**
- **Observation**: Direct assignment of tagged unions (e.g., `val_ptr.* = val;`) can sometimes produce invalid C code depending on the complexity of the l-value.
- **Workaround**: Use an explicit `switch` to decompose the union and re-assign it to the target, or ensure simple l-values are used.

## 4. Code Generation & Runtime

### Implicit `strtod` Declaration
- **Status**: **BUGFIT**
- **Observation**: The compiler might not automatically emit a prototype for C standard library functions like `strtod` unless explicitly declared as `extern`.
- **Workaround**: Add `pub extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;` in the Zig source.

### Pointer-to-Const to Pointer-to-Mutable Slices
- **Status**: **C89 COMPATIBILITY LIMITATION**
- **Observation**: Generated code for `__make_slice_T` might discard `const` qualifiers, leading to C compiler warnings.
- **Impact**: Non-fatal, but generates many warnings.

## 5. Successful Features Verified (Milestone 9)
- **Tagged Unions (`union(enum)`)**: Core functionality is working and stable.
- **Switch Payload Captures (`|val|`)**: Correctly extracts data from unions.
- **Naked Tags**: Support for `.Null` without `: void` is functional.
- **Range-based Switch**: `case '0'...'9' => ...` works correctly.
- **Modular @import**: Multi-file compilation and symbol resolution are fully operational.
- **Error Unions & `try`/`catch`**: Robust error propagation works across modules.
- **Arena Allocation**: Integration with `arena_alloc_default` is seamless.
