pub fn main() void { var c: bool = true; var r: ??i32 = if (c) null else 0; _ = r; }
