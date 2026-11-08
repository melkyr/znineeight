// df_alias_reassign.zig — Task 9c fix regression: canonical reassignment.
//
// Contract (analyzer tests/analyzers runner): zero diagnostics. `q` aliases
// the first allocation; reassigning `p` must detach `q` from the canonical
// name instead of rebinding it to the new allocation. Freeing `q` then `p`
// releases two distinct allocations, so there is no double free and no
// overwrite leak (the old allocation is still owned by `q`).
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

fn alias_reassign(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = p;
    p = sandAlloc(s, 4, 4);
    sandFree(s, q);
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    alias_reassign(&s);
}
