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
| `bool` | Boolean (`true`, `false`) | `unsigned char` (1, 0) |
| `void` | Empty type | `void` |
| `noreturn` | Never-returning type | `void` |

Arbitrary-width integers carry an exact compile-time bit width, `u1`..`u64` unsigned and `i1`..`i63` signed. Values are stored in the smallest power-of-two C carrier that holds the width, so `@sizeOf(uN)`/`@alignOf(uN)` report that carrier size (1/2/4/8) while `@bitSizeOf(uN)` reports the declared width. Arithmetic results are masked (unsigned) or sign-extended (signed) back to the declared width, and `@intCast` to an arbitrary width is range-checked. The runtime range check (like the other five runtime checks) is enabled by default (`-fsafe`) and disabled by `-ffast` (see §5). Widths outside the supported ranges are rejected with `error[3000]`. Widths are also accepted as the explicit backing type of an enum (`enum(uN)`, see §1.3).

### 1.2 Pointers
- **Single-item pointers**: `*T`, `*const T`, and `*volatile T`. `const` and `volatile` may be combined (`*const volatile T`).
- **Many-item pointers**: `[*]T`, `[*]const T`, and `[*]volatile T`. Supported for C-style array access.
- **Qualified-pointer scope**: `[]volatile T` slices and `*volatile fn(...)` function pointers are **not** supported; use `*volatile T` / `[*]volatile T` for memory-mapped I/O.
- **Multi-level pointers**: `**T`, `***T`, etc., are fully supported.
- **Address-of**: `&variable` produces a pointer.
- **Dereference**: `pointer.*` accesses the value.
- **Indexing**: `ptr[i]` is allowed for many-item pointers, but strictly rejected for single-item pointers.
- **Arithmetic**: `ptr + i`, `ptr - i`, and `ptr1 - ptr2` are allowed for many-item pointers.
- **Identifiers**: Identifiers starting with `__` are reserved for the compiler. User-defined identifiers starting with `__` are automatically mangled to avoid collisions with internal compiler symbols.
- **Auto-dereference**: `ptr.field` is automatically treated as `ptr->field` if `ptr` is a single-level pointer to a struct.
- **Const Enforcement**: The Z98 frontend strictly enforces `const` qualifiers (e.g., you cannot assign to `*const T`). The C89 backend still **drops** `const` in emission (it is not rendered), so `const` remains a frontend-only guarantee.
- **Volatile Enforcement**: `volatile` is enforced by the frontend **and preserved** in C89 emission. A `*volatile T` cannot be implicitly converted to `*T` (`error[3000]`); remove the qualifier only with `@volatileCast`, and `@ptrCast` cannot discard it. `*volatile T` renders as `volatile T*`.
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
- **Indexing**: `base[i]` is supported for both arrays and slices. For slices, this is translated to `base.ptr[i]`. Slices are guaranteed to be non-null when indexed if their length is greater than zero (enforced by the compiler's static analysis). A **comptime-known** index that is provably out of bounds for a fixed-size array (`scores[5]`, `scores[scores.len]`, a negative index, a `const` chain, a `*[N]T`, or a struct/union array field) is rejected at compile time with `error[3062]` (`index N outside array of length L`; a negative value gets Zig's `type 'usize' cannot represent integer value '-N'`), matching official Zig 0.15.2; a runtime index keeps the mode-independent `-fsafe` out-of-bounds runtime check.
- **Ranges**:
  - **Exclusive**: `start..end` (inclusive of `start`, exclusive of `end`). Used in `for` loops and slicing.
  - **Inclusive**: `start...end` (inclusive of both `start` and `end`). Supported primarily in `switch` cases.
- **Slicing**: `base[start..end]` syntax for arrays, slices, and many-item pointers.
  - The `end` index may be omitted (`arr[5..]`); the resulting slice runs from `start` to the end of the source. Omitting the `start` index (`arr[..5]`) is **not** supported.
  - Resulting slices propagate constness: slicing a `const` array or a `[]const T` results in a `[]const T`.
  - **Constant bounds** on a fixed-size array are checked at compile time with `error[3062]`, matching official Zig 0.15.2: `end index N out of bounds for array of length L`, `start index S is larger than end index E` (the open-ended `arr[s..]` compares against the length), and a negative bound gets `type 'usize' cannot represent integer value '-N'`. `arr[len..]` and `arr[len..len]` are legal empty slices; a runtime bound keeps the `-fsafe` runtime check.
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

