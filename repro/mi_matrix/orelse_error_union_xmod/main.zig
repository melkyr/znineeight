// orelse_error_union_xmod — RED->GREEN sema guard (A20). An ERROR UNION is not
// an optional; spec 3.1 assigns error unions to `catch`, so `orelse` on an
// error-union operand must be a clean sema reject (it must NOT be accepted).
//
// RED (pre-fix): the error-union operand is silently typed void, so this dump
// exits rc=0 and emits gcc-invalid C (`has no member named 'has_value'`) — the
// silent-bad-output class. GREEN: dump rc=2, 0 `.c`, error[3016].
const std = @import("std");

const E = error{Bad};

fn get() E![*]u8 {
    return @ptrCast([*]u8, 0);
}

pub fn main() void {
    var p = @ptrCast([*]u8, get() orelse @ptrCast([*]u8, 0));
    std.io.printInt(@intCast(i32, @intFromPtr(p)));
    std.io.writeByte('\n');
}
