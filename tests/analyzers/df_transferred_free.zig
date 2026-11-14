// df_transferred_free.zig — Task 9c DF-4 lossless-free fixture.
//
// Contract (analyzer tests/analyzers runner): one INFO_7001 (the real
// ownership-taking call) and one WARN_6006 (documented diagnostic for freeing
// a `transferred` pointer). The `transferred` state is not silently converted
// to `freed`, so there is no false ERR_2005 and no leak.
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

fn take(p: *u8) void {
    _ = p;
}

fn transferred_free(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    take(p);
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    transferred_free(&s);
}