### 1.7 Type Aliases
`const T = <type>;` names a type. Supported alias targets include primitive and arbitrary-width integers (`i32`, `u7`), arrays (`[N]T`), slices (`[]T`), many-item pointers (`[*]T`), single-item pointers (`*T`), optionals (`?T`), error unions (`E!T`), function types (`fn(...) T`), and other named aggregate/alias types. Aliases may chain (`const B = A;`) and may be re-exported across modules with `pub const`.
```zig
const MyInt = i32;
const MyArr = [3]i32;
const Buffer = []u8;
```
**Limitation — alias names are erased:** each alias resolves to its underlying type at registration, so diagnostics and emitted C report the underlying type, never the alias name.

## 2. Memory Management (Arena Pattern)

Z98 relies on **Arena Allocation** for almost all dynamic memory needs. This pattern simplifies memory management and ensures performance on legacy systems.

### 2.1 The Arena API
The standard library re-exports an arena allocator as `std.arena` (`sf/src/std_arena.zig`). It wraps caller-provided backing storage:

- `std.arena.init(data: []u8) Arena` — constructs an `Arena` over the given byte buffer.
- `std.arena.alloc(self: *Arena, size: usize) ArenaError![*]u8` — bumps within the backing storage and returns the raw block, or `error.OutOfMemory` when the arena is exhausted. (`pub const ArenaError = error{OutOfMemory};`)
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

