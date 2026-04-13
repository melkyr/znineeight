# MUD Server: Missing Features and Workarounds

During the implementation of the minimal telnet MUD server using the Z98 bootstrap compiler (Milestone 11/12), several language limitations were identified. This document outlines those missing features and the workarounds used in `examples/mud_server/main.zig`.

## 1. Lack of Pointer Captures in Loops
**Issue**: The current compiler does not support pointer captures in `if` or `while` statements (e.g., `if (slot) |*p|`).
**Workaround**: Use an explicit `active` boolean flag in the `Player` struct and iterate using indices. Take the address of the player manually:
```zig
var p = &players[slot_idx];
if (p.active) { ... }
```

## 2. Incomplete Tagged Union Payload Coercion
**Issue**: Automatic coercion of naked tags (e.g., `.North`) into tagged union variants (e.g., `Command{ .Go = .North }`) is sometimes ambiguous or unsupported in complex nested expressions.
**Workaround**: Use fully qualified variant initializers:
```zig
return Command{ .Go = Direction.North };
```

## 3. Global Aggregate Array Initialization
**Issue**: Initializing global arrays of structs (e.g., `rooms`) directly at the top level is not fully stabilized.
**Workaround**: Declare the global array as `undefined` and initialize it in a dedicated `init()` function called at the start of `main()`:
```zig
var rooms: [2]Room = undefined;
fn initRooms() void {
    rooms[0] = Room{ ... };
}
```

## 4. Strict C89 Integer Type Coercion
**Issue**: The C89 backend is very strict about integer types. Implicit coercion between `i32`, `u8`, `usize`, etc., often fails or requires explicit `@intCast`.
**Workaround**: Use `@intCast` liberally, even for zero-initialization if necessary:
```zig
.pos = @intCast(usize, 0),
```

## 5. Slice Property Access on Extern Structs
**Issue**: Accessing properties like `.ptr` or `.len` on slices returned from or passed to `extern "c"` functions sometimes triggers type checker errors.
**Workaround**: Explicitly declare slice variables before passing them to PAL functions:
```zig
const welcome: []const u8 = "Welcome...\n";
_ = plat_send(client, welcome.ptr, @intCast(i32, welcome.len));
```

## 6. Compiler Bug: Optional Pointer Initialization
**Note**: During verification, it was found that the compiler sometimes emits incorrect C code for initializing `Optional` pointers in `extern "c"` calls (swapping the value and `has_value` fields in the initializer list).
**Status**: Not yet fixed in the compiler; tracked as a known bootstrap regression.

## 7. Lack of Tuple Print Support
**Issue**: `std.debug.print` does not yet support tuple literals for formatting (e.g., `print("val: {}", .{val})`).
**Workaround**: Hardcode strings or use multiple print calls for now. The MUD server uses hardcoded strings for port logging.
