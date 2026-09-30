// helper.zig — FX17-F reject fixture helper module.
//
// `wrongPtr` and the exported `WRONG` binding have a `fn (*i32) void`
// signature, so using them at a `fn (*void) void` site is a signature mismatch.
// `right`/`RIGHT` are the matching forms used by the positive control.
pub fn wrongPtr(data: *i32) void {
    _ = data;
}

pub fn right(data: *void) void {
    _ = data;
}

pub const WRONG: fn (*i32) void = wrongPtr;
pub const RIGHT: fn (*void) void = right;