fn MyStruct_init(arena: *std.arena.Arena, x: i32) !*MyStruct {
    const raw = try std.arena.alloc(arena, @sizeOf(MyStruct));
    const self = @ptrCast(*MyStruct, raw);
    self.x = x;
    return self;
}
```
`std.arena.alloc` returns an error union (`ArenaError![*]u8`), so `orelse` is rejected with `error[3016]`; use `try`/`catch`. In a helper that cannot propagate the error, `catch unreachable` is the fallback and now traps (rather than falling through) if the arena is exhausted.

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
  - **Example**: `if (a) { return 1; } else { return 0; }` (the brace-less form `if (a) return 1; else return 0;` is rejected: a semicolon may not precede `else`; write the braces, or omit the semicolon as in `if (a) return 1 else return 0;`). The condition must be `bool`; an assignment is not an expression, so `if (a = 3)` is a parse error.
  - **Optional Capture**: `if (optional_val) |val| statement`. Unwraps the optional value if it is not null. `val` is immutable.
- **If Expressions**: `if (cond) a else b`. Braces are NOT required for expressions. Must have an `else` branch. Result type is merged from both branches.
  - **Optional Capture**: `if (optional_val) |val| a else b`. Supported in expressions.
- `while (cond) : (iter) statement`: While loop with a continue expression. `iter` is evaluated after the loop body on each iteration, before the condition is re-evaluated. Braces are **optional** for the loop body.
  - **Example**: `while (i < 10) i = i + 1;`
  - **Capture**: `while (optional_expr) |capture| { ... }` is supported for optional unwrapping. The loop continues as long as `optional_expr` yields a value.
- `for (iterable) |item| statement`: Simple iteration. Supports one or two capture variables: `|item|` or `|item, index|`. Braces are **optional** for the loop body.
  - **Example**: `for (arr) |item| sum = sum + item;`
  - **Iterables**: Supports arrays (`[N]T`), slices (`[]T`), and ranges (`start..end`).
  - **Explicit Index Range**: `for (arr, start..) |item, index|` and `for (arr, start..end) |item, index|` (Zig 0.15.2 parity) iterate **every** element of the iterable; the index capture is `start + j` (j = the 0-based iteration count) and is **not** clamped to the iterable. `start`/`end` must be `usize`-compatible unsigned integers. `start..end` requires `end - start == arr.len` (a compile-time error when both lengths are known, otherwise a runtime trap under `-fsafe`); `end < start` is an overflow (compile-time error when known, runtime trap otherwise). The index capture is mandatory for this form.
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
  - **Divergent Prongs**: Prongs may contain `return`, `break`, `continue`, or `unreachable`. These prongs have the type `noreturn`. An `unreachable` prong now emits a live trap (`pal_trap()`), not a fall-through no-op (see §4).
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
  - Control flow **out of** a `defer` body is rejected, matching official Zig: `return` anywhere inside the body is `error[3051]` (`cannot return from defer expression`); `break`/`continue` that transfer control out of the body are `error[3052]`/`error[3053]` (`cannot break`/`cannot continue out of defer expression`); `try` is `error[3054]` (`'try' not allowed inside defer expression`). A `break` whose target loop or labeled block, or a `continue` whose target loop, is **declared inside** the body is allowed, and a nested `fn` resets the restriction. The same rule applies to `errdefer`.
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
  - **Operand Requirement**: `orelse` requires an **optional** operand. Applying it to a non-optional value (including an error union) is rejected with `error[3016]: orelse requires an optional operand; use 'catch' for error unions`.

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
- **Validation**: A `break` or `continue` inside `defer`/`errdefer` is rejected with `error[3052]`/`error[3053]` only when it transfers control **out of** the defer body; a `break` targeting a loop or labeled block, or a `continue` targeting a loop, **declared inside** the body is allowed (official Zig behaviour, verified against `AstGen.zig`). `return` and `try` inside the body are always rejected (`error[3051]`/`error[3054]`), except inside a nested `fn`.

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
| `@volatileCast(T, expr)` | Remove the `volatile` qualifier; source must be a volatile pointer and target the same base type |
| `@intCast(T, expr)` | Checked integer conversion / width change |
| `@floatCast(T, expr)` | Float conversion (not runtime-checked; narrowing may lose precision) |
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
- `@panic(msg)`: Evaluates `msg`, writes `panic: <msg>\n` to **stderr**, then **traps** (`pal_trap()`; x86 `int 3`, elsewhere `pal_abort()`). It is typed `noreturn` and is **not** a no-op. `unreachable` is likewise a real unconditional trap. Both trap in `-fsafe` and `-ffast`. `std.debug.assert`/`std.debug.panic` also call `pal_trap()`, but their message is written to **stdout**, which is buffered and may be lost before the trap — treat them as terminators, not as a reliable printed abort.

**C varargs**
- `@cVaStart`, `@cVaArg`, `@cVaEnd`: Access a C variadic argument list (`va_list`).

**Async / coroutines**
- `@asyncInit(ctx, buf, fn, args)`: Initialize a coroutine root frame in `buf` (returns the frame as `*void`). See §4.1.
- `@asyncSuspend(data)`: Explicit suspension point; valid only inside a suspending function. See §4.1.
- `@asyncResume(frame, arg)`: Resume a coroutine step; returns `null` when the coroutine has finished. See §4.1.
- `@asyncFrameSize(fn)`: Compile-time byte size of a suspending function's frame. See §4.1.

**Declarations**
- `@import("file.zig")`: Includes another module. The standard library is imported as `@import("std")`; `sf/src/std.zig` re-exports `io`, `arena`, `str`, `mem`, `math`, `debug`, `net`, `async`, `bits`, `os`, `time`, and `buf`. **Cross-module visibility:** only `pub` declarations are visible to an importing module — a reference through an imported module (flat `mod.member`, nested `mod.sub.member`, or a direct `@import("file.zig").member` callee) to a declaration that is not `pub` is rejected with `error[3007]` (`'<name>' is not marked 'pub'`, matching official Zig 0.15.2), in value positions, type positions, and const-fold positions (array sizes and enum initializers); references to a module's own non-`pub` declarations are unaffected.
- `@cInclude("header.h")`: Emits a C header `#include` (used by the extern OS bindings, e.g. `std.net`).

**Formatted `print`**
- A call whose callee is named `print` (for example `std.io.print`) is a compiler special case: the compiler decomposes the format string and emits one runtime print call per argument.
    - **Format Specifiers**: Supports `{}` (default, decimal), `{d}` (decimal), `{x}` (hex), `{c}` (character), and `{s}` (string). Any other specifier is rejected with `error[3013]`.
    - **Arguments**: The arguments **must** be a tuple literal (e.g., `.{arg1, arg2}`) or a tuple variable. The compiler decomposes the format string and emits individual print calls for each tuple element.
    - This is the only variadic form Z98 supports; there is no `anytype`. The shipped wrapper is `std.io.print(s: [*]const c_char, ...) void`.

### 4.1 Async / coroutines

Z98 supports cooperative, stackless coroutines through four `@async*` builtins and the `std.async` library. There is no `async`/`await` keyword and no `Future(T)` type: coroutine state is type-erased to `*void`, and the scheduler/root driver is the ordinary library module `std.async`.

