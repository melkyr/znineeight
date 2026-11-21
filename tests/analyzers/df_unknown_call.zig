// df_unknown_call.zig — Task 9c fix regression: unknown calls do not transfer.
//
// Contract (analyzer tests/analyzers runner): zero diagnostics. `read` is not
// an ownership-taking site, so passing `p` must not emit INFO_7001 or turn
// the later `sandFree(s, p)` into a false WARN_6006.
const Sand = struct { dummy: u32 };

fn sandAlloc(s: *Sand, n: usize, a: usize) *u8 {
    _ = s;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn sandFree(s: *Sand, p: *u8) void {
    _ = s;
    _ = p;
}

fn read(p: *u8) void {
    _ = p;
}

fn unknown_call(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    read(p);
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    unknown_call(&s);
}
