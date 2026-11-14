// w3000_enum_carg — Task 0q3 promotion pin (INVALID Z98 -> hard error[3000]).
//
// enum -> integer at a CALL-ARGUMENT position WITHOUT `@enumToInt` is invalid
// Zig/Z98. Task 0q left this tolerated at return/call-argument (`full=false`);
// Task 0q3 migrated the compiler's own 7 enum call-arg sites and dropped the
// `full and` guard on the enum shape (`sf/src/semantic_analyzer.zig`), so this
// is now a hard error.
//
// Expected (post-0q3): dump rc=2, 0 `.c`,
// `error[3000]: type mismatch in function argument` — source: enum / target: u32.
const E = enum { A, B };

fn g(x: u32) void {
    _ = x;
}

pub fn main() void {
    g(E.B);
}