**Suspending functions.** A function is *suspending* when its body directly contains `@asyncSuspend`, or directly calls a suspending function (the property propagates over the direct-call graph; mutual recursion is ordinary propagation). The compiler computes this set once, before type resolution. Every suspending function is compiled to a *step machine* named `__Z98Step_<f>` with the signature

```zig
fn __Z98Step_<f>(frame: *void, arg: ?*void) ?*void
```

and the original synchronous body is not emitted. The step loads its hidden `state` word, jumps to the resume segment for the current suspension point, runs to the next suspension or to completion, and returns `null` at completion (non-`null` means "still suspended"). The exception is the root `pub fn main`: it keeps its source name/signature plus a minimal synchronous driver that zero-initializes its root frame and drives its own step to completion, so the C `int main` wrapper and direct calls keep working. `main` and `export fn` are ordinary functions for suspension analysis, so either may be suspending; the root `pub fn main` additionally gets the synthesized driver above, and a `main`/`export fn`/helper that is *not* itself suspending can host a `std.async` scheduler loop. A suspending function's address may **not** be taken (`error[3017]`).

**Frame / step ABI.** Each coroutine owns one root *frame* in a caller-supplied buffer. The frame header is `{ step @0 (pointer-sized), ctx (pointer-sized), state (u8/u16/u32) }`, followed by the coroutine's parameters in order, then any locals live across a suspension, then hidden tail slots for child awaits. The `state` width is chosen from the suspension-point count (`u8` ≤ 255, `u16` ≤ 65535, else `u32`). Every frame is padded to 8 bytes. The `step` word is the address of the synthesized `__Z98Step_<f>`; `@asyncResume(frame, arg)` loads that word, calls the step with `(frame, arg)`, and returns its `?*void` result. A direct call to a suspending callee inside a suspending function is an *implicit await*: the step allocates a child frame from the caller's per-task pool, copies the arguments into it, drives the child to completion, and yields to its own driver while the child is still suspended.

**The four builtins.**
- `@asyncInit(ctx, buf, fn, args) *void` — initialize a fresh coroutine root frame in `buf` for the suspending function `fn`, using the per-task `ctx` pool, and return the frame as `*void`. It zero-fills the frame, writes the `__Z98Step_<fn>` word at offset 0, stores `ctx` and `state = 0`, resets the context header (`used = 0`, sticky `oom = 0`), and copies the `args` record **positionally** into `fn`'s parameters (so the record's fields *are* the coroutine's parameters). Pass the record as `@ptrCast(*const void, &record)` — a plain `*const void`, never `?*const void`.
- `@asyncSuspend(data) *void` — an explicit suspension point. Only valid inside a suspending function (`error[3018]` otherwise) and rejected inside `defer`/`errdefer` (`error[3019]`). The `data` operand is accepted and type-checked but is not propagated by the landed step machine: the driver resumes through `@asyncResume`, and a suspended step returns a non-`null` `?*void` sentinel.
- `@asyncResume(frame, arg) ?*void` — resume the coroutine rooted at `frame`, passing `arg` as the step's second argument. Returns `null` when the coroutine has finished and a non-`null` value while it is still suspended. It does not update any scheduler state; the caller (e.g. `std.async`) owns that.
- `@asyncFrameSize(fn)` — the compile-time byte size of the root frame `fn` needs; the result is an untyped integer literal (`TYPE_INT_LIT`). `fn` must resolve to a known suspending function, else `error[3046]`.

**`-fsafe` checks.** Under the default `-fsafe` mode, `@asyncResume` traps if the frame's step word is zero, and `@asyncInit` traps when the frame size is compile-time known **and** the `buf` argument points at a concrete `[N]u8` array whose `N < @asyncFrameSize(fn)`. A slice / many-pointer buffer (`[]u8` / `[*]u8`) has no compile-time length, so the `@asyncInit` bounds check is skipped. `-ffast` emits neither check (a bad frame is undefined behavior). Independently of the mode, `contextInit` (below) traps if the context buffer is not 8-aligned.

