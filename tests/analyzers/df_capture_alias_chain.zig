// df_capture_alias_chain.zig — Task 9c DF-1 exact defect-c fixture.
//
// Contract (analyzer tests/analyzers runner): exactly one ERR_2005 double
// free. The allocation is aliased into `op`, then unwrapped into the capture
// `q`; `p` and `q` name the same allocation, so freeing both is a double
// free. No WARN_6006 and no leak.
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

fn capture_alias_chain(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var op: ?*u8 = p;
    if (op) |q| {
        sandFree(s, p);
        sandFree(s, q);
    }
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    capture_alias_chain(&s);
}
