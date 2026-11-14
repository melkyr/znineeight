// gpa_leak.zig — Task 7 GPA-aware analyzer fixture.
//
// Contract (analyzer tests/analyzers runner): 0 errors, >=1 warning
// (WARN_6005_MEMORY_LEAK). Bare `gpaAlloc` call pins the bare-callee shape.
fn gpaAlloc(g: *u32, n: usize, a: usize) *u8 {
    _ = g;
    _ = n;
    _ = a;
    return @intToPtr(*u8, 8);
}

fn leak(g: *u32) void {
    var p: *u8 = gpaAlloc(g, 4, 4);
    _ = p;
}

pub fn main() void {
    var g: u32 = 0;
    leak(&g);
}
