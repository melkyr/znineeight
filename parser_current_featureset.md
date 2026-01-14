# Parser Feature Set

This document provides a detailed overview of the language features supported by the RetroZig parser. It compares the features mentioned in the internal design documents with the actual implementation found in the source code.

| Zig Feature | Internal Doc Support | Parser Reality | Example |
| :--- | :---: | :---: | :--- |
| **Comments** | Yes | Yes | |
| Line Comments | Yes | Yes | `// a line comment` |
| Block Comments (nested) | Yes | Yes | `/* a block comment /* nested */ */` |
| **Literals** | Yes | Yes | |
| Integer Literals | Yes | Yes | `42`, `0xFF` |
| Float Literals | Yes | Yes | `3.14`, `1.0e-5`, `0x1.Ap2` |
| String Literals | Yes | Yes | `"hello"` |
| Multiline String Literals | Yes | Yes | `"hello\\\nworld"` |
| Character Literals | Yes | Yes | `'a'`, `'\n'`, `'\u{1F4A9}'` |
| Boolean Literals | Yes | Yes | `true`, `false` |
| Null Literal | Yes | Yes | `null` |
| **Declarations** | | | |
| `var` Declarations | Yes | Yes | `var x: i32 = 10;` |
| `const` Declarations | Yes | Yes | `const pi = 3.14;` |
| Function Declarations | Yes | Yes | `fn add(a: i32, b: i32) -> i32 { ... }` |
| Struct Declarations | Yes | Yes | `const Point = struct { x: i32, y: i32 };` |
| Union Declarations | Yes | Yes | `const IntOrFloat = union { i: i32, f: f32 };` |
| Enum Declarations | Yes | Yes | `const Color = enum { Red, Green, Blue };` |
| Enum with backing type | Yes | Yes | `const SmallEnum = enum(u8) { A, B };` |
| Opaque Types | Yes | No | `const File = opaque {};` |
| **Statements** | | | |
| If/Else Statements | Yes | Yes | `if (condition) { ... } else { ... }` |
| While Loops | Yes | Yes | `while (condition) { ... }` |
| For Loops | Yes | Yes | `for (my_array) |item, i| { ... }` |
| Defer Statements | Yes | Yes | `defer file.close();` |
| Errdefer Statements | Yes | Yes | `errdefer cleanup();` |
| Return Statements | Yes | Yes | `return;`, `return 42;` |
| Expression Statements | Yes | Yes | `do_something();` |
| Empty Statements | Yes | Yes | `;` |
| Comptime Blocks | Yes | Yes | `const x = comptime { 1 + 2 };` |
| **Expressions** | | | |
| Binary Operators | Yes | Yes | `a + b`, `x * y`, `c and d` |
| Unary Operators | Yes | Yes | `-x`, `!is_ready`, `&my_var` |
| Function Calls | Yes | Yes | `my_func()`, `add(1, 2)` |
| Array Access | Yes | Yes | `my_array[i]` |
| Array Slicing | Yes | Yes | `my_array[0..10]`, `my_array[..]` |
| Switch Expressions | Yes | Yes | `switch (value) { 1 => "one", else => "other" }` |
| `try` Expressions | Yes | Yes | `try fallible_operation()` |
| `catch` Expressions | Yes | Yes | `fallible() catch |err| fallback` |
| `orelse` Expressions | Yes | Yes | `optional_value orelse default_value` |
| **Types** | | | |
| Primitive Types | Yes | Yes | `i32`, `bool`, `f64` |
| Pointer Types | Yes | Yes | `*u8`, `*const MyStruct` |
| Array Types | Yes | Yes | `[8]u8` |
| Slice Types | Yes | Yes | `[]bool` |
| **Unsupported/Partially Supported** | | | |
| `async`/`await` | Yes (in docs) | No | `async my_func()` |
| `suspend`/`resume` | Yes (in docs) | No | `suspend { ... }` |
| Assignment Expressions | Yes (in docs) | No | `a = b` (parsed as `orelse/catch` only) |
| Compound Assignment | Yes (lexer only) | No | `a += 1` |
