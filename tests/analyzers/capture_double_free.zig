// capture_double_free.zig — T5 DoubleFreeAnalyzer capture propagation fixture.
//
// Contract (analyzer tests/analyzers runner): >=1 error (ERR_2005 double
// free) — the capture `q` inherits `op`'s allocated state (op marked
// transferred), so the second `sandFree(s, q)` is a double free.
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

fn dbl_via_capture(s: *Sand) void {
    var op: ?*u8 = sandAlloc(s, 4, 4);
    if (op) |q| {
        sandFree(s, q);
        sandFree(s, q);
    }
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    dbl_via_capture(&s);
}
