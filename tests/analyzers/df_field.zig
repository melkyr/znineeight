// df_field.zig — Task 9c DF-2 field-chain free fixture.
//
// Contract (analyzer tests/analyzers runner): exactly one ERR_2005 double
// free. The allocation is stored in `st.p`; `sandFree(s, st.p)` resolves
// through the field twice. No false INFO_7001 for the allocator handle and no
// leak.
const Sand = struct { dummy: u32 };
const Holder = struct { p: *u8 };

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

fn field_free(s: *Sand) void {
    var st: Holder = undefined;
    st.p = sandAlloc(s, 4, 4);
    sandFree(s, st.p);
    sandFree(s, st.p);
}

pub fn main() void {
    var s: Sand = Sand{ .dummy = 0 };
    field_free(&s);
}
