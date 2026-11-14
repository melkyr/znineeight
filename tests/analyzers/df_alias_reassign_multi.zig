// df_alias_reassign_multi.zig — Task 9c fix round 2: multi-alias reassignment.
//
// Contract (analyzer tests/analyzers runner): zero diagnostics. `q` and `r`
// both alias the first allocation; reassigning the canonical name `p` must
// keep the survivors in ONE alias class. Freeing `q` releases the old
// allocation for the whole class, so `r` is not a stale leak and freeing `p`
// releases the second allocation.
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

fn alias_reassign_multi(s: *Sand) void {
    var p: *u8 = sandAlloc(s, 4, 4);
    var q: *u8 = p;
    var r: *u8 = p;
    p = sandAlloc(s, 4, 4);
    sandFree(s, q);
    sandFree(s, p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    alias_reassign_multi(&s);
}