**The `std.async` root driver.** The scheduler and per-task child-frame pool live in `std.async`, not in the language. A task is a `Task { frame, ctx, state, cancel_requested, result, arg, waiting_on, has_waiting_on }`; a `Scheduler` holds `[*]*Task`. `@asyncInit` sets up the frame, `addTask` registers the task, and `tick` resumes every runnable task once via `@asyncResume(t.frame, t.arg)`, marking it `done` when the step returns `null`. `Context` owns a per-task LIFO child-frame pool: its 16-byte header is `{ used@0, capacity@4, oom@8, pad@9..15 }`, the pool bytes start at `ctx + 16`, and the caller's buffer must be 8-aligned (back it with a `[K]u64` array, never a bare `[N]u8`). `contextAlloc` rounds `used` up to 8 and returns `error.OutOfFrame` (setting a sticky `oom`) on exhaustion rather than crashing. See `sf/docs/tech_docs/12_async_coroutines.md` for the full API and the converted `rogue_mud` / `mud_server` examples.

## 5. Known Limitations and Workarounds

To maintain C89 compatibility and compiler simplicity, Z98 has the following limitations:

- **No `anyerror`**: The `anyerror` type does not exist in the token set; use explicit error sets (e.g., `const MyError = error { Bad };`) or anonymous error unions `!T`.
- **No Generics**: `comptime` parameters and `anytype` are not supported.
- **No Anonymous Enum Types**: Aggregate type declarations must be named via `const` assignment. Anonymous `struct` type expressions, tuple literals `.{}`, and anonymous struct payloads in tagged union variants are parsed.
- **Strict Coercion**: There is no implicit coercion between `i32` and `usize`. Use `@intCast(usize, ...)` or `@intCast(i32, ...)` when mixing these types in assignments or initializers.
- **No Method Syntax**: `struct.func()` is not supported; use `func(struct)`. (Exception: a call whose callee is named `print` gets format-string lowering; see §4.) A member not found on a value — which is always the case for `struct.func()`, since Z98 aggregate types cannot contain function declarations — is rejected at compile time with `error[3060]` (`no field or member function named '<name>' in <kind> type`), including member access/call on a non-aggregate value (`const x: i32 = 5; x.foo();`); `.len` on an array field, enum/error-set members, module members, `.ptr`, `.tag`/`.payload` and real aggregate fields stay valid. See `sf/docs/tech_docs/05_semantic_analysis.md` §semanticAnalyzerResolveFieldAccess Phases 3/5.
- **AST Lifting**: Most control-flow expressions (`if`, `switch`, `try`, `catch`, `orelse`) are automatically transformed into statement blocks using temporary variables. This enables their use in complex expressions while maintaining C89 compatibility.
- **Runtime Safety (`-fsafe` / `-ffast`)**: `-fsafe` is the **default** and enables six runtime checks — checked cast (`@intCast`), division/modulo-by-zero, shift-count, null-unwrap, index out-of-bounds, and integer overflow (`+`, `-`, `*`, unary `-`). A failed check calls `pal_trap()`. `-ffast` disables all six checks (the compiler self-build uses `-ffast`; user programs default to `-fsafe`). `unreachable`/`@panic` trap in **both** modes. Under `-fsafe`, storage initialized with `undefined` is byte-filled with `0xAA` to make reads visible; `-ffast` emits no poison fill (and does not zero it).
- **Compile-time Diagnostics**: `var x: T;` with no initializer is `error[3014]` (write `= undefined` to opt out). A statement whose result is an error union and is discarded is `error[3015]`. A non-void function that can fall off its end, or a bare `return;` in a non-void function, is `error[3003]` (real reachability; an `if`/`else` where both arms return is not flagged). `orelse` on a non-optional operand is `error[3016]` (see §3.1). A call whose argument count does not match the callee's parameter count is `error[3061]` (`expected N argument(s), found M`; a variadic callee reports `expected at least N ...`), and a call argument whose type is in a different type family from the parameter is `error[3000]` (see Type Coercions below). A cross-module reference to a non-`pub` declaration is `error[3007]` (`'<name>' is not marked 'pub'`; see §4 `@import`). All are mode-independent.

## 6. Z98 Idioms and Best Practices

### 6.1 The Arena Pattern
Dynamic memory should almost exclusively be managed via `std.arena` (`ArenaAllocator` is not the shipped name).
- **Ownership**: Functions should accept an `*std.arena.Arena` rather than "owning" their memory.
- **Allocation is fallible**: `std.arena.alloc` returns `ArenaError![*]u8`, so unwrap with `try`/`catch` (see §2.1/§2.2) — never `orelse`, which is rejected with `error[3016]`.
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
`undefined` is an opt-out of the `error[3014]` "must be initialized" diagnostic, not a guaranteed zero: under `-fsafe` the storage is filled with `0xAA` so an uninitialized read is detectable, and `-ffast` emits no fill at all.

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

