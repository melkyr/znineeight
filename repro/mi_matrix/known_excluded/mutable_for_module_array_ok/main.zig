// Off-corpus mutable-for fixture (Task 3 Step 1g): a module-member array
// aliases the global, so the capture is addressable -> --check rc=0.
const h = @import("helper.zig");

pub fn main() void {
    for (h.arr) |*x| {
        x.* = 1;
    }
}
