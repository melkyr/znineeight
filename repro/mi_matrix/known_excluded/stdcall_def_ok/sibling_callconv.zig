// D5/D10 sibling probe: `callconv(...)` stays rejected (error[2000]).
fn cc(x: u32) callconv(.c) u32 {
    return x;
}

pub fn main() void {
    _ = cc;
}
