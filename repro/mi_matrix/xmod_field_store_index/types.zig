const N: usize = 1;
pub const T = struct { arr: [N]struct { x: i32, }, };
pub fn init(t: *T) void { t.arr[0].x = 1; }