### Call-Site Arity and Argument Types
A call is checked against the callee's signature at the call site.

- **Arity**: the argument count must match the callee's parameter count. A variadic callee (`extern fn f(fmt: [*]const u8, ...)`) requires at least its fixed parameters. A violation rejects with `error[3061]` (`expected N argument(s), found M`; variadic too-few: `expected at least N argument(s), found M`) and emits no C.
- **Argument types**: an argument whose type is in a different family from the parameter type rejects with `error[3000]` (`type mismatch in function argument ...`) with `source:`/`target:` notes — e.g. a `bool` passed for an `i32` parameter (previously a silent `bool` -> `i32` coercion), an `i32` for a `f32` parameter, or an integer literal for a `bool` parameter.
- **Still implicit**: Z98's established conversions are unchanged — integer <-> integer of any width/signedness (including `u32` <-> `usize` and narrowing), the pointer/slice/array coercions above, `@enumToInt(<error set>)` into an integer parameter, and `@intCast`-based conversions (which remain the explicit form for a narrowing the program does not want to rely on).

This matches official Zig 0.15.2's rejection of wrong arity and cross-family argument types; the integer-conversion tolerance is the documented Z98 divergence retained for the existing corpus and the compiler's own source.

## 7. Not Yet Supported

### 7.1 Permanently Dropped Features

These were considered and are **not** planned for `zig1`; use the documented idiom instead.

- **`static` declarations**: dropped (the `static` keyword is not in the token set; `static var` is `error[2000]`). Use a container-level `var` for persistent state:
  ```zig
  var g_count: i32 = 0; // file/container scope, persists across calls
  fn bump() void { g_count = g_count + 1; }
  ```
- **`do ... while` loops**: dropped. Use the equivalent `while (true)` idiom with an early `break`:
  ```zig
  while (true) {
      body();
      if (!cond) break;
  }
  ```
  Caveat: `continue` in this emulation skips the condition test and re-enters the body, unlike a real `do ... while`.

`volatile` qualifiers are **no longer** dropped: `*volatile T` / `[*]volatile T` and `@volatileCast` are supported (see §1.2/§4).

### 7.2 Designed, Not Implemented

> The following features appear in design/plan documents for Z98 but are **not implemented** in the current self-hosted `zig1` compiler. Do not rely on them.

