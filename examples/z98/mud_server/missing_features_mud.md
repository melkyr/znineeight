# MUD Server: Missing Features and Workarounds

This document tracks the language limitations, compiler caveats, and workarounds identified during the development of the Z98 MUD Server example.

## 1. Global Aggregate Constants (Bug)

**Issue**: Declaring a `pub const` array of structs with complex initializers (like nested strings or union tags) fails to generate correct C89 code. The constant is referenced in the C source but its definition is missing from both `.c` and `.h` files.

**Workaround**: Change the `const` to a `var` and perform initialization at runtime.
```zig
// Before (Fails)
pub const rooms = [2]Room{ ... };

// After (Works)
var rooms: [2]Room = undefined;
fn initRooms() void {
    rooms[0] = Room { ... };
}
```

## 2. Platform `fd_set` Mapping

**Issue**: The size of `fd_set` varies significantly between platforms (260 bytes on 32-bit Windows, 128 bytes on Linux). Z98 doesn't yet support automatic C-struct size introspection for `extern struct`.

**Workaround**: Defined `plat_fd_set` as a sufficiently large opaque buffer (`[512]u8`) to prevent stack corruption when passed to PAL functions.

## 3. String Literal Coercion to `[*]u8`

**Issue**: While string literals in Z98 can coerce to slices, passing them directly to PAL functions expecting `[*]const u8` (like `plat_send`) often requires manual pointer access.

**Workaround**: Use the `.ptr` property of the string literal or slice.
```zig
const msg = "Hello\r\n";
_ = plat_send(client, msg.ptr, @intCast(i32, msg.len));
```

## 4. `std.debug.print` Signature

**Issue**: The bootstrap version of `std.debug.print` is not variadic. It requires exactly two arguments: a format string and an anonymous literal (tuple) for arguments.

**Workaround**: Always provide a tuple, even if empty.
```zig
std.debug.print("Server started\n", .{});
```

## 5. Strict Type Equality in Assignments

**Issue**: Unlike modern Zig, the Z98 bootstrap compiler (following C89 rules) is very strict about type equality in assignments. Implicit narrowing (e.g., `i32` literal to `u8` field) often fails.

**Workaround**: Use `@intCast` for all numeric field initializations and assignments.
```zig
.north = @intCast(u8, 1),
```

## 6. Switch Expression Exhaustiveness

**Issue**: Switch expressions must have an `else` prong to be valid in the bootstrap compiler, even if all enum variants appear to be covered.

**Workaround**: Always add an `else` prong to value-returning switches.

## 7. PAL Linkage

**Issue**: Because the Platform Abstraction Layer (PAL) is implemented in C++ (`platform.cpp`) but the compiler generates C code, name mangling causes "undefined reference" errors during the final link stage.

**Workaround**: Wrapped all networking function declarations in `src/include/platform.hpp` with `extern "C"`.

## 8. 8.3 Filename Constraints

**Issue**: Windows 98 has limited support for long filenames in some toolchains. The compiler issues warnings for files like `std_debug.zig`.

**Workaround**: None required for the example to function, but warnings are expected during compilation.
