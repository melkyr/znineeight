// gpa_double_free.zig — Task 7 GPA-aware analyzer fixture.
//
// Contract (analyzer tests/analyzers runner): >=1 error (ERR_2005 double
// free). Uses module-qualified calls (`gpa.gpaAlloc` / `gpa.gpaFree`) so the
// final-identifier callee matching is exercised on the double-free path too.
const Gpa = struct { dummy: u32 };

const gpa = @import("gpa.zig");

fn gpaAlloc(g: *Gpa, n: usize, a: usize) *u8 {
    _ = g;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn gpaFree(g: *Gpa, p: *u8) void {
    _ = g;
    _ = p;
}

fn double_free(g: *Gpa) void {
    var p: *u8 = gpa.gpaAlloc(g, 4, 4);
    gpa.gpaFree(g, p);
    gpa.gpaFree(g, p);
}

pub fn main() void {
    var g: Gpa = Gpa{ .dummy = 0 };
    double_free(&g);
}
