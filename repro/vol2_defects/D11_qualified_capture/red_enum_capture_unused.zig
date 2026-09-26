// D11 bundled sibling (FE): an UNUSED capture on an enum switch. The capture
// is never referenced, so sema accepts it, but the pre-fix lowering indexed
// the tagged-union payload table with the enum type's payload index and
// SIGSEGV'd the compiler (rc 139, 0 `.c`) for BOTH spellings.
const std = @import("std");

const Color = enum { red, green, blue };

fn shorthand(c: Color) i32 {
    return switch (c) {
        .red => |v| 1,
        else => 0,
    };
}

fn qualified(c: Color) i32 {
    return switch (c) {
        Color.green => |v| 2,
        else => 0,
    };
}

pub fn main() void {
    std.io.print("{} {}\n", .{ shorthand(Color.red), qualified(Color.green) });
}
