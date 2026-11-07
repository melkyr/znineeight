// gpa_use_after_free.zig — Task 7 GPA-aware analyzer fixture.
//
// Contract (analyzer tests/analyzers runner): >=1 error
// (ERR_2006_USE_AFTER_FREE, rendered as error[3079]). Module-qualified
// allocation/free calls pin the member-call matcher; the indexed read after
// the free is the use.
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

fn use_after_free(g: *Gpa) void {
    var p: *u8 = gpa.gpaAlloc(g, 4, 4);
    gpa.gpaFree(g, p);
    var v: u8 = p[0];
    _ = v;
}

pub fn main() void {
    var g: Gpa = Gpa{ .dummy = 0 };
    use_after_free(&g);
}
