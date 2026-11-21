pub const CArgs = struct { out: *i32 };

fn callee(out: *i32) void {
    @asyncSuspend(null);
    out.* = 10;
}

pub fn caller(out: *i32) void {
    var tmp: i32 = 0;
    callee(&tmp);
    out.* = tmp;
}
