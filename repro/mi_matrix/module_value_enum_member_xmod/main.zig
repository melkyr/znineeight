// module_value_enum_member_xmod — enum member via a 2-level module alias.
//
// `mid.leaf.Color.green`: the base `mid.leaf.Color` is a TYPE reached through a
// nested module alias (type position, which already resolves), and `.green` is
// an enum-member value access on it. The member access lowers the whole base as
// a value and fails.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access
//   warning[3023]: module used as value expression
//   dump rc=2, 0 `.c`. Corpus classifier: ICE (`error[3042]`).
// (`std.async.TaskState.ready` is the real-std instance of this shape.)
//
// Expected GREEN contract: `@enumToInt(c) == 1`; dump rc=0, gcc clean,
// link+run rc=0, no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    var c: mid.leaf.Color = mid.leaf.Color.green;
    if (@enumToInt(c) != 1) {
        @panic("module_value_enum_member_xmod: green mismatch");
    }
}
