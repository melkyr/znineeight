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
| `c_char` | C char type | `char` (signedness is implementation-defined) |
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
- **Identifiers**: Identifiers starting with `__` are reserved for the compiler. User-defined identifiers starting with `__` are automatically mangled to avoid collisions with internal compiler symbols.
- **Auto-dereference**: `ptr.field` is automatically treated as `ptr->field` if `ptr` is a single-level pointer to a struct.
- **Const Enforcement**: The Z98 frontend strictly enforces `const` qualifiers (e.g., you cannot assign to `*const T`). However, the C89 backend may drop these qualifiers to simplify code generation for complex types.

### 1.3 Aggregates
- **Structs**: `const S = struct { field: T, ... };`
- **Enums**: `const E = enum(T) { Member, ... };`
- **Unions**:
    - **Bare Unions**: `const U = union { field: T, ... };` (standard C union).
    - **Tagged Unions**: `const U = union(enum) { field: T, ... };`. Automatically managed tag and payload.
- **Tuples**: `.{ val1, val2 }` positional anonymous literals. Primarily supported for `std.debug.print`.

### 1.4 Arrays and Slices
- **Fixed-size Arrays**: `[N]T` where `N` is a compile-time constant.
- **Slices**: `[]T` and `[]const T`. Represented internally as a structure containing a pointer (`ptr`) and a length (`len`).
- **Indexing**: `base[i]` is supported for both arrays and slices. For slices, this is translated to `base.ptr[i]`. Slices are guaranteed to be non-null when indexed if their length is greater than zero (enforced by the compiler's static analysis).
- **Ranges**:
  - **Exclusive**: `start..end` (inclusive of `start`, exclusive of `end`). Used in `for` loops and slicing.
  - **Inclusive**: `start...end` (inclusive of both `start` and `end`). Supported primarily in `switch` cases.
- **Slicing**: `base[start..end]` creates a slice from an array, slice, or many-item pointer.
  - For arrays and slices, `start` and `end` can be omitted (e.g., `arr[..]`, `arr[5..]`).
  - For many-item pointers, both `start` and `end` **must** be explicitly provided.
  - Resulting slices propagate constness: slicing a `const` array or a `[]const T` results in a `[]const T`.
- **Properties**: Slices have built-in `.ptr` and `.len` properties.
  - `slice.ptr` returns a many-item pointer (`[*]T` or `[*]const T`).
  - `slice.len` returns a `usize`.
- **Coercion**:
  - Fixed-size arrays `[N]T` can be implicitly coerced to slices `[]T`.
  - String literals (e.g., `"hello"`) can be implicitly coerced to constant byte slices (`[]const u8`).

### 1.5 Error Handling Types
- **Error Sets**: `const MyErrors = error { Foo, Bar };`
- **Error Unions**: `!T` or `MyErrors!T`. Represented as a C struct containing a union for the payload and the error code.
- **Error Literals**: `error.TagName`. Unqualified error values.
- **Implicit Return**: Functions returning `!void` or `ErrorSet!void` implicitly return success (`{0}`) if execution falls off the end of the function body.
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
- `if (cond) statement else statement`: Braces are **optional** for `if` statement bodies. Single statements are normalized into synthetic blocks by the compiler.
  - **Example**: `if (a) return 1; else return 0;`
  - **Optional Capture**: `if (optional_val) |val| statement`. Unwraps the optional value if it is not null. `val` is immutable.
- **If Expressions**: `if (cond) a else b`. Braces are NOT required for expressions. Must have an `else` branch. Result type is merged from both branches.
  - **Optional Capture**: `if (optional_val) |val| a else b`. Supported in expressions.
- `while (cond) : (iter) statement`: While loop with a continue expression. `iter` is evaluated after the loop body on each iteration, before the condition is re-evaluated. Braces are **optional** for the loop body.
  - **Example**: `while (i < 10) i = i + 1;`
- `for (iterable) |item| statement`: Simple iteration. Supports one or two capture variables: `|item|` or `|item, index|`. Braces are **optional** for the loop body.
  - **Example**: `for (arr) |item| sum = sum + item;`
  - **Iterables**: Supports arrays (`[N]T`), slices (`[]T`), and ranges (`start..end`).
  - **Capture**: The `item` capture is by value (immutable). For ranges, it is of type `usize`.
  - **Index Capture**: An optional second capture `|item, index|` provides the current index as a `usize`.
  - **Discarding**: Captures can be discarded using the underscore `_` (e.g., `for (arr) |_, index|` or `for (arr) |_|`). Discarded captures are not bound to a symbol and cannot be accessed.
  - **Immutability**: All loop captures and function parameters are immutable. Attempting to assign to them will result in a compile-time error.
- `switch (expr) { ... }`: Pattern matching and conditional evaluation.
  - **Condition**: Must be a tagged union, integer, enum, or boolean.
  - **Prongs**: Comma-separated case items followed by `=>` and an expression.
  - **Payload Captures**: Tagged union switches support payload captures `case => |val| ...`. `val` is an immutable reference to the union's payload for that specific tag.
  - **Case Items**: Can be single values or ranges.
  - **Ranges**:
    - **Inclusive**: `start...end` (includes both `start` and `end`).
    - **Exclusive**: `start..end` (includes `start`, excludes `end`).
    - **Bounds**: Must be compile-time constants of the same type as the switch condition.
    - **Enums**: Ranges on enum conditions use the underlying integer values of the enum members.
    - **Expansion**: Ranges are lowered into sequential C `case` labels at compile-time.
    - **Limit**: To prevent excessive C code generation, each range is limited to 1000 individual case labels.
  - **Else**: An `else` prong is **mandatory** in all switch expressions.
  - **Grammar**:
    ```
    switch (expression) {
        pattern1, pattern2, ... => body,
        ...
        else => body,
    }
    pattern ::= literal | identifier | range
    range   ::= start '...' end   (inclusive)
             |  start '..' end    (exclusive)
    ```
  - **Result Type**: Computed by merging the types of all non-divergent prongs. If all prongs diverge, the result type is `noreturn`.
  - **Divergent Prongs**: Prongs may contain `return`, `break`, `continue`, or `unreachable`. These prongs have the type `noreturn`.
  - **Value Blocks**: Switch prongs can use blocks that yield a value (e.g., `=> { var x = 5; x + 1 }`).
  - **Examples**:
    ```zig
    // Inclusive range on integer
    switch (x) {
        1...5 => handleSmall(),
        else => handleLarge(),
    }

    // Exclusive range and multiple items
    switch (y) {
        0, 10..20 => handleSpecial(),
        else => handleDefault(),
    }

    // Range on enum
    const Color = enum { Red, Green, Blue };
    switch (c) {
        Color.Red...Color.Green => handleWarm(),
        else => handleCool(),
    }
    ```
- `defer statement`: Schedules `statement` to be executed at the end of the current scope. Braces are **optional**.
  - **Example**: `defer cleanup();`
  - `defer` statements are executed in reverse order of declaration (LIFO).
  - They execute on all paths out of the scope, including `return`, `break`, and `continue`.
  - `break`, `continue`, and `return` are strictly forbidden inside a `defer` block.
- `errdefer statement`: Schedules code to execute only when the scope exits with an error. Braces are **optional**. Currently supported as a placeholder in the C89 backend (emits a comment).
  - **Example**: `errdefer rollback();`
- `expr orelse fallback`: Provides a fallback value for an optional type. If `expr` is `null`, `fallback` is evaluated and yielded. The `fallback` can be an expression or a block. `orelse` is **right-associative**, so `a orelse b orelse c` is equivalent to `a orelse (b orelse c)`.
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
  - `catch` is **right-associative**, so `a catch b catch c` is equivalent to `a catch (b catch c)`.
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
- **Many-item Pointers**: `[*]T` is **supported**. Maps to raw C pointers and allows indexing/arithmetic. Note that string literals, arrays, and slices can implicitly coerce to many-item pointers in specific contexts (see Type Coercions below).
- **Optionals**: `?T` and `orelse` are **supported** as a bootstrap language extension.
- **AST Lifting**: Most control-flow expressions (`if`, `switch`, `try`, `catch`, `orelse`) are automatically transformed into statement blocks using temporary variables. This enables their use in complex expressions while maintaining C89 compatibility.
- **Tagged Unions**: `union(enum)` and switch captures are **supported**.
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **Multi-level Pointers**: `**T` and deeper are supported.
- **Function Pointers**: `fn(...) T` types are supported.
- **No Anonymous Structs/Enums**: All aggregates must be named via `const` assignment (except for tuple literals `.{}`).
- **No Method Syntax**: `struct.func()` is not supported; use `func(struct)`. (Exception: `std.debug.print`).
- **Parameter Limit**: Functions follow standard C89 parameter limits (at least 31).

## Type Coercions

### Implicit Coercion to Many-Item Pointers
In specific contexts where a pointer is expected, the compiler provides implicit coercion for slices and arrays.

**Allowed Contexts:**
- Assignments to variables of type [*]T or [*]const T.
- Passing arguments to functions where the parameter type is [*]T or [*]const T.
- Returning values from functions where the return type is [*]T or [*]const T.

**Coercion Rules:**
- **Slice to Pointer**: A slice `[]T` is coerced to `[*]T` by accessing its `.ptr` field.
- **Array to Pointer**: A fixed-size array `[N]T` is coerced to `[*]T` by taking the address of its first element (`&arr[0]`).
- **String Literal to Pointer**: A string literal is already a single-item pointer to constant bytes (`*const [N]u8`), and can be coerced to a many-item pointer (`[*]const u8`).

**Const Correctness:**
Coercions are only allowed if they do not discard const qualifiers.
- []T -> [*]const T (Allowed)
- []const T -> [*]T (Forbidden)
- [N]T -> [*]const T (Allowed)

**Restriction:**
These coercions are **not** allowed in other contexts, such as arithmetic operations or comparisons.
