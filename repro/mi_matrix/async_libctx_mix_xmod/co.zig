pub const CArgs = struct { out: *u32 };

fn callee(out: *u32) void {
    @asyncSuspend(null);
    out.* = 41;
}

pub fn caller(out: *u32) void {
    var tmp: u32 = 0;
    callee(&tmp);
    out.* = tmp;
}
