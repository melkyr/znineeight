// w3000_enum_return — Task 0q3 promotion pin (INVALID Z98 -> hard error[3000]).
//
// enum -> integer at a RETURN position WITHOUT `@enumToInt` is invalid Zig/Z98
// (the spec exposes `@enumToInt(expr)` and defines no implicit enum->integer
// coercion). Task 0q left this tolerated at return/call-argument (`full=false`);
// Task 0q3 migrated the compiler's own 7 enum call-arg sites to
// `@intCast(u32, @enumToInt(...))` and dropped the `full and` guard on the
// enum shape (`sf/src/semantic_analyzer.zig`), so this is now a hard error.
//
// Expected (post-0q3): dump rc=2, 0 `.c`,
// `error[3000]: type mismatch in return statement` — source: enum / target: u32.
const E = enum { A, B };

fn f() u32 {
    return E.B;
}

pub fn main() void {
    var x = f();
    _ = x;
}
