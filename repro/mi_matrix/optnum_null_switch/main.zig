pub fn main() void { var v: u32 = 0; var r: ?u64 = switch(v) { 0 => null, 1 => 0, else => 0, }; _ = r; }
