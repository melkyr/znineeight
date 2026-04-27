# Z98 Bootstrap Manual

This manual provides a comprehensive guide to the Z98 language subset as supported by the `zig0` bootstrap compiler. Z98 is designed to target 1998-era hardware and software by generating portable ANSI C89 code.

## 🚀 Idiomatic Z98 Patterns

To write effective Z98 code, it is important to understand the patterns used in the core examples (`rogue_mud`, `lisp_interpreter_curr`).

### 1. Memory Management: The `Sand` Arena
Z98 lacks a general-purpose heap allocator. Instead, it relies on **Arena Allocation** (often called `Sand` in examples).

- **Pattern**: Allocate a large global buffer and use a `Sand` struct to manage it.
- **Per-turn allocation**: Use a "temporary" arena for operations that only last one game tick or one evaluation cycle. Reset it at the end of the loop.

```zig
var buffer: [1024 * 1024]u8 = undefined;
var arena = sand_init(buffer[0..]);

// Inside game loop
while (true) {
    defer sand_reset(&arena);
    const temp_data = try sand_alloc(&arena, 1024, 8);
    // ...
}
```

### 2. Error Handling
Z98 supports error unions (`!T`) and the `try`/`catch`/`errdefer` keywords.

- **Idiom**: Prefer `try` for propagation.
- **Constraint**: `catch` blocks in Z98 are often lifted into statement blocks. Avoid deeply nested `catch` expressions within complex arithmetic.

### 3. C89 Interop and Strings
Zig `[]const u8` (slices) are represented as a struct `{ ptr, len }` in C89.

- **String Literals**: Passing a string literal to an `extern "c"` function expecting `[*]const u8` works because the compiler performs implicit decay.
- **`@ptrCast`**: Essential for reinterpreting memory (e.g., `*void` from an allocator to a concrete struct pointer).

```zig
const mem = try sand_alloc(&arena, @sizeOf(MyStruct), @alignOf(MyStruct));
const ptr = @ptrCast(*MyStruct, mem);
```

### 4. Control Flow: Labeled Jumps and Switch
- **Labeled Loops**: Use `break :label` or `continue :label` for multi-level escapes. This is lowered to `goto` in C89.
- **Switch Ranges**: Use `1...10 =>` for inclusive ranges.
- **Switch Exhaustiveness**: An `else` prong is **mandatory** for all switches in the bootstrap compiler, even if all enum tags are covered.

---

## 🛑 Language Subset Constraints

The `zig0` compiler only supports a specific subset of Zig.

### Prohibited Keywords & Features
- **`anytype`**: Generic parameters are not supported. Use `*void` or specific types.
- **`anyopaque`**: Not recognized. Use `*void` for opaque C pointers.
- **`static`**: Not a Zig keyword. Use file-scope `var` for persistent state.
- **Struct Methods**: Structs cannot have methods. Use prefixed functions: `fn MyStruct_init(...)`.
- **`async`/`await`**: Not supported.

### Syntax Quirks
- **Aggregate Initializers**: While `.{ .field = value }` is supported, passing it directly to a function (e.g., `func(.{ ... })`) may trigger "expression must be constant" errors in some legacy compilers. The `ControlFlowLifter` fixes this by hoisting it to a temporary variable.
- **Implicit Coercion**: `usize` and `isize` map to `unsigned int` and `int` (or `long` depending on platform). Be explicit with `@intCast` when precision matters.

---

## 🛠️ Runtime & Platform API Reference

### `zig_runtime.h`
The core runtime provides primitive types and basic I/O.

- **Types**: `i8`..`i64`, `u8`..`u64`, `f32`, `f64`, `usize`, `isize`.
- **I/O**:
  - `void __bootstrap_print(const char* s)`: Prints a null-terminated string.
  - `void __bootstrap_print_int(i32 n)`: Prints an integer.
  - `void __bootstrap_panic(const char* msg, const char* file, int line)`: Aborts execution.
- **Arena API**:
  - `Arena* arena_create(usize cap)`
  - `void* arena_alloc(Arena* a, usize size)`

### `net_runtime.c` (Networking PAL)
Provides a cross-platform (Win32/POSIX) socket layer.

- **`plat_socket_init()`**: Must be called before any networking on Windows.
- **`plat_create_tcp_server(port)`**: Creates and binds a listening socket.
- **`plat_socket_select(...)`**: Non-blocking I/O multiplexing.
- **`plat_fd_set`**: A struct containing the bitset for `select`.

### `platform_win98.h`
Forces the target API level to Windows 98 (`0x0410`).

- **Constraint**: Avoids using `unicows.lib` by sticking to `_MBCS` (Multi-Byte Character Set) instead of Unicode.
- **Console PAL**: Provides `plat_console_clear()`, `plat_console_gotoxy(x, y)`, and `plat_console_setcolor(fg, bg)`.

---

## 🗺️ Modular Design
Use `@import("file.zig")` to split code.

- **Visibility**: Use `pub` to make symbols visible to other modules.
- **Mangling**: Public symbols are mangled as `zF_[hash]_name` to prevent collisions across C translation units.
- **Circular Imports**: Supported, but try to keep type dependencies acyclic where possible to simplify C header generation.
