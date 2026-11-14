// orelse_optional_control_xmod — GREEN control (A20). A valid `?T` `orelse`
// must still compile and run: value, block, `unreachable`, and `return`
// fallbacks all preserved by the sema guard.
// Contract: 5\n99\n7\n88\n77\n (rc=0).
const std = @import("std");

fn maybe(seed: i32) ?i32 {
    if (seed > 0) return seed;
    return null;
}

fn useReturn(seed: i32) ?i32 {
    var x = maybe(seed) orelse return null;
    return x;
}

fn useBlock(seed: i32) ?i32 {
    var x = maybe(seed) orelse {
        return null;
    };
    return x;
}

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

pub fn main() void {
    var a = maybe(5) orelse 0;
    var b = maybe(-1) orelse 99;
    var c = maybe(7) orelse unreachable;
    var d = useReturn(-1) orelse 88;
    var e = useBlock(-1) orelse 77;
    p(a);
    p(b);
    p(c);
    p(d);
    p(e);
}
