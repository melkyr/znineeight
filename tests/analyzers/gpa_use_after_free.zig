// gpa_use_after_free.zig — Task 7 GPA-aware analyzer fixture.
//
// Contract (analyzer tests/analyzers runner): >=4 errors
// (ERR_2006_USE_AFTER_FREE, rendered as error[3079]). Module-qualified
// allocation/free calls pin the member-call matcher. Each function is a
// separate same-block case: direct indexed read, comparison wrapper,
// compound assignment, and arithmetic wrapper.
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

fn use_after_free_compare(g: *Gpa) void {
    var p: *u8 = gpa.gpaAlloc(g, 4, 4);
    gpa.gpaFree(g, p);
    if (p[0] == 0) {
        var v: u8 = 1;
        _ = v;
    }
}

fn use_after_free_compound(g: *Gpa) void {
    var p: *u8 = gpa.gpaAlloc(g, 4, 4);
    gpa.gpaFree(g, p);
    p[0] += 1;
}

fn use_after_free_arith(g: *Gpa) void {
    var p: *u8 = gpa.gpaAlloc(g, 4, 4);
    gpa.gpaFree(g, p);
    var v: u8 = p[0] + 1;
    _ = v;
}

pub fn main() void {
    var g: Gpa = Gpa{ .dummy = 0 };
    use_after_free(&g);
    use_after_free_compare(&g);
    use_after_free_compound(&g);
    use_after_free_arith(&g);
}
