pub fn main() void { var v: u32 = 0; var r: ?u64 = switch(v) { 0 => @as(u32, 42), 1 => @as(u32, 0), else => @as(u32, 0), }; _ = r; }
