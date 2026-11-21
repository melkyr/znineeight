// df_alloc_handle_var.zig — Task 9c fix regression: allocator handles in
// `var` initializers must be recorded.
//
// Contract (analyzer tests/analyzers runner): zero diagnostics. `h` is the
// allocator argument of the allocation stored in `p` (a `var` initializer,
// not a statement-level call), so `take(h)` must not be an ownership transfer
// and both `p` and `h` free exactly once.
const Sand = struct { dummy: u32 };

fn sandAlloc(s: *Sand, n: usize, a: usize) *Sand {
    _ = s;
    _ = n;
    _ = a;
    return @intToPtr(*Sand, 8);
}

fn sandFree(s: *Sand, p: *Sand) void {
    _ = s;
    _ = p;
}

fn take(p: *Sand) void {
    _ = p;
}

fn alloc_handle_var(s: *Sand) void {
    var h: *Sand = sandAlloc(s, 4, 4);
    var p: *Sand = sandAlloc(h, 4, 4);
    take(h);
    sandFree(h, p);
    sandFree(s, h);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    alloc_handle_var(&s);
}
