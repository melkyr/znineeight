# Z98 Bootstrap Manual

This manual provides a comprehensive, deep-dive guide to the Z98 language subset as supported by the `zig0` bootstrap compiler. Z98 is designed to target 1998-era hardware and software by generating portable, highly-compatible ANSI C89 code.

---

## 🏗️ Core Idioms and Architecture

Writing Z98 is a specialized discipline. Because the `zig0` bootstrap compiler is a subset of modern Zig, developers must rely on specific architectural patterns to achieve expressiveness and stability on resource-constrained systems.

### 1. Manual Memory Orchestration: The `Sand` Arena
Z98 prohibits the use of `std.mem.Allocator` interfaces and dynamic heap allocation (`malloc`). All dynamic memory must be managed via manual arenas, typically implemented as the `Sand` struct.

#### Pattern: Multi-Tiered Arenas
In sophisticated Z98 applications like `examples/rogue_mud/main.zig`, memory is managed through distinct "tiers" to optimize for both persistence and performance.
- **Permanent Arena**: Allocated once at startup. Stores the static world state.
- **Transient Arena**: Reset every game tick. Used for pathfinding algorithms (A*) and building outgoing network packets.

```zig
// From examples/rogue_mud/main.zig
var buffer: [512 * 1024]u8 = undefined;
var temp_buffer: [512 * 1024]u8 = undefined;

pub fn main() !void {
    var arena = sand_init(buffer[0..], true);
    var temp_arena = sand_init(temp_buffer[0..], false);

    while (true) {
        // High-frequency operations use the temp arena
        combat_mod.updateEnemies(&temp_arena, &dungeon);
        // sand_reset is a constant-time O(1) operation
        sand_mod.sand_reset(&temp_arena);
    }
}
```

#### Why `Sand`?
The `Sand` allocator (defined in `examples/rogue_mud/lib/sand.zig`) is a simple pointer-bump allocator. It guarantees zero fragmentation and predictable peak memory usage. On a 16MB system, this predictability is more valuable than the flexibility of a general-purpose heap. It also simplifies cleanup: instead of hundreds of `free()` calls, you perform a single pointer reset.

### 2. Functional Structs (Prefixed API)
Z98 does not support struct methods (`fn (self: *Self) ...`). Instead, it adopts a C-like functional prefix pattern.

#### Pattern: Namespace-Prefixed Functions
By convention, functions that operate on a struct are named `StructName_functionName`.

```zig
// From examples/rogue_mud/lib/room.zig
pub const Room_t = struct {
    x1: u8, y1: u8, x2: u8, y2: u8,
};

pub fn Room_centerX(self: Room_t) u8 {
    return self.x1 + (self.x2 - self.x1) / 2;
}

// Usage in main.zig:
const center_x = room_mod.Room_centerX(my_room);
```
**Ref:** See `examples/mud_server/main.zig` for a similar pattern with `Server_init` and `Server_deinit`. This pattern avoids the need for complex vtable or method resolution logic in the bootstrap compiler.

---

## 🛠️ Language Feature Deep-Dive

### 1. Control Flow

#### Labeled Jumps
Labeled loops allow for sophisticated multi-level escapes, which are essential when processing nested data like Lisp ASTs or complex dungeon maps.

```zig
// From examples/rogue_mud/main.zig
game_loop: while (true) {
    const c = getchar();
    switch (c) {
        'q', 'Q' => break :game_loop, // Multi-level jump
        else => {},
    }
}
```
**Technical Note:** The Z98 compiler lowers labeled jumps to `goto` statements in C89, providing a zero-cost abstraction for complex loops.

#### Exhaustive Switches and Expressions
Switch statements in Z98 can be used as expressions and support powerful range syntax.

- **Mandatory `else`**: To ensure valid C89 emission, every switch must contain an `else` prong.
- **Ranges**: Inclusive ranges use the `...` operator.

```zig
// From examples/lisp_interpreter_curr/main.zig
const result = switch (v.*) {
    .Int => |val| val,
    .Symbol => |s| lookup(s),
    else => 0, // Mandatory else
};
```

### 2. Data Structures

#### Slices (`[]T`)
Slices are first-class citizens in Z98, representing a pointer-length pair.
- **Underlying C Type**: Emitted as a struct `typedef struct { T* ptr; size_t len; } Slice_T;`.
- **Interop**: Passing `slice.ptr` to C functions is a common pattern for file I/O (see `examples/rogue_mud/lib/persistence.zig`).

#### Tagged Unions (`union(enum)`)
Tagged unions provide type-safe sum types.
- **Payload Capture**: Use `|capture|` to access the underlying value in a `switch` or `if`.

```zig
// From examples/lisp_interpreter_curr/value.zig
pub const Value = union(enum) {
    Int: i64,
    Cons: struct { car: *Value, cdr: *Value },
    // ...
};

// Accessing
switch (v.*) {
    .Int => |val| print_int(val),
    .Cons => |data| print_cons(data),
    else => {},
}
```

