pub fn main() void {
    const x: usize = 10;
    const y: usize = 2;
    const z = x & ~(y - 1);
    _ = z;
}
