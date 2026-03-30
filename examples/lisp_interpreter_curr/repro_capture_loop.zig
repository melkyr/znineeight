const value_mod = @import("value.zig");
const util = @import("util.zig");

pub fn test_loop(params: *value_mod.Value) util.LispError!void {
    var cur_param = params;
    var i: usize = 0;
    while (i < 5) {
        var next_p: *value_mod.Value = undefined;
        var found = false;
        switch (cur_param.*) {
            .Cons => |cp_data| {
                next_p = cp_data.cdr;
                found = true;
            },
            else => {},
        }
        if (!found) return error.TooManyArgs;
        cur_param = next_p;
        i += 1;
    }
}

pub fn main() void {
    // This repros the complex loop pattern that was failing.
}
