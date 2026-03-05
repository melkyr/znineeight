# Z98 JSON Parser

This is a "baptism of fire" JSON parser implemented in Z98 Zig, designed to stress-test the multi-module compilation pipeline, recursive type resolution, and overall robustness of the Stage 0 compiler.

## Purpose
The primary purpose of this parser is to demonstrate the current capabilities and limitations of the Z98 compiler. It serves as a benchmark for multi-module coordination and recursive type handling.

## Current Status (Skeleton Phase)
The version currently committed is a functional skeleton that demonstrates:
- Multi-module imports (`@import("file.zig")`).
- Standard C interop (using `fopen`, `fread`).
- Arena-based memory management.
- Recursive struct definition for `JsonValue`.

## Roadmap Features (Rich Phase)
An attempt was made to implement a full feature-set parser, which revealed critical insights into the Stage 0 compiler's stability. The intended rich feature set includes:
- **Token-based Lexing**: A dedicated `Lexer` for efficient tokenization.
- **Full JSON Grammar**: Support for `null`, `bool`, hexadecimal numbers, and nested objects/arrays.
- **Escape Sequences**: Support for `\n`, `\t`, etc.
- **Recursive Descent Parsing**: A formal parser structure using standalone functions to bypass the lack of struct methods.

## Implementation Insights
- **Manual Tagged Unions**: Since `union(enum)` is unstable for complex nesting, the parser uses an `enum` tag and a `union` data field.
- **Explicit Pointer Recursion**: To avoid resolution cycles in slices, explicit pointers (`*JsonData`) are preferred.
- **Standalone Functions**: Due to the lack of method support, all operations are implemented as `fn (self: *T, ...)` standalone functions.

## Limitations and Stability
For a detailed analysis of why some features are currently restricted, see the [Missing Features](../missing_features_for_jsonparser.md) document. Key stability hurdles include:
- Recursive slice resolution.
- Structural equality checks for complex types.
- Control-flow expression lifting in deeply nested contexts.

## Usage
Compile with `zig0` and link with the Z98 runtime. The parser reads `test.json` and performs a structural validation.
