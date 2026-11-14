const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var reg = mod_a.Registry{
        .enum_payload = mod_a.EnumPayload{ .backing_type = 2 },
        .eu_payload = mod_a.EUPayload{ .payload = 3 },
    };
    var ty = mod_a.Type{ .kind = mod_a.TypeKind.error_union_type, .payload_idx = 0 };
    var r = mod_b.computeTypeLayout(&reg, &ty);
    std.io.printInt(@intCast(i32, r));
}
