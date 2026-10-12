pub const Kind = enum(u8) { a, b };
pub const Type = struct { id: u32, kind: u32 };
pub const CoercionKind = enum(u8) { none, int_widen };

pub fn makeType() Type {
    return .{ .id = 0, .kind = 0 };
}

pub fn makeCoercion() CoercionKind {
    return .int_widen;
}
