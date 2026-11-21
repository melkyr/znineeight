// df_owner_handle.zig — Task 9c DF-3 ownership-precision fixture.
//
// Contract (analyzer tests/analyzers runner): zero diagnostics. Passing the
// allocator handle to `sandFree(h, p)` is not an ownership transfer; `h`
// keeps its allocation state and is freed by the following `sandFree`. The
// false INFO_7001/leak-suppression from the old ownership pass is gone.
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

fn owner_handle(s: *Sand) void {
    var p: *Sand = sandAlloc(s, 4, 4);
    var h: *Sand = sandAlloc(s, 4, 4);
    sandFree(h, p);
    sandFree(s, h);
    take(p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    owner_handle(&s);
}
