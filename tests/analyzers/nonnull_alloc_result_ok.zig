// nonnull_alloc_result_ok.zig — Task 9h D4h fixture.
//
// A `catch unreachable` allocator result is non-optional and non-null; casting
// it with `@ptrCast` and dereferencing the result must not emit WARN_6002.
const Sand = struct { dummy: u32 };

fn sandAlloc(s: *Sand, n: usize, a: usize) !*u8 {
    _ = s;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn alloc_result_ok(s: *Sand) u8 {
    var raw: *u8 = sandAlloc(s, 4, 4) catch unreachable;
    var p: *u8 = @ptrCast(*u8, raw);
    return p.*;
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    _ = alloc_result_ok(&s);
}
