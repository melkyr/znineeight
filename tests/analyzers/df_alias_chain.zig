// df_alias_chain.zig — Task 9c DF-1 alias-state propagation fixture.
//
// Contract (analyzer tests/analyzers runner): exactly one ERR_2005 double
// free. `var q = p` and `r = q` are aliases of the single allocation; freeing
// `p` and then `r` is the same allocation freed twice. No WARN_6006 (the
// aliases are tracked, not untracked) and no leak.
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

fn alias_chain(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = p;
    var r: *u8 = undefined;
    r = q;
    sandFree(s, p);
    sandFree(s, r);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    alias_chain(&s);
}
