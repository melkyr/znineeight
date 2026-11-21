// orelse_requires_optional_xmod — RED->GREEN sema guard (A20). `orelse` is for
// optional types only (spec 3.1); applied to a concrete NON-OPTIONAL operand it
// must be a clean sema reject.
//
// RED (pre-fix): the orelse operand type is silently typed void, so this dump
// exits rc=0 and emits gcc-invalid C (`request for member 'has_value' in
// something not a structure or union`) — the A7F/A19 silent-bad-output class.
// GREEN: dump rc=2, 0 `.c`, error[3016]: orelse requires an optional operand.
const std = @import("std");

var buf: [4]u8 = [_]u8{ 1, 2, 3, 4 };

fn get() [*]u8 {
    return @ptrCast([*]u8, &buf[0]);
}

pub fn main() void {
    var p = @ptrCast([*]u8, get() orelse @ptrCast([*]u8, 0));
    std.io.printInt(@intCast(i32, @intFromPtr(p)));
    std.io.writeByte('\n');
}
