// module_member_ok_xmod — accepted control for Task 3b-R.
//
// Same direct module-alias import shape as the reject fixture, but `answer`
// really exists and `triple` is a real member function call: rc 0 and at least
// one `.c`. The missing-member diagnostic must not disturb the accepted path.
const h = @import("helper.zig");

pub fn main() void {
    var x: i32 = h.answer;
    var y: i32 = h.triple(x);
    if (y != 126) {
        @panic("module_member_ok_xmod: triple mismatch");
    }
}
