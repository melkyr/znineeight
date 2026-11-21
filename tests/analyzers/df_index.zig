// df_index.zig — Task 9c DF-2 index-chain free fixture.
//
// Contract (analyzer tests/analyzers runner): exactly one ERR_2005 double
// free. The allocation is stored in `arr[0]`; `sandFree(s, arr[0])` resolves
// through the index twice. No false INFO_7001 for the allocator handle and no
// leak.
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

fn index_free(s: *Sand) void {
    var arr: [8]*u8 = undefined;
    arr[0] = sandAlloc(s, 4, 4);
    sandFree(s, arr[0]);
    sandFree(s, arr[0]);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    index_free(&s);
}
