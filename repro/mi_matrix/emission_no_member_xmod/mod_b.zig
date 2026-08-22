const std = @import("std");
const mod_a = @import("mod_a.zig");
const Type = mod_a.Type;
const TypeKind = mod_a.TypeKind;
const Registry = mod_a.Registry;

pub fn computeTypeLayout(reg: *Registry, ty: *Type) u32 {
    if (ty.kind == TypeKind.enum_type) {
        var ep = reg.enum_payload;
        var bt = ep.backing_type;
        return bt;
    } else if (ty.kind == TypeKind.error_union_type) {
        var ep = reg.eu_payload;
        var pt = ep.payload;
        return pt;
    }
    return 0;
}
