pub const TokenKind = enum(u16) { eof, number, ident };

pub const TokenValue = union {
    int_val: u64,
    float_val: f64,
    string_id: u32,
    none: void,
};

// packed struct with union field is rejected by zig0
pub const Token = packed struct {
    kind: TokenKind,
    span_start: u32,
    span_len: u16,
    value: TokenValue,
};

pub fn main() void {}
