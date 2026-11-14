// dead_arm.zig — T5 comptime-dead-arm fixture (T3 interaction).
//
// Contract (analyzer tests/analyzers runner): 0 errors, 0 warnings. Per Zig
// semantics the comptime-untaken arm does not exist for analysis (T3 rule):
// the double free and the local-address return sit behind `if (false)` and
// must produce no diagnostics. The live trailing free is clean.
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

fn deadarm(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var x: i32 = 10;
    if (false) {
        sandFree(s, p);
        sandFree(s, p);
        _ = &x;
    }
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    deadarm(&s);
}
