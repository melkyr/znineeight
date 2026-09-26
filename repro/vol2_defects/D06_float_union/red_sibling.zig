// D6 sibling shape: an f32 payload literal in a union that ALSO has an f64
// variant. Before FF the emitter inferred the variant by exact type-id, the
// f64 temp matched the SIBLING field, and the program silently wrote
// `payload.b._0` while the tag named `a` (`x.a` read 0). After FF the literal
// is narrowed to the selected f32 field and the real variant is written.
const std = @import("std");

const S = union(enum) {
    a: f32,
    b: f64,
};

pub fn main() void {
    var x: S = S{ .a = 2.0 };
    var y: S = S{ .b = 2.5 };
    std.io.print("a={} b={}\n", .{ x.a, y.b });
}
