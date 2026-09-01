pub fn main() void { var v: u32 = 0; var r: ??i32 = switch(v) { 0 => 42, 1 => null, else => null, }; _ = r; }
