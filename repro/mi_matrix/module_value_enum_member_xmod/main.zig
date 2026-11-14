// module_value_enum_member_xmod — enum member via a 2-level module alias.
//
// `mid.leaf.Color.green`: the base `mid.leaf.Color` is a TYPE reached through a
// nested module alias (type position, which already resolves), and `.green` is
// an enum-member value access on it. The member access lowers the whole base as
// a value and fails.
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d):
// `@enumToInt(c) == 1`; dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: error[3042] + warning[3023],
// dump rc=2, 0 `.c` (corpus classifier ICE).
// (`std.async.TaskState.ready` is the real-std instance of this shape.)
const mid = @import("mid.zig");

pub fn main() void {
    var c: mid.leaf.Color = mid.leaf.Color.green;
    if (@enumToInt(c) != 1) {
        @panic("module_value_enum_member_xmod: green mismatch");
    }
}
