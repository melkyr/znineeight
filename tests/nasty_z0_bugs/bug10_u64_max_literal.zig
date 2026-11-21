// compile with: ./zig0 -o /tmp/repro.c tests/nasty_z0_bugs/bug10_u64_max_literal.zig
// check C output: grep '18446744073709551615\|~0ULL' /tmp/repro.c

pub fn main() void {
    // Workaround: bitwise NOT of zero gives max u64 as ~0ULL in C
    var x: u64 = ~@intCast(u64, 0);
    _ = x;
}
