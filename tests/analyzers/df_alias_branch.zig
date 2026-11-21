// df_alias_branch.zig — Task 9c fix regression: branch-scoped aliases.
//
// Contract (analyzer tests/analyzers runner): zero diagnostics. The `then`
// arm aliases `q` to `a`; the `else` arm gives `q` its own allocation. The
// then-arm alias must not leak into the else fork (no false overwrite/leak),
// and both paths free exactly one allocation per name.
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

fn branch_alias(cond: bool, s: *Sand) void {
    var a: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = undefined;
    if (cond) {
        q = a;
    } else {
        q = sandAlloc(s, 4, 4);
        sandFree(s, q);
    }
    if (cond) {
        sandFree(s, a);
    } else {
        sandFree(s, a);
    }
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    branch_alias(false, &s);
}
