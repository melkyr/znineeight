pub fn main() void { var v: u32 = 0; var r: ?E!i32 = switch(v) { 0 => null, 1 => @as(E!i32, @as(i32, 0)), else => @as(E!i32, @as(i32, 0)), }; _ = r; }
