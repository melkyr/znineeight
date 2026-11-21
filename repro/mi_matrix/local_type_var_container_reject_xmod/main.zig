// local_type_var_container_reject_xmod — Task B2 final fix wave negative
// control: `var x = struct { ... };` binds a `type` value with `var`. Official
// Zig rejects this (a `type` value must be `const`/comptime); Z98 previously
// accepted it and emitted uncompilable C
// (`unknown type name 'zT_5127F14D_type'`).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3000]: a local type value must be declared with 'const'
fn f() void {
    var x = struct { a: u32 };
    _ = x;
}

pub fn main() void {
    f();
}
