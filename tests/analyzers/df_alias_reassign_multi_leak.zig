// df_alias_reassign_multi_leak.zig — Task 9c fix round 2: multi-alias
// reassignment leak de-duplication.
//
// Contract (analyzer tests/analyzers runner): exactly one WARN_6005. The
// first allocation survives under the `q`/`r` alias class after `p` is
// reassigned, so it is reported once at scope exit, not once per surviving
// alias. The new allocation through `p` is freed.
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

fn alias_reassign_multi_leak(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = p;
    var r: *u8 = p;
    p = sandAlloc(s, 4, 4);
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    alias_reassign_multi_leak(&s);
}
