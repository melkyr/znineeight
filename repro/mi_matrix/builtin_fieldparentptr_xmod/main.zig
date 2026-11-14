// builtin_fieldparentptr_xmod — FEATURE-GAP RED fixture (@fieldParentPtr).
// Feature: @fieldParentPtr(Outer, "field", &o.field) -> *Outer.
// RED today: unrecognized -> clean FAIL.
// GREEN (contract): "1\n" — recovered pointer equals &o.
const std = @import("std");

const Inner = struct { val: i32 };
const Outer = struct { tag: u8, inner: Inner };

pub fn main() void {
    var o: Outer = undefined;
    o.tag = 42;
    o.inner = Inner{ .val = 1 };
    var po = @fieldParentPtr(Outer, "inner", &o.inner);
    var ok: i32 = 0;
    if (@ptrToInt(po) == @ptrToInt(&o)) { ok = 1; }
    std.io.printInt(ok);
    std.io.writeByte('\n');
}
