pub fn main() void { var x: usize = @sizeOf(*u8); var y: usize = @alignOf(*u8); _ = x; _ = y; }
