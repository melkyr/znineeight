// array_value_return_ok.zig — Task 9d fix-round negative fixture.
//
// Returning an array BY VALUE copies it out of the call frame, so it must not
// be reported as WARN_6010 ("returning pointer to local via variable"). The
// array local is tracked with the internal `local_array` marker, which only
// the slice arm maps back to `local` for WARN_6011.
fn makeArray() [2]u32 {
    var arr: [2]u32 = [2]u32{ 1, 2 };
    return arr;
}

pub fn main() void {
    _ = makeArray();
}
