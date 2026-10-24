// P3-M3 fix F3 fixture: one source line owns the whole loop, so resume must
// re-arm the breakpoint after stepping over the line's consecutive addresses.
var n: u32 = 0;

pub fn main() void {
    while (n < 3) { n = n + 1; }
    n = 99;
}
