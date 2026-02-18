# Z98 Language Specification
**A Zig subset for 1998-era hardware and software.**

Z98 is a restricted subset of the Zig programming language designed to be compiled by the RetroZig bootstrap compiler into C89 code. It maintains the core spirit of Zig while adhering to the extreme technical constraints of the late 90s.

## 1. Types

### 1.1 Primitive Types
| Type | Description | C89 Equivalent |
|------|-------------|----------------|
| `i8`, `i16`, `i32`, `i64` | Signed integers | `signed char`, `short`, `int`, `__int64` |
| `u8`, `u16`, `u32`, `u64` | Unsigned integers | `unsigned char`, `unsigned short`, `unsigned int`, `unsigned __int64` |
| `isize`, `usize` | Platform-sized integers | `int`, `unsigned int` (32-bit) |
| `f32`, `f64` | Floating-point | `float`, `double` |
| `bool` | Boolean (`true`, `false`) | `int` (1, 0) |
| `void` | Empty type | `void` |

### 1.2 Pointers
- **Single-item pointers**: `*T` and `*const T`.
- **Address-of**: `&variable` produces a pointer.
- **Dereference**: `pointer.*` accesses the value.
- **Auto-dereference**: `ptr.field` is automatically treated as `ptr->field` if `ptr` is a pointer to a struct.

### 1.3 Aggregates
- **Structs**: `const S = struct { field: T, ... };`
- **Enums**: `const E = enum(T) { Member, ... };`
- **Unions**: `const U = union { field: T, ... };` (Bare unions only).

### 1.4 Arrays
- **Fixed-size**: `[N]T` where `N` is a compile-time constant.
- **Indexing**: `arr[i]`.

## 2. Memory Management (Arena Pattern)

Z98 relies on **Arena Allocation** for almost all dynamic memory needs. This pattern simplifies memory management and ensures performance on legacy systems.

### 2.1 Initialization Pattern
Since Z98 targets C89 and avoids complex destructors, the standard "constructor" pattern is a function that takes an `*Arena` and returns a pointer to an initialized object.

```zig
const MyStruct = struct {
    x: i32,
};

fn MyStruct_init(arena: *Arena, x: i32) *MyStruct {
    const self = arena_alloc(arena, @sizeOf(MyStruct));
    self.x = x;
    return self;
}
```

### 2.2 Reclaiming Memory
Memory is reclaimed by resetting or destroying the arena.
- If a type manages external resources (like file handles), a `deinit` function should be provided and called manually before the arena is reset.
- Memory allocated via `arena_alloc` should **not** be manually freed using `free()`.

## 3. Control Flow
- `if (cond) { ... } else { ... }`: Braces are **required**.
- `while (cond) { ... }`: Supports `break` and `continue`.
- `for (iterable) |item| { ... }`: Simple iteration.
- `switch (expr) { ... }`: Pattern matching.
- `defer { ... }`: Executes at scope exit.
- `errdefer { ... }`: Executes at scope exit if an error is returned.

## 4. Built-in Functions
- `@import("file.zig")`: Includes another module.
- `@sizeOf(T)`: Byte size of type `T`.
- `@alignOf(T)`: Alignment of type `T`.
- `@offsetOf(T, "field")`: Byte offset of a field.
- `@ptrCast(T, expr)`: Explicit pointer cast.
- `@intCast(T, expr)`: Checked integer conversion.
- `@floatCast(T, expr)`: Checked float conversion.

## 5. Explicit Limitations (Unsupported Features)
To maintain C89 compatibility, the following Zig features are **NOT supported** in Z98:

- **No Slices**: `[]T` is rejected. Use a pointer and a length.
- **Many-item Pointers**: `[*]T` is supported (Task 220).
- **No Error Unions**: `!T` syntax is recognized but requires Milestone 5 translation (not available in bootstrap).
- **No Optionals**: `?T` is recognized but strictly rejected in the bootstrap phase.
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **Multi-level Pointers**: `**T` and deeper are supported (Task 219).
- **Function Pointers**: `fn(...) T` types are supported (Task 221).
- **No Anonymous Structs/Enums**: All aggregates must be named via `const` assignment.
- **No Method Syntax**: `struct.func()` is not supported; use `func(struct)`.
- **Parameter Limit**: Functions are limited to a maximum of **4 parameters**.
