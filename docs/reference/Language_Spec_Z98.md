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
- **Tuples**: `.{ val1, val2 }` positional anonymous literals. Primarily supported for `std.debug.print`.

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

### 1.5 Error Handling Types
- **Error Sets**: `const MyErrors = error { Foo, Bar };`
- **Error Unions**: `!T` or `MyErrors!T`. Represented as a C struct containing a union for the payload and the error code.
- **Error Literals**: `error.TagName`. Unqualified error values.
- **Coercion**:
  - A value of type `T` can be implicitly coerced to `!T` (success).
  - An error literal can be implicitly coerced to any error union `!T`.

### 1.6 Optional Types
- **Optional Types**: `?T`. Represented as a C struct containing the payload and a `has_value` flag. (Note: pointers `?*T` also use this uniform struct representation in the bootstrap compiler).
- **Null Literal**: `null`.
- **Coercion**:
  - A value of type `T` can be implicitly coerced to `?T` (present).
  - The `null` literal can be implicitly coerced to any optional type `?T`.
- **Example**:
  ```zig
  var x: ?i32 = null;
  x = 42; // implicitly wrapped
  ```

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
- `if (cond) { ... } else { ... }`: Braces are **strictly required** for all `if` statement bodies in the bootstrap compiler.
  - **Optional Capture**: `if (optional_val) |val| { ... }`. Unwraps the optional value if it is not null. `val` is immutable.
- **If Expressions**: `if (cond) a else b`. Braces are NOT required for expressions. Must have an `else` branch. Result type is merged from both branches.
  - **Optional Capture**: `if (optional_val) |val| a else b`. Supported in expressions.
- `while (cond) { ... }`: Simple loop. Braces are **strictly required** for the loop body. The `while (cond) : (iter)` syntax is currently **NOT supported**.
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
- `errdefer statement`: Recognized but NOT supported in the C89 backend. Strictly rejected by the validator. Schedules code to execute only when the scope exits with an error.
- `expr orelse fallback`: Provides a fallback value for an optional type. If `expr` is `null`, `fallback` is evaluated and yielded. The `fallback` can be an expression or a block.
  - **Example**:
    ```zig
    const val: i32 = optional_int orelse 0;
    const ptr: *i32 = optional_ptr orelse {
        // block fallback
        return;
    };
    ```

### 3.2 Loop Control
- `break`: Exits the innermost loop. Only allowed within `while` or `for` loop bodies.
- `break :label`: Exits the loop with the matching label.
- `continue`: Jumps to the next iteration of the innermost loop. Only allowed within `while` or `for` loop bodies.
- `continue :label`: Jumps to the next iteration of the loop with the matching label.
- **Loop Labels**: Loops can be labeled using `label: while ...` or `label: for ...`. Labels must be unique within their function.
- **Validation**: Both `break` and `continue` (labeled or unlabeled) are strictly forbidden inside `defer` and `errdefer` blocks.

### 3.3 Error Handling Expressions
- `try expr`: Unwraps an error union. If `expr` is an error, it is returned from the current function. Otherwise, the payload is yielded.
  - The enclosing function must return a compatible error union.
  - Example:
    ```zig
    fn mightFail() !i32 { return error.Bad; }
    fn callIt() !i32 {
        const val = try mightFail();
        return val + 1;
    }
    ```
- `expr catch |err| fallback`: Handles an error from an error union.
  - If `expr` is an error, the `err` variable is bound to the error code and `fallback` is evaluated.
  - If `expr` is a success, the payload is yielded and `fallback` is NOT evaluated.
  - The `|err|` capture is optional.
  - The `fallback` can be any expression, including a block `{ ... }`.
  - The result type of the `catch` expression is the payload type of `expr`. The `fallback` must yield a value of the same type or diverge (`return`, `break`, etc.).
  - Example:
    ```zig
    const res = mightFail() catch |err| {
        if (err == error.Bad) return 0;
        return 1;
    };
    ```

## 4. Built-in Functions
- `@import("file.zig")`: Includes another module.
- `std.debug.print(fmt: []const u8, args: anytype)`: Lowered by the compiler to a sequence of runtime print calls. Decomposes `{}` in the format string. Supports tuple literals for `args`.
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
- **Many-item Pointers**: `[*]T` is **supported**. Maps to raw C pointers and allows indexing/arithmetic. Note that string literals and slices do **not** implicitly decay to many-item pointers; use `.ptr` and `@ptrCast` explicitly.
- **Optionals**: `?T` and `orelse` are **supported** as a bootstrap language extension.
- **Lifting Limitations**: Some nested control-flow expressions (like `try try foo()`) are not supported due to C89 backend limitations. See [Current Lifting Strategies](../current_lifting_strategies.md) for details.
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **Multi-level Pointers**: `**T` and deeper are supported.
- **Function Pointers**: `fn(...) T` types are supported.
- **No Anonymous Structs/Enums**: All aggregates must be named via `const` assignment (except for tuple literals `.{}`).
- **No Method Syntax**: `struct.func()` is not supported; use `func(struct)`. (Exception: `std.debug.print`).
- **Parameter Limit**: Functions follow standard C89 parameter limits (at least 31).
