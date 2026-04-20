// examples/rogue_mud/test/lifetime_repro.zig
// This file demonstrates the lifetime violation bug and its workaround.

const List = struct {
    ptr: [*]u8,
    len: usize,
};

// ❌ This triggers: "error: lifetime violation: Returning pointer to local variable 'self.ptr' creates dangling pointer"
// To see the error, uncomment this function and its call in main.
/*
pub fn toSliceFails(self: *List) []u8 {
    return self.ptr[0..self.len];
}
*/

// ✅ This workaround bypasses the lifetime analyzer and works correctly.
pub fn toSliceWorks(self: *List, out: *[]u8) void {
    if (out != null) {
        out.* = self.ptr[0..self.len];
    }
}

pub fn main() void {
    var buf: [10]u8 = undefined;
    var list = List {
        .ptr = @ptrCast([*]u8, &buf[0]),
        .len = @intCast(usize, 10),
    };

    // var slice_fail = toSliceFails(&list);

    var slice_ok: []u8 = undefined;
    toSliceWorks(&list, &slice_ok);

    // Verify we can access the data
    slice_ok[0] = 42;
}
