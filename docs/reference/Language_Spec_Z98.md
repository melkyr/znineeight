> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Z98 Language Specification
**A Zig subset for 1998-era hardware and software.**

Z98 is a restricted subset of the Zig programming language compiled by the self-hosted `zig1` compiler into C89 code. `zig1` is written in Z98 and rebuilt from the committed seed `release/seed/zig1-seed.tgz`. It maintains the core spirit of Zig while adhering to the extreme technical constraints of the late 90s.

## 1. Types

### 1.1 Primitive Types
| Type | Description | C89 Equivalent |
|------|-------------|----------------|
| `i8`, `i16`, `i32`, `i64` | Signed integers | `signed char`, `short`, `int`, `__int64` |
| `u8`, `u16`, `u32`, `u64` | Unsigned integers | `unsigned char`, `unsigned short`, `unsigned int`, `unsigned __int64` |
| `u1`..`u64`, `i1`..`i63` | Arbitrary-width integers | Smallest power-of-two C integer carrier that holds the width |
| `isize`, `usize` | Platform-sized integers | `int`, `unsigned int` (32-bit) |
| `c_char` | C char type | `char` (signedness is implementation-defined) |
| `f32`, `f64` | Floating-point | `float`, `double` |
| `bool` | Boolean (`true`, `false`) | `int` (1, 0) |
| `void` | Empty type | `void` |
| `noreturn` | Never-returning type | `void` |

Arbitrary-width integers carry an exact compile-time bit width, `u1`..`u64` unsigned and `i1`..`i63` signed. Values are stored in the smallest power-of-two C carrier that holds the width, so `@sizeOf(uN)`/`@alignOf(uN)` report that carrier size (1/2/4/8) while `@bitSizeOf(uN)` reports the declared width. Arithmetic results are masked (unsigned) or sign-extended (signed) back to the declared width, and `@intCast` to an arbitrary width is range-checked. Widths outside the supported ranges are rejected with `error[3000]`. Widths are also accepted as the explicit backing type of an enum (`enum(uN)`, see §1.3).

### 1.2 Pointers
- **Single-item pointers**: `*T` and `*const T`.
- **Many-item pointers**: `[*]T` and `[*]const T`. Supported for C-style array access.
- **Multi-level pointers**: `**T`, `***T`, etc., are fully supported.
- **Address-of**: `&variable` produces a pointer.
- **Dereference**: `pointer.*` accesses the value.
- **Indexing**: `ptr[i]` is allowed for many-item pointers, but strictly rejected for single-item pointers.
- **Arithmetic**: `ptr + i`, `ptr - i`, and `ptr1 - ptr2` are allowed for many-item pointers.
- **Identifiers**: Identifiers starting with `__` are reserved for the compiler. User-defined identifiers starting with `__` are automatically mangled to avoid collisions with internal compiler symbols.
- **Auto-dereference**: `ptr.field` is automatically treated as `ptr->field` if `ptr` is a single-level pointer to a struct.
- **Const Enforcement**: The Z98 frontend strictly enforces `const` qualifiers (e.g., you cannot assign to `*const T`). However, the C89 backend may drop these qualifiers to simplify code generation for complex types.
- **Function Pointers**: `fn(...) T` types are supported.
- **Pointer Builtins**: Pointer casts and pointer/introspection are provided by builtins — `@ptrCast`, `@ptrToInt`/`@intFromPtr`, `@intToPtr`/`@ptrFromInt`, `@fieldParentPtr`, `@bitCast`, and `@as` (see §4).

### 1.3 Aggregates
- **Structs**: `const S = struct { field: T, ... };`
- **Packed Structs**: `const P = packed struct { field: uN, ... };`. Fields are packed LSB-first with no padding; `@sizeOf(P)` is `(total_bits + 7) / 8`. Every field must be `bool` or an integer type whose width is at most 31 bits; a `packed struct` member is admitted by its inner total width, even when that exceeds 31 bits. Field reads/writes lower to generated bitfield load/store code.
- **Enums**: `const E = enum { Member, ... };` (inferred backing) or `const E = enum(uN) { Member, ... };` (explicit unsigned integer backing of width `N`).
- **Unions**:
    - **Packed Unions**: `const U = packed union { field: uN, ... };`. All members overlap at bit offset 0; total bits is the widest member; `@sizeOf` is `max(1, (total_bits + 7) / 8)`, alignment 1. Members must be `bool` or an integer type of at most 31 bits; a `packed struct` member is admitted by its inner total width, even when that exceeds 31 bits (the ≤31-bit cap applies to the `bool`/integer leaves).
    - **Bare Unions**: `const U = union { field: T, ... };` (standard C union).
    - **Tagged Unions**: `const U = union(enum) { field: T, ... };`. Automatically managed tag and payload.
        - **Naked Tags**: In tagged unions, fields without an explicit type (e.g., `A,` instead of `A: void,`) are automatically treated as having a `void` payload. This sugar is NOT allowed in bare unions or structs.
        - **Anonymous Payloads**: Tagged union variants can have nested anonymous struct payloads (e.g., `Cons: struct { car: *Value, cdr: *Value }`). The compiler handles the C89 declaration and initialization of these internal structures.