- Value-producing labeled blocks (`const n = blk: { ... break :blk 1; };`). Only value-less `break :blk;` is supported.
- `@errorName`.
- `extern struct`, `opaque`, and `vector` types.
- Generics, `anytype` parameters, `@Type`, `@typeInfo`, and `comptime`.
- The `anyerror` type (use explicit error sets or `!T`).
- `@cImport` (use bare `extern` declarations plus `@cInclude`).
- `std.Io` / an event-loop interface, preemption, threads, and typed futures (`Future(T)`): the `@async*` coroutines (§4.1) are cooperative and round-robin only, and coroutine state is type-erased to `*void`.
- Compile-time integer semantics (implemented; Task 2-5 of the comptime-int parity plan). Values are arbitrary-precision within a **256-bit magnitude cap** and **signedness-free until materialised**; `-0` normalises to `0`. `+`, `-`, `*`, `/` (truncating toward zero), `%` (truncating remainder), unary `-`, `&`, `|`, `^`, `~` (`~x = -x - 1`), `<<` and `>>` (floor) are exact; a result needing more than 256 magnitude bits, division/mod by zero, or an out-of-domain shift count is *unfoldable* (the existing reject/runtime path), never wrapped. Source integer literals are `u64`-lossy at lex/parse time (a literal `>= 2^64` clamps to `u64` max), so the cap governs arithmetic results, not literal spellings.
- **Comparisons are signedness-free and exact** over magnitude+sign, and the short-circuit logical ops (`and`/`or`/`!`) fold like Zig. The Task 9D bounded divergence is RETIRED: `(umax - 1) > 0`, `0 < (umax - 1)`, `(umax - 1) > zero`, `umax > (0 + 0)`, `(a + 1) == 2`, `(imin + 1) < 0` and `-9223372036854775808 < 0` fold exactly, including when the condition of a capture-free no-`else` value `if` is stored and its branch elided at lowering (module-scope operands are runtime-equal to Zig; a then-arm that returns is handled, Task 3 fix rounds 1-2). The old divergence fixture was **split, not flipped wholesale**: its arithmetic-derived sites `subGt0`, `zeroLtSub`, `subGtZeroConst`, `gtAddZero`, `arithEq` (plus the `i64`-extreme `(imin + 1) < 0` / `(imax - 1) > 0` shapes) became accepted Zig-equal positives (`repro/mi_matrix/stdlib_comptime_compare_xmod`), while `subLt0` (`(umax - 1) < 0`) and `u8SubLt0` (`(u - 300) < 0` on a `u8`) stay rejected because official Zig rejects them too (`error[3059]`, now pinned with the other reject sites in `repro/mi_matrix/comptime_compare_reject_xmod`); `repro/mi_matrix/comptime_compare_diverge_reject_xmod` was removed.
- Arithmetic folds over a DECLARED integer operand apply a **peer-fit rule**: an untyped operand's exact value and the exact result must fit the operand's sema type (including the unary `-`, nested arithmetic, and a name typed through an unannotated `const`'s initializer), so Zig-rejected shapes (`u - 300` on a `u8`, `0 - umax` and `-umax` on a `u64`) stay rejected. `~` is EXEMPT: Z98 folds the exact `-x - 1` while sema types `~x` as x's type and the runtime complement wraps — the accepted `(~u) != 0` class is runtime-equal to Zig, but a shape depending on the wrapped value (`(~u) == 4294967295` with `u: u32`) can false-reject (pre-existing divergence).
- **Coercion happens only at materialisation**, against the target's exact width/signedness (`comptimeIntFitsType`), preserving the existing diagnostics (`error[3000]`/`[3050]`/`[3055]`/`[3059]`). Sites: typed `var`/`const` declarations, parameters, returns, `@intCast`/`@as` targets, enum backing/member values, and array sizes. The **array-size evaluator** folds exactly and accepts `0..0xFFFFFFFE` (the `0xFFFFFFFF` unfolding sentinel collision is pre-existing), so `[0 - 1]u8` is `error[3050]`, while `[1 << 4]u8`, `[(2 + 1) * 2]u8`, `[(1 << 200) >> 190]u8` and a module-const chain fold exactly. The **enum evaluator** materialises through the `[i64 min, u64 max]` member-storage window, so `enum(u64) { A = (1 << 200) >> 190 }` folds `1024`, while `enum { A = 18446744073709551615 + 1 }` and `enum(u64) { A = 18446744073709551615 * 2 }` are clean `error[3055]` rejects (the old 64-bit wrappers stored `0` / `2^64 - 2` silently).
- **Remaining bounded divergences** (documented, deliberately not full parity): `const BIGFOLD = 1 << 100;` in a runtime/untyped slot rejects `error[3000]` where Zig accepts (Z98 has no >64-bit runtime integer slot; `repro/mi_matrix/comptime_coerce_reject_xmod`); `%` on signed comptime integers and `~` on `comptime_int` are accepted where Zig 0.15.2 requires `@rem` / rejects `~`; an over-u32 array size (`[1 << 40]u8`) is `error[3050]` although Zig accepts it at compile time (Z98's array length field is `u32`); **float comparisons fold (Task 9, Part II)** at the compiler's established `f64` precision with an exact-representability peer rule — an integer operand participates only when it fits the peer's significand (53 bits for `f64`/`comptime_float`, 24 for `f32`; its significant-bit count is `bitlen(magnitude) - trailing zeros`, corrected by Task 9 fix round 1), an `f32` operand against a non-`f32`-exact untyped literal declines, and `comptime_float` literals compare at `f64` rather than Zig's `f128` (bounded residual; `repro/mi_matrix/stdlib_comptime_float_compare_xmod` + `comptime_float_compare_reject_xmod`), while float comptime arithmetic precision stays out of scope; `@intToFloat` of a value above 2^53 may differ from a correctly-rounded conversion by 1 ulp. Fixtures: `repro/mi_matrix/stdlib_comptime_compare_xmod`, `comptime_compare_reject_xmod`, `stdlib_comptime_float_compare_xmod`, `stdlib_comptime_noreturn_if_xmod`, `stdlib_comptime_bigint_arith_xmod`, `stdlib_comptime_coerce_typed_slots_xmod`, `comptime_coerce_reject_xmod`, `array_size_negative_reject_xmod`, `stdlib_comptime_constfold_exact_xmod`, `comptime_constfold_reject_xmod`; standalone repros under `repro/comptime_*.z98`.
