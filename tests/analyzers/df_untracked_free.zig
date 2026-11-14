// df_untracked_free.zig — Task 9c fix round 2: untracked-free regression.
//
// Contract (analyzer tests/analyzers runner): exactly one WARN_6006. A null
// binding is recorded as `untracked`; freeing it must keep that state and
// report the untracked free instead of silently converting it to `freed`.
const Sand = struct { dummy: u32 };

fn sandFree(s: *Sand, p: *u8) void {
    _ = s;
    _ = p;
}

fn untracked_free(s: *Sand) void {
    var p: *u8 = null;
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    untracked_free(&s);
}
