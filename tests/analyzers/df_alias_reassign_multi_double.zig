// df_alias_reassign_multi_double.zig — Task 9c fix round 2: multi-alias
// reassignment double free.
//
// Contract (analyzer tests/analyzers runner): exactly one ERR_2005. `q` and
// `r` are one alias class for the first allocation after `p` is reassigned;
// freeing `q` then `r` frees the same allocation twice. Freeing the new `p`
// afterwards is clean.
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

fn alias_reassign_multi_double(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = p;
    var r: *u8 = p;
    p = sandAlloc(s, 4, 4);
    sandFree(s, q);
    sandFree(s, r);
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    alias_reassign_multi_double(&s);
}