#### Tuples and Anonymous Literals
Tuples are anonymous structs with indexed fields, frequently used for passing arguments to formatted print functions.
- **Literal Syntax**: `.{ value1, value2 }`
- **Example**: Formatting output in `examples/mud_server/main.zig`.

```zig
// The second argument is a tuple
std.debug.print("Client {d} connected\n", .{client_id});
```

### 3. Optionals and `orelse`
Optional types (`?T`) allow for explicit nullability. The `orelse` operator provides a fallback.

#### Pattern: Default Values and Early Return
In `examples/rogue_mud/lib/persistence.zig`, `orelse` is used to handle failed C-interop calls.

```zig
const file = fopen(c_path, "wb") orelse return error.OpenFailed;
```

---

## 💾 System Integration and Interop

### 1. The C89 Boundary
Z98 is designed to "live" inside the C ecosystem. It directly utilizes standard C headers through `extern "c"`.

#### Pattern: Null-Terminated Strings
Zig slices are NOT null-terminated. To pass a string to C functions like `fopen`, you must create a null-terminated copy.

```zig
// From examples/rogue_mud/lib/sand.zig
pub fn sand_dupe_z(sand: *Sand, s: []const u8) ![*]u8 {
    const mem = try sand_alloc(sand, s.len + 1, 1);
    const ptr = @ptrCast([*]u8, mem);
    // ... copy ...
    ptr[s.len] = 0; // Null terminator
    return ptr;
}
```

---

## 🔌 Platform, Runtime, and Win98 API

Z98 provides a standardized Platform Abstraction Layer (PAL) to ensure code runs on both modern Linux and vintage Windows 98.

### 1. The Core Runtime (`zig_runtime.c` / `zig_runtime.h`)
This layer handles the most basic operations of the language.
- **`__bootstrap_print(const char*)`**: Low-level string output. On Win98, it utilizes `WriteConsoleA` for robust terminal output.
- **`__bootstrap_print_int(i32)`**: Optimized integer-to-string conversion that avoids `sprintf`.
- **Arena API**: `arena_create`, `arena_alloc`, `arena_reset`. This is the C-level foundation for Zig's `Sand` allocators.
- **Numeric Casts**: Runtime checked helpers like `__bootstrap_u8_from_i32` ensure that `@intCast` violations trigger a panic instead of silent corruption.

### 2. Networking PAL (`net_runtime.c`)
Abstracts the differences between Berkeley Sockets (POSIX) and Winsock 1.1 (Win95/98).
- **`plat_socket_init()`**: Critical on Windows to initialize the Winsock DLL.
- **`plat_create_tcp_server(u16 port)`**: Handles `socket`, `bind`, and `listen` in one call.
- **`plat_socket_select(...)`**: Enables non-blocking multiplexing. Note that `plat_fd_set` in Z98 is a struct wrapper to ensure 4-byte alignment, as required by Windows.

### 3. Windows 98 Platform Header (`platform_win98.h`)
This internal header locks the compiler into the Win98 API subset.
- **API Level**: Forced to `0x0410` (Windows 98).
- **Encoding**: Uses `_MBCS` (Multi-Byte) instead of Unicode to maintain compatibility with the non-Unicode Windows 9x kernel.

### 4. Console Management
Located in `src/runtime/zig_runtime.c`, these functions provide the basis for TUI (Text User Interface) applications.
- **`plat_console_clear()`**: On Linux, emits ANSI escape `\x1b[2J`. On Win98, uses `FillConsoleOutputCharacter` to clear the buffer.
- **`plat_console_gotoxy(x, y)`**: Moves the cursor. Uses `SetConsoleCursorPosition` on Windows.
- **Ref**: See `examples/game_of_life/main.zig` for how these are used to build a real-time animated display.

---

## 🛑 Constraints and Design Rationale

| Constraint | Why it exists | Recommended Workaround |
| :--- | :--- | :--- |
| **No Methods** | Simplifies C89 name mangling and vtable logic. | Use namespace-prefixed functions. |
| **No `anytype`** | Avoids complex template instantiation in C89. | Use `*void` for generic payloads (see `builtins.zig`). |
| **No `anyopaque`** | Lexer limitation in the bootstrap phase. | Use `*void` or `*u8`. |
| **No `static`** | Zig uses file-scope `var` for persistent state. | Declare `var` at the top level of the module. |
| **Mandatory `else`** | Ensures deterministic C control flow. | Always provide a fallback branch. |

---

## 📚 Study Guide: Recommended Examples

If you are learning Z98, study these files in order:
1. **`examples/hello/main.zig`**: The "Hello World" of Z98. Learn about `extern` calls.
2. **`examples/prime/main.zig`**: Master basic arithmetic and `while` loop syntax.
3. **`examples/lisp_interpreter_curr/`**: The standard for complex data structures, recursive type handling, and using `Sand` for heavy processing.
4. **`examples/mud_server/main.zig`**: Learn non-blocking socket I/O and networked state management.
5. **`examples/rogue_mud/`**: The definitive Z98 project. Covers persistence, pathfinding, UI rendering, and multi-module architecture.
