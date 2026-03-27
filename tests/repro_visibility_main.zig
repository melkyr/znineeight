const r = @import("repro_visibility_recursive.zig");

pub fn main() void {
    var v: r.Value = undefined;
    _ = v;
    _ = r.process(&v);
}
