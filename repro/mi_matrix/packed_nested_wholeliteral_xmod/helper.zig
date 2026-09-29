// helper.zig — cross-module packed types for packed_nested_wholeliteral_xmod.
pub const Inner = packed struct { x: u2, y: u3 };
pub const Outer = packed struct { first: u3, inner: Inner, last: u1 };
