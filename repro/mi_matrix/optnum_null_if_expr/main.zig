pub fn main() void { var c: bool = true; var r: ?u64 = if (c) null else 0; _ = r; }
