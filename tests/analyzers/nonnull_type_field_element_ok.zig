// nonnull_type_field_element_ok.zig — Task 9h2 D4h2 fixture.
//
// A declared non-optional pointer field (`Holder.p: *u32`) and an element of a
// slice of non-optional pointers (`[]*u32`) are statically non-null bases, so
// neither dereference emits WARN_6002.
const Holder = struct { p: *u32, q: ?*u32 };

fn field_ok(h: *Holder) u32 {
    var v: u32 = h.p.*;
    _ = h.q;
    return v;
}

fn element_ok(xs: []*u32) u32 {
    return xs[0].*;
}

pub fn main() void {
    var x: u32 = 7;
    _ = x;
}
