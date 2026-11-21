// local_type_alias_reject_xmod — Task B2 negative control: a function-local
// type alias (`const F = E;` where `E` is a function-local named type) is a
// documented divergence and clean-rejects.
//
// Official Zig allows a local `type` value bound by a `const`; this compiler
// does not model function-local `type` values, so rather than emit invalid C it
// emits a dedicated hard error and produces no `.c`.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3000]: local type aliases are not supported; bind the container
//   declaration directly
fn f() void {
    const E = enum(u8) { A = 1, B };
    const F = E;
    _ = F;
}

pub fn main() void {
    f();
}
