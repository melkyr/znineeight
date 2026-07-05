pub fn main() void { var v: u32 = 0; var r: ??i32 = switch(v) { 0 => @as(?i32, @as(i32, 42)), 1 => @as(?i32, null), else => @as(?i32, null), }; _ = r; }
