// empty_named_struct_xmod — A2 regression: an empty named struct's layout.
//
// DEFECT (seed v90): `populateTypePayload` (`sf/src/symbol_registrator.zig`)
// early-returned for a container with no children, so an empty named
// `struct {}` never got a `StructPayload` and kept `payload_idx = 0`, aliasing
// a foreign `st_items[0]` (or uninitialized memory). Empty `E` folded to the
// aliased struct's fields — `@sizeOf/@alignOf/@bitSizeOf` printed `12/4/96`
// (a std `Arena`) — and a bare `const E = struct {};` segfaulted (rc 139).
//
// FIX (A2-F): keep populating container kinds regardless of child count and
// always append a `StructPayload`, so an empty struct reaches the min-1 clamp
// in `layoutCompute` (size 1 / align 1); `emitStructType` emits
// `unsigned char _[1];` so the C layout matches.
//
// GREEN contract: rc 0 and stdout `1\n1\n8` (RUNRC 0).
// Seed v90 is RED by golden mismatch: it prints `12\n4\n96`.
const std = @import("std");
const E = struct {};
fn pl(n: i32) void { std.io.printInt(n); std.io.print("\n"); }
pub fn main() void {
    pl(@intCast(i32, @sizeOf(E)));
    pl(@intCast(i32, @alignOf(E)));
    pl(@intCast(i32, @bitSizeOf(E)));
}
