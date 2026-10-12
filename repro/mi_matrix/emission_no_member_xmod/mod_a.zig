const std = @import("std");

pub const TypeKind = enum(u32) {
    enum_type,
    error_union_type,
};

pub const EnumPayload = struct {
    backing_type: u32,
};

pub const EUPayload = struct {
    payload: u32,
};

pub const Type = struct {
    kind: TypeKind,
    payload_idx: u32,
};

pub const Registry = struct {
    enum_payload: EnumPayload,
    eu_payload: EUPayload,
};
