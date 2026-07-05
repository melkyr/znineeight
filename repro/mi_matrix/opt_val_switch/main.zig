pub fn main() void { var v: u32 = 0; var r: ?i32 = switch(v) { 0 => @as(?i32, @as(i32, 42)), 1 => @as(?i32, @as(i32, 0)), else => @as(?i32, @as(i32, 0)), }; _ = r; }
