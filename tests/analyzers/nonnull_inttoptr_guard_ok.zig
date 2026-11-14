// nonnull_inttoptr_guard_ok.zig — Task 9h D4h fixture.
//
// `@intToPtr` from a non-zero literal, or from a value guarded non-zero by
// `if (addr != 0)`, is a statically non-null base.
fn inttoptr_literal_ok() u32 {
    var p: *u32 = @intToPtr(*u32, 8);
    return p.*;
}

fn inttoptr_guard_ok(addr: usize) u32 {
    if (addr != 0) {
        var p: *u32 = @intToPtr(*u32, addr);
        return p.*;
    }
    return 0;
}

pub fn main() void {
    _ = inttoptr_literal_ok();
    _ = inttoptr_guard_ok(8);
}
