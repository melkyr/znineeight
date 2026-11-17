// module_member_ok_xmod — accepted control for Task 3b.
//
// Same direct module-alias import shape as the reject fixture, but `answer`
// really exists: rc 0 and at least one `.c`. The missing-member diagnostic
// must not disturb the accepted path.
const h = @import("helper.zig");

pub fn main() void {
    var x: i32 = h.answer;
    if (x != 42) {
        @panic("module_member_ok_xmod: answer mismatch");
    }
}
