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
| `noreturn` | Never-returning type | `void` |

### 1.2 Pointers
- **Single-item pointers**: `*T` and `*const T`.
- **Many-item pointers**: `[*]T` and `[*]const T`. Supported for C-style array access.
- **Address-of**: `&variable` produces a pointer.
- **Dereference**: `pointer.*` accesses the value.
- **Indexing**: `ptr[i]` is allowed for many-item pointers, but strictly rejected for single-item pointers.
- **Arithmetic**: `ptr + i`, `ptr - i`, and `ptr1 - ptr2` are allowed for many-item pointers.
- **Auto-dereference**: `ptr.field` is automatically treated as `ptr->field` if `ptr` is a single-level pointer to a struct.
- **Const Enforcement**: The Z98 frontend strictly enforces `const` qualifiers (e.g., you cannot assign to `*const T`). However, the C89 backend may drop these qualifiers to simplify code generation for complex types.

### 1.3 Aggregates
- **Structs**: `const S = struct { field: T, ... };`
- **Enums**: `const E = enum(T) { Member, ... };`
- **Unions**: `const U = union { field: T, ... };` (Bare unions only).

### 1.4 Arrays and Slices
- **Fixed-size Arrays**: `[N]T` where `N` is a compile-time constant.
- **Slices**: `[]T` and `[]const T`. Represented internally as a structure containing a pointer (`ptr`) and a length (`len`).
- **Indexing**: `base[i]` is supported for both arrays and slices. For slices, this is translated to `base.ptr[i]`.
- **Ranges**:
  - **Exclusive**: `start..end` (inclusive of `start`, exclusive of `end`). Used in `for` loops and slicing.
  - **Inclusive**: `start...end` (inclusive of both `start` and `end`). Supported primarily in `switch` cases.
- **Slicing**: `base[start..end]` creates a slice from an array, slice, or many-item pointer.
  - For arrays and slices, `start` and `end` can be omitted (e.g., `arr[..]`, `arr[5..]`).
  - For many-item pointers, both `start` and `end` **must** be explicitly provided.
  - Resulting slices propagate constness: slicing a `const` array or a `[]const T` results in a `[]const T`.
- **Properties**: Slices have a built-in `.len` property (e.g., `slice.len`) which returns a `usize`.
- **Coercion**: Fixed-size arrays `[N]T` can be implicitly coerced to slices `[]T`.

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

### 3.1 Statements
- `if (cond) { ... } else { ... }`: Braces are **required**.
- `while (cond) { ... }`: Simple loop.
- `for (iterable) |item| { ... }`: Simple iteration. Supports one or two capture variables: `|item|` or `|item, index|`.
  - **Iterables**: Supports arrays (`[N]T`), slices (`[]T`), and ranges (`start..end`).
  - **Capture**: The `item` capture is by value (immutable). For ranges, it is of type `usize`.
  - **Index Capture**: An optional second capture `|item, index|` provides the current index as a `usize`.
  - **Discarding**: Captures can be discarded using the underscore `_` (e.g., `for (arr) |_, index|` or `for (arr) |_|`). Discarded captures are not bound to a symbol and cannot be accessed.
  - **Immutability**: All loop captures and function parameters are immutable. Attempting to assign to them will result in a compile-time error.
- `switch (expr) { ... }`: Pattern matching and conditional evaluation.
  - **Condition**: Must be an integer, enum, or boolean.
  - **Prongs**: Comma-separated case items followed by `=>` and an expression.
  - **Case Items**: Can be single values or inclusive ranges (`a...b`).
  - **Else**: An `else` prong is **mandatory** in all switch expressions.
  - **Result Type**: Computed by merging the types of all non-divergent prongs. If all prongs diverge, the result type is `noreturn`.
  - **Divergent Prongs**: Prongs may contain `return`, `break`, `continue`, or `unreachable`. These prongs have the type `noreturn`.
  - **Value Blocks**: Switch prongs can use blocks that yield a value (e.g., `=> { var x = 5; x + 1 }`).
- `defer statement`: Schedules `statement` to be executed at the end of the current scope.
  - The statement can be a single expression statement or a block `{ ... }`.
  - `defer` statements are executed in reverse order of declaration (LIFO).
  - They execute on all paths out of the scope, including `return`, `break`, and `continue`.
  - `break`, `continue`, and `return` are strictly forbidden inside a `defer` block.
- `errdefer { ... }`: Recognized but not yet implemented in the bootstrap compiler. Schedules code to execute only when the scope exits with an error.

### 3.2 Loop Control
- `break`: Exits the innermost loop. Only allowed within `while` or `for` loop bodies.
- `break :label`: Exits the loop with the matching label.
- `continue`: Jumps to the next iteration of the innermost loop. Only allowed within `while` or `for` loop bodies.
- `continue :label`: Jumps to the next iteration of the loop with the matching label.
- **Loop Labels**: Loops can be labeled using `label: while ...` or `label: for ...`. Labels must be unique within their function.
- **Validation**: Both `break` and `continue` (labeled or unlabeled) are strictly forbidden inside `defer` and `errdefer` blocks.

## 4. Built-in Functions
- `@import("file.zig")`: Includes another module.
- `@sizeOf(T)`: Byte size of type `T`.
- `@alignOf(T)`: Alignment of type `T`.
- `@offsetOf(T, "field")`: Byte offset of a field.
- `@ptrCast(T, expr)`: Explicit pointer cast.
- `@intCast(T, expr)`: Checked integer conversion.
- `@floatCast(T, expr)`: Checked float conversion.
- `unreachable`: Diverges with a panic. Has type `noreturn`.

## 5. Explicit Limitations (Unsupported Features)
To maintain C89 compatibility, the following Zig features are **NOT supported** in Z98:

- **Slices**: `[]T` is **supported** as a bootstrap language extension (mapping to C structs).
- **Many-item Pointers**: `[*]T` is **supported**. Maps to raw C pointers and allows indexing/arithmetic.
- **No Error Unions**: `!T` syntax is recognized but requires Milestone 5 translation (not available in bootstrap).
- **No Optionals**: `?T` is recognized but strictly rejected in the bootstrap phase.
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **Multi-level Pointers**: `**T` and deeper are supported.
- **Function Pointers**: `fn(...) T` types are supported.
- **No Anonymous Structs/Enums**: All aggregates must be named via `const` assignment.
- **No Method Syntax**: `struct.func()` is not supported; use `func(struct)`.
- **Parameter Limit**: Functions follow standard C89 parameter limits (at least 31).
