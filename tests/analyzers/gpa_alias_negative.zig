// gpa_alias_negative.zig — Task 7 GPA-aware analyzer fixture.
//
// Contract (analyzer tests/analyzers runner): 0 errors, 0 warnings. The
// pointer is copied before the original is freed and the copy is used after
// the free. This is the documented limitation: no alias tracking, so no
// ERR_2006 is claimed; the original free also clears the leak warning.
fn gpaAlloc(g: *u32, n: usize, a: usize) *u8 {
    _ = g;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn gpaFree(g: *u32, p: *u8) void {
    _ = g;
    _ = p;
}

fn alias_negative(g: *u32) void {
    var p: *u8 = gpaAlloc(g, 4, 4);
    var q: *u8 = p;
    gpaFree(g, p);
    q[0] = 1;
}

pub fn main() void {
    var g: u32 = 0;
    alias_negative(&g);
}
