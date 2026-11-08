// D13 sibling probe: duplicate tags at u64 max must reject as a duplicate
// (post-fix), not as a range limitation.
const E = enum(u64) {
    A = 18446744073709551615,
    B = 18446744073709551615,
};

pub fn main() void {
    _ = E.A;
}
