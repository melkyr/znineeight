pub fn main() void { var c: bool = true; var r: ??i32 = if (c) 42 else null; _ = r; }