- **Tuples**: `struct { T1, T2, ... }` for types and `.{ val1, val2, ... }` for positional anonymous literals.
    - **Member Access**: Accessed via numeric indices (e.g., `t.0`, `t.1`).
    - **C89 Representation**: Lowered to C structs with fields named `field0`, `field1`, etc.
    - **Usage**: Primarily used for `print` arguments and grouped return values.
    - **Initialization**: Anonymous tuple literals are automatically coerced to concrete tuple types based on context.

### 1.4 Arrays and Slices
- **Fixed-size Arrays**: `[N]T` where `N` is a compile-time constant.
- **Slices**: `[]T` and `[]const T`. Represented internally as a structure containing a pointer (`ptr`) and a length (`len`).
- **Indexing**: `base[i]` is supported for both arrays and slices. For slices, this is translated to `base.ptr[i]`. Slices are guaranteed to be non-null when indexed if their length is greater than zero (enforced by the compiler's static analysis).
- **Ranges**:
  - **Exclusive**: `start..end` (inclusive of `start`, exclusive of `end`). Used in `for` loops and slicing.
  - **Inclusive**: `start...end` (inclusive of both `start` and `end`). Supported primarily in `switch` cases.
- **Slicing**: `base[start..end]` syntax for arrays, slices, and many-item pointers.
  - The `end` index may be omitted (`arr[5..]`); the resulting slice runs from `start` to the end of the source. Omitting the `start` index (`arr[..5]`) is **not** supported.
  - Resulting slices propagate constness: slicing a `const` array or a `[]const T` results in a `[]const T`.
- **Properties**: Slices have built-in `.ptr` and `.len` properties.
  - `slice.ptr` returns a many-item pointer (`[*]T` or `[*]const T`).
  - `slice.len` returns a `usize`.
- **Coercion**:
  - Fixed-size arrays `[N]T` can be implicitly coerced to slices `[]T`.
  - String literals (e.g., `"hello"`) are typed as `*const [N]u8` and can be implicitly coerced to constant byte slices (`[]const u8`), many-item pointers (`[*]const u8`), or legacy single-item pointers (`*const u8`).

### 1.5 Error Handling Types
- **Error Sets**: `const MyErrors = error { Foo, Bar };`
- **Error Unions**: `!T` or `MyErrors!T`. Represented as a C struct containing a union for the payload and the error code.
- **Error Literals**: `error.TagName`. Unqualified error values.
- **Implicit Return**: Functions returning `!void` or `ErrorSet!void` implicitly return success (`{0}`) if execution falls off the end of the function body.
- **Coercion**:
  - A value of type `T` can be implicitly coerced to `!T` (success).
  - An error literal can be implicitly coerced to any error union `!T`.
- **Not supported**: `@errorName` and the `anyerror` type (see §7).

### 1.6 Optional Types
- **Optional Types**: `?T`. Represented as a C struct containing the payload and a `has_value` flag. (Note: pointers `?*T` also use this uniform struct representation.)
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

### 2.1 The Arena API
The standard library re-exports an arena allocator as `std.arena` (`sf/src/std_arena.zig`). It wraps caller-provided backing storage:

- `std.arena.init(data: []u8) Arena` — constructs an `Arena` over the given byte buffer.
- `std.arena.alloc(self: *Arena, size: usize) ?[*]u8` — bumps within the backing storage and returns the raw block, or `null` when the arena is exhausted.
- `std.arena.reset(self: *Arena) void` — reclaims all allocations by setting the used length back to zero.

Z98 has no method syntax, so these are called as free functions (e.g. `std.arena.alloc(&a, n)`).

Canonical usage:

```zig
var g_buf: [65536]u8 = undefined;
var g_arena = std.arena.init(g_buf[0..]);
```

### 2.2 Initialization Pattern
Since Z98 targets C89 and avoids complex destructors, the standard "constructor" pattern is a function that takes a `*std.arena.Arena` and returns a pointer to an initialized object.

```zig
const MyStruct = struct {
    x: i32,
};

fn MyStruct_init(arena: *std.arena.Arena, x: i32) *MyStruct {
    const raw = std.arena.alloc(arena, @sizeOf(MyStruct)) orelse unreachable;
    const self = @ptrCast(*MyStruct, raw);
    self.x = x;
    return self;
}
```

### 2.3 Reclaiming Memory
Memory is reclaimed by resetting the arena.
- `std.arena.reset(&arena)` reclaims every allocation made through that arena; there is no `deinit`.
- If a type manages external resources (like file handles), it must clean those up manually before the arena is reset.
- Memory obtained from `std.arena.alloc` should **not** be passed to `free()`.

### 2.4 Advanced Patterns (Dual-Arena)
For complex applications like compilers or interpreters (e.g., the Lisp interpreter), a **dual-arena system** is highly effective:
- **Permanent Arena**: Stores long-lived data (e.g., global symbols, environment nodes, persistent AST).
- **Transient Arena**: Stores temporary data that is cleared frequently (e.g., per-eval, per-file, or per-request data).
This approach maximizes performance on legacy hardware by minimizing the active working set and avoiding frequent small allocations.

## 3. Control Flow

### 3.1 Statements
- `if (cond) statement else statement`: Braces are **optional** for `if` statement bodies. Single statements are normalized into synthetic blocks by the compiler.
  - **Capture**: `if (result) |payload| ...` supports capturing payloads from error unions and optional types.
  - **Example**: `if (a) return 1; else return 0;`
  - **Optional Capture**: `if (optional_val) |val| statement`. Unwraps the optional value if it is not null. `val` is immutable.
- **If Expressions**: `if (cond) a else b`. Braces are NOT required for expressions. Must have an `else` branch. Result type is merged from both branches.
  - **Optional Capture**: `if (optional_val) |val| a else b`. Supported in expressions.
- `while (cond) : (iter) statement`: While loop with a continue expression. `iter` is evaluated after the loop body on each iteration, before the condition is re-evaluated. Braces are **optional** for the loop body.
  - **Example**: `while (i < 10) i = i + 1;`
  - **Capture**: `while (optional_expr) |capture| { ... }` is supported for optional unwrapping. The loop continues as long as `optional_expr` yields a value.
- `for (iterable) |item| statement`: Simple iteration. Supports one or two capture variables: `|item|` or `|item, index|`. Braces are **optional** for the loop body.
  - **Example**: `for (arr) |item| sum = sum + item;`
  - **Iterables**: Supports arrays (`[N]T`), slices (`[]T`), and ranges (`start..end`).
  - **Capture**: The `item` capture is by value (immutable). For ranges, it is of type `usize`.
  - **Index Capture**: An optional second capture `|item, index|` provides the current index as a `usize`.
  - **Discarding**: Captures can be discarded using the underscore `_` (e.g., `for (arr) |_, index|` or `for (arr) |_|`). Discarded captures are not bound to a symbol and cannot be accessed.
  - **Immutability**: All loop captures and function parameters are immutable. Attempting to assign to them will result in a compile-time error.
- `switch (expr) { ... }`: Pattern matching and conditional evaluation.
  - **Condition**: Must be a tagged union, integer, enum, or boolean.
  - **Prongs**: Comma-separated case items followed by `=>` and an expression. If a prong consists of a single expression, it is automatically treated as an expression-statement when the switch is used as a statement.
  - **Payload Captures**: Tagged union switches support payload captures `case => |val| ...`. `val` is an immutable reference to the union's payload for that specific tag.
  - **Case Items**: Can be single values or ranges.
  - **Ranges**:
    - **Inclusive**: `start...end` (includes both `start` and `end`).
    - **Exclusive**: `start..end` (includes `start`, excludes `end`).
    - **Bounds**: Must be compile-time constants of the same type as the switch condition.
    - **Enums**: Ranges on enum conditions use the underlying integer values of the enum members.
    - **Expansion**: Ranges are lowered into sequential C `case` labels at compile-time.
    - **Character Literals**: Character literals (e.g., `'a'...'z'`) are fully supported in constant expressions, including `switch` ranges. They are treated as their underlying Unicode codepoint (ASCII) values.
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
- `errdefer statement`: Schedules code to execute only when the scope exits with an error. Braces are **optional**.
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

### 3.2 Labeled Blocks and Loop Control
- **Labeled Blocks**: A block can be labeled (`blk: { ... }`) and exited early with a value-less `break :blk;`. A labeled block is a statement, not a value-producing expression: yielding a value out of a labeled block (`break :blk value;`) is **not implemented** (see §7).
  ```zig
  blk: {
      if (cond) break :blk;
      doStuff();
  }
  ```
- `break`: Exits the innermost `while` or `for` loop; when labeled, exits the matching loop or labeled block.
- `break :label`: Exits the matching loop or labeled block.
- `continue`: Jumps to the next iteration of the innermost `while` or `for` loop.
- `continue :label`: Jumps to the next iteration of the matching loop.
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

Builtins are invoked as `@name(...)` and are recognized by name; an unknown or unsupported builtin is rejected with `error[3000]: unsupported builtin function`. The supported surface is:

**Cast / conversion / introspection**
| Builtin | Description |
|---------|-------------|
| `@ptrCast(T, expr)` | Explicit pointer cast |
| `@ptrToInt(expr)` / `@intFromPtr(expr)` | Pointer to integer (`@intFromPtr` is the modern alias) |
| `@intToPtr(T, expr)` | Integer to pointer, explicit result type |
| `@ptrFromInt(expr)` | Integer to pointer, result type taken from context |
| `@fieldParentPtr(T, "field", expr)` | Pointer to the containing struct from a pointer to one of its fields |
| `@bitCast(T, expr)` | Same-size integer-to-integer bit reinterpretation |
| `@intCast(T, expr)` | Checked integer conversion / width change |
| `@floatCast(T, expr)` | Checked float conversion |
| `@intToFloat(T, expr)` | Integer to float |
| `@intToEnum(T, expr)` | Integer to enum |
| `@enumToInt(expr)` | Enum to integer |
| `@as(T, expr)` | Explicit type coercion |
| `@sizeOf(T)` | Byte size of type `T` |
| `@alignOf(T)` | Alignment of type `T` |
| `@offsetOf(T, "field")` | Byte offset of a field |
| `@bitSizeOf(T)` | Bit size of type `T` |
| `@bitOffsetOf(T, "field")` | Bit offset of a field |

**Runtime**
- `@putChar(c)`: Writes a single character.
- `@stdoutWrite(ptr, len)` / `@stderrWrite(ptr, len)`: Writes `len` bytes to stdout / stderr.
- `@getChar()`: Reads a single character.
- `@exit(code)`: Terminates the process with `code`.
- `@sleepMs(ms)`: Sleeps for `ms` milliseconds.
- `@isWindows()`: Compile-time-folded target predicate (true only for the Windows target).
- `@consoleClear()`, `@consoleGotoxy(x, y)`, `@consoleSetColor(fg, bg)`: Console control helpers.
- `@panic(msg)`: Accepted, but **lowers to a no-op** in user programs on this compiler (it is typed as its argument, not `noreturn`). `unreachable` is also accepted and typed as `noreturn`, but likewise **lowers to a no-op**. For real termination, use the printed-abort + trap provided by `std.debug` (see `sf/src/std_debug.zig`), not `@panic`/`unreachable`.

**C varargs**
- `@cVaStart`, `@cVaArg`, `@cVaEnd`: Access a C variadic argument list (`va_list`).

**Declarations**
- `@import("file.zig")`: Includes another module. The standard library is imported as `@import("std")`; `sf/src/std.zig` re-exports `io`, `arena`, `str`, `mem`, `math`, `debug`, and `net`.
- `@cInclude("header.h")`: Emits a C header `#include` (used by the extern OS bindings, e.g. `std.net`).

**Formatted `print`**
- A call whose callee is named `print` (for example `std.io.print`) is a compiler special case: the compiler decomposes the format string and emits one runtime print call per argument.
    - **Format Specifiers**: Supports `{}` (default, decimal), `{d}` (decimal), `{x}` (hex), `{c}` (character), and `{s}` (string). Any other specifier is rejected with `error[3013]`.
    - **Arguments**: The arguments **must** be a tuple literal (e.g., `.{arg1, arg2}`) or a tuple variable. The compiler decomposes the format string and emits individual print calls for each tuple element.
    - This is the only variadic form Z98 supports; there is no `anytype`. The shipped wrapper is `std.io.print(s: [*]const c_char, ...) void`.

## 5. Known Limitations and Workarounds

To maintain C89 compatibility and compiler simplicity, Z98 has the following limitations:

- **No `anyerror`**: The `anyerror` type does not exist in the token set; use explicit error sets (e.g., `const MyError = error { Bad };`) or anonymous error unions `!T`.
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **No Anonymous Enum Types**: Aggregate type declarations must be named via `const` assignment. Anonymous `struct` type expressions, tuple literals `.{}`, and anonymous struct payloads in tagged union variants are parsed.
- **Strict Coercion**: There is no implicit coercion between `i32` and `usize`. Use `@intCast(usize, ...)` or `@intCast(i32, ...)` when mixing these types in assignments or initializers.
- **No Method Syntax**: `struct.func()` is not supported; use `func(struct)`. (Exception: a call whose callee is named `print` gets format-string lowering; see §4.)
- **AST Lifting**: Most control-flow expressions (`if`, `switch`, `try`, `catch`, `orelse`) are automatically transformed into statement blocks using temporary variables. This enables their use in complex expressions while maintaining C89 compatibility.

## 6. Z98 Idioms and Best Practices

### 6.1 The Arena Pattern
Dynamic memory should almost exclusively be managed via `std.arena` (`ArenaAllocator` is not the shipped name).
- **Ownership**: Functions should accept an `*std.arena.Arena` rather than "owning" their memory.
- **Transient vs Permanent**: Use a dual-arena system to separate short-lived temporary allocations from long-lived application state.
- **Cleanup**: Call `std.arena.reset(&arena)` at the highest possible level (e.g., end of `main` or after a major processing loop). There is no `deinit`.

### 6.2 Manual Virtual Tables
Since Z98 lacks classes and methods, use structs of function pointers to implement polymorphism.
```zig
const Shape = struct {
    draw_fn: fn(*void) void,
    data: *void,
};
```

### 6.3 Runtime Initialization
For complex global state, avoid large constant initializers. Use a dedicated `init()` function called at startup.
```zig
var global_registry: [100]Item = undefined;
fn initRegistry() void {
    // initialize here
}
```

## Type Coercions

### Implicit Coercion to Many-Item Pointers and Slices
In specific contexts where a pointer or slice is expected, the compiler provides implicit coercion for slices and arrays.

**Allowed Contexts:**
- Assignments to variables of type `[*]T` or `[]T`.
- Passing arguments to functions.
- Returning values from functions.

**Coercion Rules:**
- **Slice to Pointer**: A slice `[]T` is coerced to `[*]T` by accessing its `.ptr` field.
- **Array to Pointer**: A fixed-size array `[N]T` is coerced to `[*]T` by taking the address of its first element (`&arr[0]`).
- **String Literal to Pointer**: A string literal is typed as `*const [N]u8` and can be implicitly coerced to `[*]const u8`, `[]const u8`, or `*const u8`.
- **Array/Pointer to Slice**: Handled via a synthetic slicing node `arr[0..arr.len]`.

**Const Correctness:**
Coercions are only allowed if they do not discard const qualifiers.
- `[]T` -> `[*]const T` (Allowed)
- `[]const T` -> `[*]T` (Forbidden)

**Restriction:**
These coercions are **not** allowed in other contexts, such as arithmetic operations or comparisons.

## 7. Not Yet Supported

> **DESIGNED, NOT IMPLEMENTED.** The following features appear in design/plan documents for Z98 but are **not implemented** in the current self-hosted `zig1` compiler. Do not rely on them.

- `static` declarations.
- `do ... while` loops.
- Value-producing labeled blocks (`const n = blk: { ... break :blk 1; };`). Only value-less `break :blk;` is supported.
- `volatile` qualifiers.
- `@errorName`.
- `extern struct`, `opaque`, and `vector` types.
- Generics, `anytype` parameters, `@Type`, `@typeInfo`, and `comptime`.
- The `anyerror` type (use explicit error sets or `!T`).
- `@cImport` (use bare `extern` declarations plus `@cInclude`).
